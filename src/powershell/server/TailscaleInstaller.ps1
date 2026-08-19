<#
.SYNOPSIS
    Installs Tailscale mesh VPN on a Windows Server host and brings it up
    as a node named rdp-virtual-box-server.

.DESCRIPTION
    Downloads the official Tailscale MSI, performs a silent install, and
    activates the node with a reusable auth key. The script accepts the
    auth key either via -AuthKey or via the TAILSCALE_AUTHKEY environment
    variable (preferred for unattended / silent installs).

    After successful auth the script prints the assigned Tailscale IP so
    the client-side installer can target the host without ever needing
    to know the public IP.

.PARAMETER AuthKey
    Reusable auth key (tskey-auth-...). Falls back to $env:TAILSCALE_AUTHKEY.

.PARAMETER MsiUrl
    Override URL for the Tailscale Windows MSI.

.PARAMETER Hostname
    Tailscale node name. Default: rdp-virtual-box-server.

.PARAMETER AcceptRoutes
    Pass --accept-routes so this node can use other nodes as subnets.

.PARAMETER ExitNode
    Pass --advertise-exit-node so this node can be used as an exit node.

.PARAMETER SkipFirewall
    Skip opening UDP 41641.

.OUTPUTS
    PSCustomObject:
        Success     [bool]
        TailscaleIp [string]
        Hostname    [string]
        LogFile     [string]

.EXAMPLE
    $env:TAILSCALE_AUTHKEY = 'tskey-auth-XXXXXXXX'
    & .\TailscaleInstaller.ps1

.NOTES
    Author : Rdp Virtual Box App - Server Side (Agent S3)
    Module  : src/powershell/server/TailscaleInstaller.ps1
    Run on : Windows Server 2016/2019/2022 with elevated PowerShell.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$AuthKey,

    [Parameter()] [string]$MsiUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi',

    [Parameter()] [string]$Hostname = 'rdp-virtual-box-server',

    [Parameter()] [switch]$AcceptRoutes,

    [Parameter()] [switch]$ExitNode,

    [Parameter()] [switch]$SkipFirewall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$script:LogFile = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\tailscale-installer.log'
$script:WorkDir = Join-Path -Path $env:TEMP -ChildPath 'RdpVirtualBoxApp\tailscale-install'

function Write-TLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO','WARN','ERROR')] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    try {
        $dir = Split-Path -Path $script:LogFile -Parent
        if (-not (Test-Path -Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    } catch { }

    switch ($Level) {
        'INFO'  { Write-Verbose    $Message }
        'WARN'  { Write-Warning    $Message }
        'ERROR' { Write-Error      $Message }
    }
}

function Assert-Admin {
    [CmdletBinding()]
    param()

    $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'TailscaleInstaller.ps1 must be run from an elevated PowerShell session (Administrator).'
    }
}

function Resolve-AuthKey {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($AuthKey)) {
        return $AuthKey
    }
    $envKey = [Environment]::GetEnvironmentVariable('TAILSCALE_AUTHKEY','User')
    if (-not $envKey) {
        $envKey = [Environment]::GetEnvironmentVariable('TAILSCALE_AUTHKEY','Process')
    }
    if (-not $envKey) {
        $envKey = [Environment]::GetEnvironmentVariable('TAILSCALE_AUTHKEY','Machine')
    }
    if ([string]::IsNullOrWhiteSpace($envKey)) {
        throw 'No Tailscale auth key provided. Pass -AuthKey or set the TAILSCALE_AUTHKEY environment variable.'
    }
    return $envKey
}

