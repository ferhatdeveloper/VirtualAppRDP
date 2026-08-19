<#
.SYNOPSIS
    Rdp Virtual Box App - application registry (apps.json + Start Menu shortcuts).

.DESCRIPTION
    Persists the list of installed RemoteApp applications to
    %LOCALAPPDATA%\RdpVirtualBoxApp\apps.json and creates Start Menu
    shortcuts for each application.

    Schema:
        {
          "version": "1.0",
          "updatedAt": "2026-01-01T12:00:00Z",
          "apps": [
            {
              "id": "erp",
              "name": "ERP Uygulaması",
              "remoteAppAlias": "||erp",
              "server": "192.168.0.106",
              "port": 3389,
              "rdpPath": "%USERPROFILE%\\Documents\\RdpVirtualBoxApp\\erp.rdp",
              "webUrl": null,
              "credentialTarget": "RdpVirtualBoxApp:192.168.0.106:erp",
              "credentialMode": "Save",
              "category": "erp",
              "registeredAt": "2026-01-01T12:00:00Z"
            }
          ]
        }

.NOTES
    Std : CmdletBinding, try/catch, Verbose, English comments.
    Exposed functions:
        Get-RegisteredApps, Register-App, Unregister-App, Update-App,
        Test-RegisteredApp, Get-AppRegistryPath
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

$script:AppRegistrySchemaVersion = '1.0'

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
function Get-AppRegistryPath {
    <#
    .SYNOPSIS  Returns the full path to apps.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'RdpVirtualBoxApp'
    return (Join-Path -Path $root -ChildPath 'apps.json')
}

function Get-AppRegistryRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'RdpVirtualBoxApp')
}

function Get-StartMenuShortcutPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $AppName)

    $shell = New-Object -ComObject WScript.Shell
    $startMenu = $shell.SpecialFolders.Item('Programs')
    $folder    = Join-Path -Path $startMenu -ChildPath 'RdpVirtualBoxApp'
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    return (Join-Path -Path $folder -ChildPath ("{0}.lnk" -f $AppName))
}

function Set-AppRegistryFile {
    [CmdletBinding()]
    param([string] $Path = (Get-AppRegistryPath))

    if (Test-Path -LiteralPath $Path) { return }
    $root = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    $seed = [pscustomobject]@{
        version   = $script:AppRegistrySchemaVersion
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        apps      = @()
    }
    ConvertTo-Json -InputObject $seed -Depth 6 | Out-File -FilePath $Path -Encoding utf8 -Force
}

# Backwards-compatible alias for PSScriptAnalyzer PSUseApprovedVerbs compliance
Set-Alias -Name Initialize-AppRegistryFile -Value Set-AppRegistryFile -Scope Global -Force

# ---------------------------------------------------------------------------
# Internal read/write helpers (serialized with a mutex-style temp file)
# ---------------------------------------------------------------------------
function Read-AppRegistry {
    [CmdletBinding()]
    [OutputType([psobject])]
    param([string] $Path = (Get-AppRegistryPath))

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Set-AppRegistryFile -Path $Path
        }
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Error -ErrorRecord $_
        return $null
    }
}

function Write-AppRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Document,
        [string] $Path = (Get-AppRegistryPath)
    )

    try {
        $tmp = "$Path.tmp"
        $Document.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        ConvertTo-Json -InputObject $Document -Depth 8 | Out-File -FilePath $tmp -Encoding utf8 -Force
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        Write-Error -ErrorRecord $_
    }
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function Get-RegisteredApps {
    <#
    .SYNOPSIS  Returns the list of registered apps.
    .DESCRIPTION
        If -Id is supplied, returns the matching app object or $null.
        Otherwise returns the array of apps.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [string] $Id,
        [string] $Path = (Get-AppRegistryPath)
    )

    $doc = Read-AppRegistry -Path $Path
    if ($null -eq $doc) { return $null }

    if (-not $doc.apps) { $doc.apps = @() }

    if ($Id) {
        foreach ($a in $doc.apps) {
            if ($a.id -eq $Id) { return $a }
        }
        return $null
    }
    return @($doc.apps)
}

