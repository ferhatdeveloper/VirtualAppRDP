<#
.SYNOPSIS
    Installs Remote Desktop Services (RDS) roles on a Windows Server.

.DESCRIPTION
    Performs a silent installation of selected RDS features using
    Install-WindowsFeature. Supports Session Host, Web Access, Gateway and
    Licensing roles plus management tools. Provides automatic rollback via
    Uninstall-WindowsFeature when an installation step fails.

.PARAMETER Features
    One or more RDS feature names to install. Accepts aliases that are
    translated to their canonical Windows feature names.

.PARAMETER IncludeManagementTools
    When set, management tools (MMC snap-ins, PowerShell module) are
    installed alongside the requested features.

.PARAMETER AutoRestart
    When set, the server is rebooted automatically if the installation
    returns the "restart required" exit code.

.PARAMETER LogPath
    Optional path to a log file. Defaults to
    "$env:ProgramData\RdpVirtualBoxApp\Logs\rds-installer.log".

.EXAMPLE
    Install-RdsRole -Features 'RDS-RD-Server','RDS-Web-Access','RDS-Gateway','RDS-Licensing' -IncludeManagementTools -AutoRestart

.NOTES
    Author : Rdp Virtual Box App
    Module  : RdsInstaller.ps1
    Tags    : RDS, RemoteDesktop, Setup
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Features,

    [Parameter()]
    [switch]$IncludeManagementTools,

    [Parameter()]
    [switch]$AutoRestart,

    [Parameter()]
    [string]$LogPath
)

# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------
$script:RdsFeatureAliases = @{
    'RDS-RD-Server'         = 'RDS-RD-Server'
    'SessionHost'           = 'RDS-RD-Server'
    'RDS-Web-Access'        = 'RDS-Web-Access'
    'WebAccess'             = 'RDS-Web-Access'
    'RDS-Gateway'           = 'RDS-Gateway'
    'Gateway'               = 'RDS-Gateway'
    'RDS-Licensing'         = 'RDS-Licensing'
    'Licensing'             = 'RDS-Licensing'
    'RDS-Connection-Broker' = 'RDS-Connection-Broker'
    'ConnectionBroker'      = 'RDS-Connection-Broker'
}

function Resolve-RdsFeatureName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($script:RdsFeatureAliases.ContainsKey($Name)) {
        return $script:RdsFeatureAliases[$Name]
    }

    return $Name
}

function Initialize-RdsInstallerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $logDir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