function Install-TailscaleMsi {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Tailscale install' -Status 'Downloading MSI' -PercentComplete 25

    $existing = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-TLog -Level INFO -Message 'Tailscale service already present; skipping MSI download.'
        return
    }

    if (-not (Test-Path -Path $script:WorkDir)) {
        New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null
    }
    $msi = Join-Path -Path $script:WorkDir -ChildPath 'tailscale.msi'

    Write-TLog -Level INFO -Message "Downloading Tailscale MSI from $MsiUrl"
    Invoke-WebRequest -Uri $MsiUrl -OutFile $msi -UseBasicParsing -TimeoutSec 600

    Write-Progress -Activity 'Tailscale install' -Status 'Installing MSI (silent)' -PercentComplete 60

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'msiexec.exe'
    $psi.Arguments = "/i `"$msi`" /quiet /norestart"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null
    $exited = $proc.WaitForExit(900 * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { }
        throw 'msiexec did not finish within 900 seconds.'
    }
    if ($proc.StandardOutput) { Write-TLog -Level INFO -Message ($proc.StandardOutput.ReadToEnd().TrimEnd()) }
    if ($proc.StandardError)  { Write-TLog -Level WARN -Message ($proc.StandardError.ReadToEnd().TrimEnd()) }

    $code = $proc.ExitCode
    if ($code -ne 0 -and $code -ne 3010) {
        throw "Tailscale MSI install failed with exit code $code."
    }

    # Wait for the service to register itself.
    for ($i = 0; $i -lt 30; $i++) {
        $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
        if ($svc) { return }
        Start-Sleep -Seconds 2
    }
    throw 'Tailscale service did not register within 60 seconds.'
}

function Start-TailscaleUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ResolvedAuthKey
    )

    Write-Progress -Activity 'Tailscale install' -Status 'tailscale up' -PercentComplete 80

    $tailscale = (Get-Command -Name 'tailscale' -ErrorAction SilentlyContinue)
    if (-not $tailscale) {
        $candidate = 'C:\Program Files\Tailscale\tailscale.exe'
        if (Test-Path -Path $candidate) {
            $tailscalePath = $candidate
        } else {
            throw 'tailscale.exe not found on PATH or at the default install location.'
        }
    } else {
        $tailscalePath = $tailscale.Path
    }

    $upArgs = @('up',
        "--authkey=$ResolvedAuthKey",
        "--hostname=$Hostname"
    )
    if ($AcceptRoutes) { $upArgs += '--accept-routes' }
    if ($ExitNode)     { $upArgs += '--advertise-exit-node' }

    Write-TLog -Level INFO -Message "Running: $tailscalePath $($upArgs -join ' ')"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $tailscalePath
    $psi.Arguments = ($upArgs | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null
    $exited = $proc.WaitForExit(180 * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { }
        throw 'tailscale up did not finish within 180 seconds.'
    }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($stdout) { Write-TLog -Level INFO -Message $stdout.TrimEnd() }
    if ($stderr) { Write-TLog -Level WARN -Message $stderr.TrimEnd() }
    if ($proc.ExitCode -ne 0) {
        throw "tailscale up exited with code $($proc.ExitCode)."
    }
}

function Get-TailscaleIp {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $tailscale = (Get-Command -Name 'tailscale' -ErrorAction SilentlyContinue)
    if (-not $tailscale) {
        $candidate = 'C:\Program Files\Tailscale\tailscale.exe'
        if (-not (Test-Path -Path $candidate)) {
            return ''
        }
        $tailscalePath = $candidate
    } else {
        $tailscalePath = $tailscale.Path
    }

    try {
        $ip = & $tailscalePath ip -4 2>$null | Select-Object -First 1
        if ($ip) { return $ip.Trim() }
    } catch {
        Write-TLog -Level WARN -Message "tailscale ip failed: $($_.Exception.Message)"
    }
    return ''
}

function Open-TailscaleFirewall {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Tailscale install' -Status 'Firewall rule UDP 41641' -PercentComplete 95

    if ($SkipFirewall) {
        Write-TLog -Level INFO -Message 'SkipFirewall set; not touching Windows Firewall.'
        return
    }

    $existing = Get-NetFirewallRule -DisplayName 'Tailscale WireGuard 41641' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-TLog -Level INFO -Message 'Tailscale firewall rule already present.'
        return
    }

    New-NetFirewallRule -DisplayName 'Tailscale WireGuard 41641' `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 41641 `
        -Action Allow `
        -Profile Any | Out-Null
}

function Uninstall-Tailscale {
    [CmdletBinding()]
    param()

    Write-TLog -Level WARN -Message 'Rolling back Tailscale installation.'
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name 'Tailscale' -Force -ErrorAction SilentlyContinue
    }
    Remove-NetFirewallRule -DisplayName 'Tailscale WireGuard 41641' -ErrorAction SilentlyContinue
    $msi = 'C:\Program Files (x86)\Tailscale\tailscale-setup-latest-amd64.msi'
    if (Test-Path -Path $msi) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'msiexec.exe'
        $psi.Arguments = "/x `"$msi`" /quiet /norestart"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        $proc.WaitForExit(180 * 1000) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Assert-Admin
    $resolvedKey = Resolve-AuthKey
    Install-TailscaleMsi
    Start-TailscaleUp -ResolvedAuthKey $resolvedKey
    $tsIp = Get-TailscaleIp
    Open-TailscaleFirewall
    Write-Progress -Activity 'Tailscale install' -Completed

    [pscustomobject]@{
        Success     = [bool]$tsIp
        TailscaleIp = $tsIp
        Hostname    = $Hostname
        LogFile     = $script:LogFile
    }
}
catch {
    Write-TLog -Level ERROR -Message $_.Exception.Message
    Uninstall-Tailscale
    throw
}

Export-ModuleMember -Function @() -Variable @() -Cmdlet @()
# End of TailscaleInstaller.ps1