<#
.SYNOPSIS
    Configures Windows Firewall rules required by Rdp Virtual Box App.

.DESCRIPTION
    Creates inbound rules for:
      * RDP (TCP 3389)
      * RD Web Access / RD Gateway (TCP 443)
      * Apache Guacamole (TCP 8443)
      * WinRM HTTP (TCP 5985)
      * WinRM HTTPS (TCP 5986)

    Each rule is tagged with the "RdpVirtualBoxApp" prefix so it can be
    identified and removed by the companion Remove-RdpVirtualBoxAppRule
    function.

.PARAMETER EnableFirewall
    When set, all firewall profiles (Domain, Public, Private) are forced
    to enabled state.

.PARAMETER AllowedRemoteAddresses
    Optional array of remote IP addresses used to scope inbound rules
    (RemoteAddress parameter). When omitted, rules accept any remote
    address.

.PARAMETER LogPath
    Optional path to a log file. Defaults to
    "$env:ProgramData\RdpVirtualBoxApp\Logs\firewall-config.log".

.EXAMPLE
    Set-RdpVirtualBoxAppFirewall -EnableFirewall

.NOTES
    Author : Rdp Virtual Box App
    Module  : FirewallConfig.ps1
    Tags    : Firewall, NetSecurity, RDS
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$EnableFirewall,

    [Parameter()]
    [string[]]$AllowedRemoteAddresses,

    [Parameter()]
    [string]$LogPath
)

# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------
$script:RulePrefix = 'RdpVirtualBoxApp'

$script:DefaultRules = @(
    @{ DisplayName = "$script:RulePrefix - RDP 3389";            Port = 3389; Description = 'RDP direct connection' },
    @{ DisplayName = "$script:RulePrefix - HTTPS 443";           Port = 443;  Description = 'RD Web Access / RD Gateway HTTPS' },
    @{ DisplayName = "$script:RulePrefix - Guacamole 8443";      Port = 8443; Description = 'Apache Guacamole HTML5 gateway' },
    @{ DisplayName = "$script:RulePrefix - WinRM 5985";          Port = 5985; Description = 'WinRM HTTP (ServerProbe)' },
    @{ DisplayName = "$script:RulePrefix - WinRM 5986";          Port = 5986; Description = 'WinRM HTTPS (ServerProbe)' }
)

function Initialize-FirewallLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

function Write-FirewallLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('Info', 'Warning', 'Error', 'Debug')][string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    Add-Content -LiteralPath $script:FwLogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8

    switch ($Level) {
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning   $Message }
        'Error'   { Write-Error     $Message }
        'Debug'   { Write-Debug     $Message }
    }
}

function Test-RdpVirtualBoxAppRule {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][string]$DisplayName)

    $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    return ($null -ne $existing)
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function Set-RdpVirtualBoxAppFirewall {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [switch]$EnableFirewall,

        [Parameter()]
        [string[]]$AllowedRemoteAddresses,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\firewall-config.log'
    }

    Initialize-FirewallLog -Path $LogPath
    $script:FwLogPath = $LogPath

    try {
        if ($EnableFirewall) {
            if ($PSCmdlet.ShouldProcess('All profiles', 'Enable-NetFirewallProfile')) {
                Write-FirewallLogEntry -Message 'Enabling all firewall profiles.'
                Set-NetFirewallProfile -All -Enabled True -ErrorAction Stop
            }
        }

        $created = New-Object System.Collections.Generic.List[object]
        $existing = New-Object System.Collections.Generic.List[object]

        foreach ($rule in $script:DefaultRules) {
            $name = $rule.DisplayName
            $port = $rule.Port

            if (Test-RdpVirtualBoxAppRule -DisplayName $name) {
                Write-FirewallLogEntry -Level Debug -Message "Rule '$name' already exists, skipping creation."
                $existing.Add($name)
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, "New-NetFirewallRule TCP/$port")) {
                $args = @{
                    DisplayName = $name
                    Direction   = 'Inbound'
                    Action      = 'Allow'
                    Protocol    = 'TCP'
                    LocalPort   = $port
                    Profile     = 'Any'
                    Enabled     = 'True'
                    Description = "$($rule.Description) - Rdp Virtual Box App"
                }

                if ($AllowedRemoteAddresses) {
                    $args['RemoteAddress'] = $AllowedRemoteAddresses
                }

                $null = New-NetFirewallRule @args -ErrorAction Stop
                $created.Add([PSCustomObject]@{
                    DisplayName = $name
                    Port        = $port
                    Status      = 'Created'
                })
                Write-FirewallLogEntry -Message "Created firewall rule: $name (TCP/$port)"
            }
        }

        return [PSCustomObject]@{
            Created   = $created.ToArray()
            Existing  = $existing.ToArray()
            LogPath   = $LogPath
        }
    }
    catch {
        Write-FirewallLogEntry -Level Error -Message "Firewall configuration failed: $($_.Exception.Message)"
        throw
    }
}