function Register-App {
    <#
    .SYNOPSIS  Registers an application: appends to apps.json and creates
                a Start Menu shortcut pointing at the .rdp file.
    .PARAMETER RdpPath  Path to the generated .rdp file.
    .PARAMETER WebUrl   Optional HTML5 URL.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Server,
        [int]    $Port = 3389,
        [string] $RemoteAppAlias,
        [Parameter(Mandatory)][string] $RdpPath,
        [string] $WebUrl,
        [ValidateSet('Ask','Save','Embed')]
        [string] $CredentialMode = 'Ask',
        [string] $Category = 'custom',
        [string] $IconPath
    )

    try {
        if ($PSCmdlet.ShouldProcess($Id, 'Register application')) {
            $doc = Read-AppRegistry
            if (-not $doc.apps) { $doc.apps = @() }

            # Replace if already present.
            $existingIdx = -1
            for ($i = 0; $i -lt $doc.apps.Count; $i++) {
                if ($doc.apps[$i].id -eq $Id) { $existingIdx = $i; break }
            }

            $entry = [ordered]@{
                id               = $Id
                name             = $Name
                remoteAppAlias   = $RemoteAppAlias
                server           = $Server
                port             = $Port
                rdpPath          = $RdpPath
                webUrl           = if ([string]::IsNullOrEmpty($WebUrl)) { $null } else { $WebUrl }
                credentialTarget = (Format-StoredCredentialTarget -Server $Server -AppId $Id)
                credentialMode   = $CredentialMode
                category         = $Category
                registeredAt     = (Get-Date).ToUniversalTime().ToString('o')
            }
            $entryObj = [pscustomobject]$entry

            if ($existingIdx -ge 0) {
                $doc.apps[$existingIdx] = $entryObj
            } else {
                $doc.apps += $entryObj
            }
            Write-AppRegistry -Document $doc

            # Start Menu shortcut.
            $shortcutPath = Get-StartMenuShortcutPath -AppName $Name
            $shell  = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath   = $RdpPath
            $shortcut.WorkingDirectory = (Split-Path -Parent $RdpPath)
            $shortcut.WindowStyle  = 3
            $shortcut.IconLocation = if ($IconPath) { "$IconPath,0" } else { "%SystemRoot%\system32\mstsc.exe,0" }
            $shortcut.Description  = "Rdp Virtual Box App - $Name"
            $shortcut.Save()

            Write-Verbose ("Registered app '{0}' -> {1}" -f $Id, $shortcutPath)
            return $entryObj
        }
    } catch {
        Write-Error -ErrorRecord $_
    }
    return $null
}

function Unregister-App {
    <#
    .SYNOPSIS  Removes an app from apps.json and deletes its Start Menu shortcut.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Id,
        [switch] $RemoveShortcutOnly,
        [switch] $RemoveRegistryOnly,
        [string] $Path = (Get-AppRegistryPath)
    )

    try {
        $doc = Read-AppRegistry -Path $Path
        if (-not $doc) { return $false }
        $app = $null
        for ($i = 0; $i -lt $doc.apps.Count; $i++) {
            if ($doc.apps[$i].id -eq $Id) { $app = $doc.apps[$i]; break }
        }
        if (-not $app) { return $false }

        if (-not $RemoveRegistryOnly) {
            try {
                $shortcutPath = Get-StartMenuShortcutPath -AppName $app.name
                if (Test-Path -LiteralPath $shortcutPath) {
                    if ($PSCmdlet.ShouldProcess($shortcutPath, 'Delete Start Menu shortcut')) {
                        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
                    }
                }
            } catch {
                Write-Verbose ("Shortcut removal failed: {0}" -f $_.Exception.Message)
            }
        }

        if (-not $RemoveShortcutOnly) {
            if ($PSCmdlet.ShouldProcess($Id, 'Remove from apps.json')) {
                $remaining = @($doc.apps | Where-Object { $_.id -ne $Id })
                $doc.apps = $remaining
                Write-AppRegistry -Document $doc -Path $Path
            }
        }
        Write-Verbose ("Unregistered app '{0}'." -f $Id)
        return $true
    } catch {
        Write-Error -ErrorRecord $_
        return $false
    }
}

function Update-App {
    <#
    .SYNOPSIS  Updates an existing app record (merge semantics).
    .DESCRIPTION
        Accepts a hashtable of fields to merge into the existing app entry.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][hashtable] $Properties,
        [string] $Path = (Get-AppRegistryPath)
    )

    try {
        $doc = Read-AppRegistry -Path $Path
        if (-not $doc) { return $null }
        $idx = -1
        for ($i = 0; $i -lt $doc.apps.Count; $i++) {
            if ($doc.apps[$i].id -eq $Id) { $idx = $i; break }
        }
        if ($idx -lt 0) { return $null }

        if ($PSCmdlet.ShouldProcess($Id, 'Update application record')) {
            $existing = $doc.apps[$idx]
            $merged = [ordered]@{}
            foreach ($prop in $existing.PSObject.Properties) { $merged[$prop.Name] = $prop.Value }
            foreach ($key in $Properties.Keys) { $merged[$key] = $Properties[$key] }
            $merged.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
            $doc.apps[$idx] = [pscustomobject]$merged
            Write-AppRegistry -Document $doc -Path $Path
            return $doc.apps[$idx]
        }
    } catch {
        Write-Error -ErrorRecord $_
    }
    return $null
}

function Test-RegisteredApp {
    <#
    .SYNOPSIS  Returns $true when the given app id is registered.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Id)

    return ($null -ne (Get-RegisteredApps -Id $Id))
}

# ---------------------------------------------------------------------------
# Fallback for Format-StoredCredentialTarget (so this module works even
# when Credential.ps1 hasn't been dot-sourced yet).
# ---------------------------------------------------------------------------
if (-not (Get-Command -Name 'Format-StoredCredentialTarget -ErrorAction SilentlyContinue')) {
    function Format-StoredCredentialTarget {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)][string] $Server,
            [Parameter(Mandatory)][AllowEmptyString()][string] $AppId = ''
        )
        $parts = @('RdpVirtualBoxApp', $Server.Trim())
        if (-not [string]::IsNullOrEmpty($AppId)) { $parts += $AppId }
        return ($parts -join ':')
    }
}

# ---------------------------------------------------------------------------
# Module exports (when dot-sourced as a .psm1)
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'Get-RegisteredApps',
        'Register-App',
        'Unregister-App',
        'Update-App',
        'Test-RegisteredApp',
        'Get-AppRegistryPath',
        'Get-AppRegistryRoot'
    )
}