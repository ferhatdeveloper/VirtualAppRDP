#requires -Version 5.1
<#
.SYNOPSIS
    Publishes the executables discovered by AppScanner.ps1 as RemoteApps
    inside a Remote Desktop Services collection.

.DESCRIPTION
    RemoteAppPublisher.ps1 consumes the JSON catalogue produced by
    AppScanner.ps1 and, for each application, ensures a matching RemoteApp
    exists on the target collection. The module is idempotent: existing
    RemoteApps are updated instead of duplicated and a rollback function is
    exposed for use by higher-level orchestrators.

    The module relies on the RemoteDesktop PowerShell module
    (RemoteDesktop.psd1) which ships with the RDS-Session-Host role. When
    the module is not present, a clear error is reported rather than a
    cryptic cmdlet-not-found.

.PARAMETER CollectionName
    Name of the Session Collection that owns the RemoteApps.

.PARAMETER ConnectionBroker
    FQDN of the Connection Broker server. When omitted the local server is
    assumed.

.PARAMETER Apps
    JSON string or array of objects produced by AppScanner.ps1.

.PARAMETER MaxSessions
    Maximum concurrent sessions for the session host.

.PARAMETER IdleTimeoutMinutes
    Idle session timeout, in minutes.

.PARAMETER EndDisconnectTimeoutMinutes
    End-of-session disconnect timeout, in minutes.

.EXAMPLE
    $json = .\AppScanner.ps1
    .\RemoteAppPublisher.ps1 -Apps $json -CollectionName 'RdpVirtualBoxApp'

.NOTES
    Author : Rdp Virtual Box App - Server-side agent S2
    License: MIT
#>
[CmdletBinding()]
param(
    [string] $CollectionName           = 'RdpVirtualBoxApp',
    [string] $ConnectionBroker         = '',
    [Parameter(Mandatory)] $Apps,
    [int]    $MaxSessions              = 50,
    [int]    $IdleTimeoutMinutes       = 30,
    [int]    $EndDisconnectTimeoutMinutes = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Test-RemoteDesktopModule {
    <#
    .SYNOPSIS
        Verifies the RemoteDesktop module is importable on this host.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Get-Module -ListAvailable -Name RemoteDesktop) {
        return $true
    }
    Write-Warning "RemoteDesktop module not found. Install the RDS-Session-Host role or run Install-WindowsFeature RemoteDesktopServices."
    return $false
}

function Import-RemoteDesktopModule {
    <#
    .SYNOPSIS
        Loads the RemoteDesktop module and returns whether it succeeded.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not (Test-RemoteDesktopModule)) { return $false }
    try {
        Import-Module RemoteDesktop -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Failed to import RemoteDesktop: $($_.Exception.Message)"
        return $false
    }
}

function ConvertTo-AppObject {
    <#
    .SYNOPSIS
        Normalises the -Apps parameter into an array of PSCustomObject items.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)] $InputObject)

    if ($null -eq $InputObject) { return @() }

    if ($InputObject -is [string]) {
        $InputObject = $InputObject.Trim()
        if ([string]::IsNullOrWhiteSpace($InputObject)) { return @() }
        return ,(ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop)
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject)
    }

    return ,@($InputObject)
}

function Resolve-RemoteAppAlias {
    <#
    .SYNOPSIS
        Derives a RemoteApp alias from the executable name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Executable)

    if ([string]::IsNullOrWhiteSpace($Executable)) { return $Executable }
    return ($Executable -replace '\.exe$', '').Trim()
}

function Get-ExistingRemoteApp {
    <#
    .SYNOPSIS
        Returns the RemoteApp matching the alias, or $null when not found.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Collection,
        [Parameter(Mandatory)] [string] $Alias,
        [string] $Broker
    )

    $params = @{
        CollectionName = $Collection
        Alias           = $Alias
        ErrorAction     = 'SilentlyContinue'
    }
    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $params['ConnectionBroker'] = $Broker
    }
    return Get-RDRemoteApp @params
}