function Enable-RdpVirtualBoxAppRule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$DisplayName
    )

    $filter = if ($DisplayName) { $DisplayName } else { "$script:RulePrefix*" }

    if ($PSCmdlet.ShouldProcess("rules matching '$filter'", 'Enable-NetFirewallRule')) {
        $rules = Get-NetFirewallRule -DisplayName $filter -ErrorAction SilentlyContinue
        if (-not $rules) {
            Write-Warning "No firewall rules matched '$filter'."
            return
        }
        foreach ($r in $rules) {
            Enable-NetFirewallRule -Name $r.Name -ErrorAction Stop
            Write-Verbose "Enabled firewall rule: $($r.DisplayName)"
        }
    }
}

function Disable-RdpVirtualBoxAppRule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$DisplayName
    )

    $filter = if ($DisplayName) { $DisplayName } else { "$script:RulePrefix*" }

    if ($PSCmdlet.ShouldProcess("rules matching '$filter'", 'Disable-NetFirewallRule')) {
        $rules = Get-NetFirewallRule -DisplayName $filter -ErrorAction SilentlyContinue
        if (-not $rules) {
            Write-Warning "No firewall rules matched '$filter'."
            return
        }
        foreach ($r in $rules) {
            Disable-NetFirewallRule -Name $r.Name -ErrorAction Stop
            Write-Verbose "Disabled firewall rule: $($r.DisplayName)"
        }
    }
}

function Remove-RdpVirtualBoxAppRule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$DisplayName
    )

    $filter = if ($DisplayName) { $DisplayName } else { "$script:RulePrefix*" }

    if ($PSCmdlet.ShouldProcess("rules matching '$filter'", 'Remove-NetFirewallRule')) {
        $rules = Get-NetFirewallRule -DisplayName $filter -ErrorAction SilentlyContinue
        if (-not $rules) {
            Write-Warning "No firewall rules matched '$filter'."
            return
        }
        foreach ($r in $rules) {
            Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop
            Write-Verbose "Removed firewall rule: $($r.DisplayName)"
        }
    }
}

function Get-RdpVirtualBoxAppFirewallStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $rules = Get-NetFirewallRule -DisplayName "$script:RulePrefix*" -ErrorAction SilentlyContinue
    $profiles = Get-NetFirewallProfile -All -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        Profiles = ($profiles | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction)
        Rules    = ($rules | ForEach-Object {
            $portInfo = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                DisplayName = $_.DisplayName
                Direction   = $_.Direction.ToString()
                Action      = $_.Action.ToString()
                Enabled     = $_.Enabled.ToString()
                Protocol    = if ($portInfo) { $portInfo.Protocol.ToString() } else { 'N/A' }
                LocalPort   = if ($portInfo) { $portInfo.LocalPort } else { 'N/A' }
                Profile     = $_.Profile.ToString()
            }
        })
    }
}

Export-ModuleMember -Function @(
    'Set-RdpVirtualBoxAppFirewall',
    'Enable-RdpVirtualBoxAppRule',
    'Disable-RdpVirtualBoxAppRule',
    'Remove-RdpVirtualBoxAppRule',
    'Get-RdpVirtualBoxAppFirewallStatus'
)