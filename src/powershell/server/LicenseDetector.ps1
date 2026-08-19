<#
.SYNOPSIS
    Detects the RD Web Access licensing status on a Windows Server.

.DESCRIPTION
    Inspects the local RDS Licensing role, RD License Server configuration and
    the term-service grace period registry keys to determine whether the host
    is allowed to publish RD Web Access resources. Used by the server-side
    wizard to pick between "Use RD Web" and "Install Guacamole" as the HTML5
    fallback strategy.

    Scenarios handled:
      1. RDS-Licensing feature installed AND Get-RDLicenseConfiguration reports
         an activated license server -> HasRdWebLicense = $true.
      2. Role missing or no activated license server -> HasRdWebLicense = $false.
      3. 120-day grace period active -> HasRdWebLicense = $false with a
         LICENSE_REQUIRED recommendation.

.PARAMETER LicenseServerHint
    Optional FQDN/IP of the license server the operator expects to be in use.
    Used only to enrich the LicenseServer property of the result object.

.OUTPUTS
    PSCustomObject with the shape:
        HasRdWebLicense   [bool]
        GracePeriodDays   [int]
        LicenseServer     [string]
        Recommendation    [string]   'Use RD Web' | 'Install Guacamole'
        Detail            [string]

.EXAMPLE
    $result = & "$PSScriptRoot\LicenseDetector.ps1"
    if (-not $result.HasRdWebLicense) { Install-Guacamole }

.NOTES
    Author : Rdp Virtual Box App - Server Side (Agent S3)
    Module  : src/powershell/server/LicenseDetector.ps1
    Run on : Windows Server 2016/2019/2022 with elevated PowerShell.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$LicenseServerHint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:TermServiceLicenseKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters\License'
$script:DefaultGracePeriodDays = 120
$script:LogFile = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\license-detector.log'

function Write-LicenseLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO','WARN','ERROR')] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    try {
        $logDir = Split-Path -Path $script:LogFile -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $entry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8
    } catch {
        # Logging is best-effort; never fail the caller because of a log write.
    }

    switch ($Level) {
        'INFO'  { Write-Verbose $Message }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
    }
}

function Test-RdsLicensingRoleInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $feature = Get-WindowsFeature -Name 'RDS-Licensing' -ErrorAction Stop
        return ($feature -and $feature.InstallState -eq 'Installed')
    } catch {
        Write-LicenseLog -Level WARN -Message "Get-WindowsFeature RDS-Licensing failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-RdLicenseServerConfiguration {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    try {
        $cmd = Get-Command -Name 'Get-RDLicenseConfiguration' -ErrorAction Stop
        return & $cmd -ErrorAction Stop
    } catch {
        Write-LicenseLog -Level WARN -Message "Get-RDLicenseConfiguration unavailable: $($_.Exception.Message)"
        return $null
    }
}

function Get-TermServiceGraceDays {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        if (-not (Test-Path -Path $script:TermServiceLicenseKey)) {
            Write-LicenseLog -Level INFO -Message "TermService license registry key not found at $script:TermServiceLicenseKey"
            return 0
        }

        $props = Get-ItemProperty -Path $script:TermServiceLicenseKey -ErrorAction SilentlyContinue
        if ($null -eq $props) {
            return 0
        }

        # The grace period may be stored under several names depending on the
        # Windows version. Pick the first one that resolves to a positive int.
        $candidateNames = @('GracePeriod', 'RemainingGracePeriodDays', 'LlsGracePeriod', 'SpecifiedLicenseServerList')
        foreach ($name in $candidateNames) {
            $value = $props.$name
            if ($null -ne $value) {
                $asInt = 0
                if ([int]::TryParse([string]$value, [ref]$asInt) -and $asInt -gt 0) {
                    return $asInt
                }
            }
        }

        return 0
    } catch {
        Write-LicenseLog -Level WARN -Message "Reading TermService license registry failed: $($_.Exception.Message)"
        return 0
    }
}

function Resolve-LicenseServer {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($LicenseServerHint)) {
        return $LicenseServerHint
    }

    try {
        $config = Get-RdLicenseServerConfiguration
        if ($config) {
            foreach ($propName in @('LicenseServer','SpecifiedLicenseServer','LicenseServerName')) {
                $value = $config.$propName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return [string]$value
                }
            }
        }
    } catch {
        Write-LicenseLog -Level WARN -Message "Could not resolve license server name from RD configuration."
    }

    return ''
}

function New-LicenseDetectionResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [bool]$HasRdWebLicense,
        [Parameter(Mandatory)] [int]$GracePeriodDays,
        [Parameter(Mandatory)] [string]$LicenseServer,
        [Parameter(Mandatory)] [string]$Recommendation,
        [Parameter(Mandatory)] [string]$Detail
    )

    [pscustomobject]@{
        HasRdWebLicense = $HasRdWebLicense
        GracePeriodDays = $GracePeriodDays
        LicenseServer   = $LicenseServer
        Recommendation  = $Recommendation
        Detail          = $Detail
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Write-LicenseLog -Level INFO -Message 'License detection started.'

    $roleInstalled = Test-RdsLicensingRoleInstalled
    $rdConfig      = Get-RdLicenseServerConfiguration
    $graceDays     = Get-TermServiceGraceDays
    $licenseServer = Resolve-LicenseServer

    $activated = $false
    if ($rdConfig) {
        foreach ($flagName in @('Activated','IsActivated','LicenseActivated')) {
            if ($null -ne $rdConfig.$flagName) {
                $activated = [bool]$rdConfig.$flagName
                break
            }
        }
    }

    $hasLicense = ($roleInstalled -and $activated)

    if ($hasLicense) {
        $detail = 'RDS-Licensing role is installed and the license server reports an activated configuration.'
        $rec    = 'Use RD Web'
        Write-LicenseLog -Level INFO -Message $detail
        return New-LicenseDetectionResult -HasRdWebLicense $true -GracePeriodDays $graceDays -LicenseServer $licenseServer -Recommendation $rec -Detail $detail
    }

    # No activated license. Decide whether we are inside the grace period.
    if ($graceDays -gt 0 -and $graceDays -le $script:DefaultGracePeriodDays) {
        $detail = "LISANS GEREKLI: No activated RD license found. Approximately $graceDays day(s) of grace period remain before RD Web Access will stop accepting connections."
        $rec    = 'Install Guacamole'
        Write-LicenseLog -Level WARN -Message $detail
        return New-LicenseDetectionResult -HasRdWebLicense $false -GracePeriodDays $graceDays -LicenseServer $licenseServer -Recommendation $rec -Detail $detail
    }

    $detail = 'No RDS-Licensing role installed or no activated license server detected. RD Web Access cannot be published without a license.'
    $rec    = 'Install Guacamole'
    Write-LicenseLog -Level WARN -Message $detail
    return New-LicenseDetectionResult -HasRdWebLicense $false -GracePeriodDays $graceDays -LicenseServer $licenseServer -Recommendation $rec -Detail $detail
}
catch {
    $message = "Unexpected error during license detection: $($_.Exception.Message)"
    Write-LicenseLog -Level ERROR -Message $message
    return New-LicenseDetectionResult -HasRdWebLicense $false -GracePeriodDays 0 -LicenseServer '' -Recommendation 'Install Guacamole' -Detail $message
}

Export-ModuleMember -Function @() -Variable @() -Cmdlet @()
# End of LicenseDetector.ps1