function Write-RdsInstallerLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    $line = "[$timestamp] [$Level] $Message"

    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8

    switch ($Level) {
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning   $Message }
        'Error'   { Write-Error     $Message }
        'Debug'   { Write-Debug     $Message }
    }
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function Install-RdsRole {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Features,

        [Parameter()]
        [switch]$IncludeManagementTools,

        [Parameter()]
        [switch]$AutoRestart,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\rds-installer.log'
    }

    Initialize-RdsInstallerLog -Path $LogPath
    $script:LogPath = $LogPath

    $installed = New-Object System.Collections.Generic.List[string]
    $failed    = New-Object System.Collections.Generic.List[object]
    $rolled    = New-Object System.Collections.Generic.List[string]

    $resolvedFeatures = foreach ($f in $Features) { Resolve-RdsFeatureName -Name $f }

    Write-RdsInstallerLogEntry -Message ("Starting RDS installation. Requested: " + ($Features -join ', '))
    Write-RdsInstallerLogEntry -Message ("Resolved Windows features: " + ($resolvedFeatures -join ', '))

    if ($PSCmdlet.ShouldProcess('local computer', "Install RDS features [$($resolvedFeatures -join ', ')]")) {
        foreach ($feature in $resolvedFeatures) {
            try {
                Write-RdsInstallerLogEntry -Message "Installing feature: $feature"

                $installArgs = @{
                    Name                  = $feature
                    ErrorAction           = 'Stop'
                }

                if ($IncludeManagementTools) {
                    $installArgs['IncludeManagementTools'] = $true
                }

                $result = Install-WindowsFeature @installArgs

                if ($null -eq $result) {
                    throw "Install-WindowsFeature returned no result for $feature."
                }

                Write-RdsInstallerLogEntry -Message ("Install-WindowsFeature '{0}' -> Success={1}, ExitCode={2}, RestartNeeded={3}" -f $feature, $result.Success, $result.ExitCode, $result.RestartNeeded)

                if (-not $result.Success) {
                    $failed.Add([PSCustomObject]@{ Feature = $feature; ExitCode = $result.ExitCode; Message = 'Install-WindowsFeature reported failure' })
                    break
                }

                $installed.Add($feature)

                if ($result.RestartNeeded -and -not $AutoRestart) {
                    Write-RdsInstallerLogEntry -Level Warning -Message "Restart required after installing $feature. AutoRestart is not enabled."
                }
            }
            catch {
                $err = $_.Exception.Message
                Write-RdsInstallerLogEntry -Level Error -Message "Failed to install $feature : $err"
                $failed.Add([PSCustomObject]@{ Feature = $feature; ExitCode = -1; Message = $err })
                break
            }
        }

        # Rollback any partially installed features when at least one failed.
        if ($failed.Count -gt 0 -and $installed.Count -gt 0) {
            Write-RdsInstallerLogEntry -Level Warning -Message 'Initiating rollback for partially installed features.'

            foreach ($feature in $installed) {
                try {
                    if (Uninstall-RdsRole -Features $feature -LogPath $LogPath -ErrorAction Stop) {
                        $rolled.Add($feature)
                    }
                }
                catch {
                    Write-RdsInstallerLogEntry -Level Error -Message "Rollback failed for $feature : $($_.Exception.Message)"
                }
            }
        }

        $success = ($failed.Count -eq 0)
        $restartPending = $false
        foreach ($feature in $resolvedFeatures) {
            $state = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
            if ($state -and $state.InstallState -eq 'InstallPending') {
                $restartPending = $true
                break
            }
        }

        $summary = [PSCustomObject]@{
            Success        = $success
            Installed      = $installed.ToArray()
            Failed         = $failed.ToArray()
            RolledBack     = $rolled.ToArray()
            RestartPending = $restartPending
            LogPath        = $LogPath
        }

        if ($AutoRestart -and $restartPending -and $success) {
            Write-RdsInstallerLogEntry -Level Warning -Message 'Rebooting computer because restart is pending and AutoRestart was requested.'
            try {
                Restart-Computer -Force
            }
            catch {
                Write-RdsInstallerLogEntry -Level Error -Message "Restart-Computer failed: $($_.Exception.Message)"
            }
        }

        if (-not $success) {
            throw "RDS installation failed. See log for details: $LogPath"
        }

        return $summary
    }
}

function Uninstall-RdsRole {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Features,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\rds-installer.log'
    }

    Initialize-RdsInstallerLog -Path $LogPath
    $script:LogPath = $LogPath

    $resolved = foreach ($f in $Features) { Resolve-RdsFeatureName -Name $f }
    $results = New-Object System.Collections.Generic.List[object]

    if ($PSCmdlet.ShouldProcess('local computer', "Uninstall RDS features [$($resolved -join ', ')]")) {
        foreach ($feature in $resolved) {
            try {
                Write-RdsInstallerLogEntry -Message "Uninstalling feature: $feature"

                $r = Uninstall-WindowsFeature -Name $feature -ErrorAction Stop -Remove
                $results.Add([PSCustomObject]@{ Feature = $feature; Success = $r.Success; ExitCode = $r.ExitCode })

                if (-not $r.Success) {
                    Write-RdsInstallerLogEntry -Level Error -Message "Uninstall failed for $feature (ExitCode=$($r.ExitCode))"
                }
            }
            catch {
                Write-RdsInstallerLogEntry -Level Error -Message "Uninstall exception for $feature : $($_.Exception.Message)"
                $results.Add([PSCustomObject]@{ Feature = $feature; Success = $false; ExitCode = -1 })
            }
        }

        return $results.ToArray()
    }
}

function Get-RdsRoleState {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Features
    )

    if (-not $Features) {
        $Features = @('RDS-RD-Server', 'RDS-Web-Access', 'RDS-Gateway', 'RDS-Licensing', 'RDS-Connection-Broker')
    }

    $resolved = foreach ($f in $Features) { Resolve-RdsFeatureName -Name $f }

    $report = foreach ($feature in $resolved) {
        $state = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
        if ($state) {
            [PSCustomObject]@{
                Name         = $feature
                DisplayName  = $state.DisplayName
                InstallState = $state.InstallState.ToString()
                Installed    = ($state.InstallState -eq 'Installed')
            }
        }
        else {
            [PSCustomObject]@{
                Name         = $feature
                DisplayName  = 'Unknown'
                InstallState = 'Unknown'
                Installed    = $false
            }
        }
    }

    return $report
}

Export-ModuleMember -Function @(
    'Install-RdsRole',
    'Uninstall-RdsRole',
    'Get-RdsRoleState'
)