function New-RemoteAppEntry {
    <#
    .SYNOPSIS
        Creates a RemoteApp inside the given collection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]   $App,
        [Parameter(Mandatory)] [string]   $Collection,
        [string]                          $Broker
    )

    $alias = Resolve-RemoteAppAlias -Executable (Split-Path -Path $App.path -Leaf)
    $params = @{
        CollectionName      = $Collection
        FilePath            = $App.path
        Alias               = $alias
        DisplayName         = if ($App.PSObject.Properties.Match('name').Count -and $App.name) { $App.name } else { $alias }
        FriendlyName        = if ($App.PSObject.Properties.Match('name').Count -and $App.name) { $App.name } else { $alias }
        IconPath            = if ($App.PSObject.Properties.Match('icon').Count) { $App.icon } else { $null }
        ShowInWebAccess     = $true
        CommandLineSetting  = 'Allow'
        RequiredCommandLine = ''
    }

    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $params['ConnectionBroker'] = $Broker
    }

    try {
        $created = New-RDRemoteApp @params -ErrorAction Stop
        Write-Verbose "Created RemoteApp '$alias' in collection '$Collection'."
        return [pscustomobject]@{ Alias = $alias; Status = 'Created'; Object = $created }
    } catch {
        Write-Warning "New-RDRemoteApp failed for '$alias': $($_.Exception.Message)"
        return [pscustomobject]@{ Alias = $alias; Status = 'Failed';  Error  = $_.Exception.Message }
    }
}

function Update-RemoteAppEntry {
    <#
    .SYNOPSIS
        Refreshes a RemoteApp when its underlying executable has changed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $App,
        [Parameter(Mandatory)] [string] $Collection,
        [Parameter(Mandatory)] [object] $Existing,
        [string]                 $Broker
    )

    $alias = $Existing.Alias
    $params = @{
        CollectionName = $Collection
        Alias          = $alias
        FilePath       = $App.path
        DisplayName    = if ($App.PSObject.Properties.Match('name').Count -and $App.name) { $App.name } else { $alias }
        ErrorAction    = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $params['ConnectionBroker'] = $Broker
    }

    try {
        Set-RDRemoteApp @params | Out-Null
        Write-Verbose "Updated RemoteApp '$alias' (collection '$Collection')."
        return [pscustomobject]@{ Alias = $alias; Status = 'Updated' }
    } catch {
        Write-Warning "Set-RDRemoteApp failed for '$alias': $($_.Exception.Message)"
        return [pscustomobject]@{ Alias = $alias; Status = 'Failed'; Error = $_.Exception.Message }
    }
}

function Set-RemoteAppSessionHostConfig {
    <#
    .SYNOPSIS
        Applies session host configuration (max sessions and timeouts).
    #>
    [CmdletBinding()]
    param(
        [string] $Collection,
        [int]    $MaxSessions,
        [int]    $IdleMinutes,
        [int]    $DisconnectMinutes,
        [string] $Broker
    )

    $setParams = @{
        CollectionName = $Collection
        MaxSessions    = $MaxSessions
        ErrorAction    = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $setParams['ConnectionBroker'] = $Broker
    }

    try {
        Set-RDSessionHostConfiguration @setParams | Out-Null
        Write-Verbose ("Applied session host config: MaxSessions={0}, Idle={1}min, Disconnect={2}min" -f `
            $MaxSessions, $IdleMinutes, $DisconnectMinutes)
    } catch {
        Write-Warning "Set-RDSessionHostConfiguration failed: $($_.Exception.Message)"
    }
}

function Get-RemoteAppCollectionStatus {
    <#
    .SYNOPSIS
        Returns a summary object with collection and session host info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Collection,
        [string] $Broker
    )

    $status = [pscustomobject]@{
        CollectionExists  = $false
        Collection        = $null
        SessionHosts      = @()
        PublishedRemoteApps = @()
    }

    $collectionParams = @{ CollectionName = $Collection; ErrorAction = 'SilentlyContinue' }
    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $collectionParams['ConnectionBroker'] = $Broker
    }
    $coll = Get-RDCollection @collectionParams
    if ($coll) {
        $status.CollectionExists = $true
        $status.Collection       = $coll

        $hostParams = @{ CollectionName = $Collection; ErrorAction = 'SilentlyContinue' }
        if (-not [string]::IsNullOrWhiteSpace($Broker)) {
            $hostParams['ConnectionBroker'] = $Broker
        }
        $status.SessionHosts = @(Get-RDSessionHost @hostParams)

        $appParams = @{ CollectionName = $Collection; ErrorAction = 'SilentlyContinue' }
        if (-not [string]::IsNullOrWhiteSpace($Broker)) {
            $appParams['ConnectionBroker'] = $Broker
        }
        $status.PublishedRemoteApps = @(Get-RDRemoteApp @appParams | Select-Object -ExpandProperty Alias)
    }

    return $status
}

function Publish-RemoteAppFromApp {
    <#
    .SYNOPSIS
        Public orchestration entry point: ensures a RemoteApp exists for
        every application descriptor provided.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] $ApplicationList,
        [Parameter(Mandatory)] [string] $Collection,
        [string] $Broker
    )

    $apps = ConvertTo-AppObject -InputObject $ApplicationList
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($app in $apps) {
        if (-not ($app.PSObject.Properties.Match('path').Count) -or [string]::IsNullOrWhiteSpace($app.path)) {
            Write-Warning "Skipping app without path: $($app | ConvertTo-Json -Compress)"
            $results.Add([pscustomobject]@{ Alias = $null; Status = 'Skipped'; Error = 'missing path' })
            continue
        }

        $alias = Resolve-RemoteAppAlias -Executable (Split-Path -Path $app.path -Leaf)
        $existing = Get-ExistingRemoteApp -Collection $Collection -Alias $alias -Broker $Broker

        if ($existing) {
            $results.Add((Update-RemoteAppEntry -App $app -Collection $Collection -Existing $existing -Broker $Broker))
        } else {
            $results.Add((New-RemoteAppEntry -App $app -Collection $Collection -Broker $Broker))
        }
    }

    return ,$results
}

function Remove-RemoteAppRollback {
    <#
    .SYNOPSIS
        Removes a published RemoteApp by alias. Used by orchestrators that
        need to roll back a partial publish.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Alias,
        [Parameter(Mandatory)] [string] $Collection,
        [string] $Broker
    )

    $params = @{
        CollectionName = $Collection
        Alias          = $Alias
        Force          = $true
        ErrorAction    = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($Broker)) {
        $params['ConnectionBroker'] = $Broker
    }

    Remove-RDRemoteApp @params
    Write-Verbose "Rolled back RemoteApp '$Alias' from collection '$Collection'."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
try {
    if (-not (Import-RemoteDesktopModule)) {
        throw "RemoteDesktop module unavailable; RemoteAppPublisher cannot continue."
    }

    $broker = if ([string]::IsNullOrWhiteSpace($ConnectionBroker)) { $null } else { $ConnectionBroker }
    $resolvedBroker = if ($broker) { $broker } else { $env:COMPUTERNAME }

    Write-Verbose ("Publishing RemoteApps into collection '{0}' on broker '{1}'" -f $CollectionName, $resolvedBroker)

    Set-RemoteAppSessionHostConfig -Collection $CollectionName -MaxSessions $MaxSessions `
        -IdleMinutes $IdleTimeoutMinutes -DisconnectMinutes $EndDisconnectTimeoutMinutes -Broker $broker

    $publishResults = Publish-RemoteAppFromApp -ApplicationList $Apps -Collection $CollectionName -Broker $broker

    $status = Get-RemoteAppCollectionStatus -Collection $CollectionName -Broker $broker

    return [pscustomobject]@{
        Collection     = $CollectionName
        Broker         = $resolvedBroker
        PublishResults = $publishResults
        Status         = $status
    }
} catch {
    Write-Error "RemoteAppPublisher failed: $($_.Exception.Message)"
    return $null
}

Export-ModuleMember -Function @(
    'Publish-RemoteAppFromApp'
    'Get-RemoteAppCollectionStatus'
    'Remove-RemoteAppRollback'
    'Resolve-RemoteAppAlias'
    'ConvertTo-AppObject'
) -ErrorAction SilentlyContinue