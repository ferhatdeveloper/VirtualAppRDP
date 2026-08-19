<#
.SYNOPSIS
    Sets up a Cloudflare Tunnel that publishes the local RDP / RD Web /
    Guacamole endpoints without opening any inbound firewall ports.

.DESCRIPTION
    Downloads cloudflared, authenticates with the supplied API token, creates
    a tunnel named 'rdp-virtual-box', writes a config file that publishes:
      * the RD Web / RD Gateway endpoint at https://<Domain>/rdweb
      * the Guacamole endpoint   at https://<Domain>/guacamole  (optional)
      * raw RDP traffic         at rdp://<Domain>            (optional)
    and finally installs cloudflared as a Windows service.

    Authentication is fully token-based - the operator must have created
    a scoped API token that includes:
      * Account / Cloudflare Tunnel: Edit
      * Zone / DNS: Edit
    on the zone that owns <Domain>.

.PARAMETER Domain
    Hostname that will be pointed at the tunnel (e.g. rdp.example.com).
    The apex zone (example.com) is taken from the last two labels.

.PARAMETER CloudflareToken
    API token with the scopes described above.

.PARAMETER TunnelName
    Logical tunnel name in Cloudflare. Default: rdp-virtual-box.

.PARAMETER PublishRdp
    Add a raw RDP ingress (cloudflared supports rdp:// protocol).

.PARAMETER PublishGuacamole
    Add a Guacamole ingress in addition to the RD Web one.

.PARAMETER ExeUrl
    Override URL for the cloudflared Windows executable.

.PARAMETER SkipFirewall
    Skip firewall rule addition (cloudflared uses outbound 443 only).

.OUTPUTS
    PSCustomObject:
        Success        [bool]
        TunnelId       [string]
        TunnelName     [string]
        Hostnames      [string[]]
        ConfigFile     [string]
        ServiceName    [string]
        LogFile        [string]

.EXAMPLE
    $token = 'eyJhIjoixxxxxxxxxxxxxxxx'
    & .\CloudflareTunnelInstaller.ps1 -Domain 'rdp.example.com' -CloudflareToken $token -PublishRdp -PublishGuacamole

.NOTES
    Author : Rdp Virtual Box App - Server Side (Agent S3)
    Module  : src/powershell/server/CloudflareTunnelInstaller.ps1
    Run on : Windows Server 2016/2019/2022 with elevated PowerShell.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Domain,
    [Parameter(Mandatory)] [string]$CloudflareToken,

    [Parameter()] [string]$TunnelName = 'rdp-virtual-box',

    [Parameter()] [switch]$PublishRdp,
    [Parameter()] [switch]$PublishGuacamole,

    [Parameter()] [string]$ExeUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe',

    [Parameter()] [switch]$SkipFirewall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants + logging
# ---------------------------------------------------------------------------
$script:LogFile          = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\cloudflare-tunnel-installer.log'
$script:WorkDir          = Join-Path -Path $env:TEMP -ChildPath 'RdpVirtualBoxApp\cloudflared'
$script:InstallDir       = 'C:\Program Files\cloudflared'
$script:ConfigDir        = 'C:\ProgramData\cloudflared'
$script:CloudflaredExe   = Join-Path -Path $script:InstallDir -ChildPath 'cloudflared.exe'
$script:ConfigFile       = Join-Path -Path $script:ConfigDir -ChildPath 'config.yml'
$script:ServiceName      = 'cloudflared'
$script:CredentialFile   = Join-Path -Path $script:ConfigDir -ChildPath 'credentials.json'

function Write-CFLog {
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
        throw 'CloudflareTunnelInstaller.ps1 must be run from an elevated PowerShell session (Administrator).'
    }
}

function Invoke-Cloudflared {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]]$Arguments)

    if (-not (Test-Path -Path $script:CloudflaredExe)) {
        throw "cloudflared.exe missing at $script:CloudflaredExe"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:CloudflaredExe
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    $exited = $proc.WaitForExit(600 * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { }
        throw "cloudflared $($Arguments -join ' ') timed out."
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($stdout) { Write-CFLog -Level INFO -Message $stdout.TrimEnd() }
    if ($stderr) { Write-CFLog -Level WARN -Message $stderr.TrimEnd() }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
function Install-CloudflaredBinary {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Downloading cloudflared' -PercentComplete 15

    if (Test-Path -Path $script:CloudflaredExe) {
        Write-CFLog -Level INFO -Message "cloudflared already present at $script:CloudflaredExe"
        return
    }

    if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
    $downloaded = Join-Path -Path $script:WorkDir -ChildPath 'cloudflared.exe'

    Write-CFLog -Level INFO -Message "Downloading cloudflared from $ExeUrl"
    Invoke-WebRequest -Uri $ExeUrl -OutFile $downloaded -UseBasicParsing -TimeoutSec 600

    if (-not (Test-Path -Path $script:InstallDir)) { New-Item -Path $script:InstallDir -ItemType Directory -Force | Out-Null }
    Move-Item -Path $downloaded -Destination $script:CloudflaredExe -Force

    if (-not (Test-Path -Path $script:ConfigDir)) { New-Item -Path $script:ConfigDir -ItemType Directory -Force | Out-Null }
}

function Save-CloudflaredCredential {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Persisting API token' -PercentComplete 30

    # Storing the token in a credential file is supported by cloudflared.
    $credJson = @{
        AccountTag   = 'token'
        TunnelSecret = ''
        TunnelID     = ''
        Token        = $CloudflareToken
    } | ConvertTo-Json -Depth 5

    Set-Content -Path $script:CredentialFile -Value $credJson -Encoding UTF8 -Force

    # Lock down permissions so only SYSTEM / Administrators can read it.
    try {
        $acl = Get-Acl -Path $script:CredentialFile
        $acl.SetAccessRuleProtection($true, $false)
        $sysRule   = New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators','FullControl','Allow')
        $acl.AddAccessRule($sysRule)
        $acl.AddAccessRule($adminRule)
        Set-Acl -Path $script:CredentialFile -AclObject $acl
    } catch {
        Write-CFLog -Level WARN -Message "Could not tighten ACL on $($script:CredentialFile): $($_.Exception.Message)"
    }
}

function New-CloudflareTunnel {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Creating tunnel' -PercentComplete 50

    # Check for an existing tunnel first by listing and matching name.
    $list = Invoke-Cloudflared -Arguments @('tunnel','list','--token', $CloudflareToken, '--output','json')
    if ($list.ExitCode -ne 0) {
        Write-CFLog -Level WARN -Message 'cloudflared tunnel list failed; attempting create anyway.'
    } else {
        try {
            $parsed = $list.StdOut | ConvertFrom-Json -ErrorAction Stop
            $match  = $parsed | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
            if ($match) {
                Write-CFLog -Level INFO -Message "Tunnel '$TunnelName' already exists with id $($match.id)."
                return $match.id
            }
        } catch {
            Write-CFLog -Level WARN -Message "Could not parse tunnel list JSON: $($_.Exception.Message)"
        }
    }

    $create = Invoke-Cloudflared -Arguments @('tunnel','create','--token', $CloudflareToken, $TunnelName)
    if ($create.ExitCode -ne 0) {
        throw "cloudflared tunnel create failed with exit code $($create.ExitCode)."
    }

    # The output mentions 'Created tunnel ... with id xxxx-xxxx-xxxx-xxxx'.
    $tunnelId = ''
    if ($create.StdOut -match 'with id ([0-9a-fA-F\-]+)') {
        $tunnelId = $Matches[1]
    }
    if (-not $tunnelId) {
        # Fallback: re-list and find by name.
        $list2 = Invoke-Cloudflared -Arguments @('tunnel','list','--token', $CloudflareToken, '--output','json')
        try {
            $parsed2 = $list2.StdOut | ConvertFrom-Json
            $match2  = $parsed2 | Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1
            if ($match2) { $tunnelId = $match2.id }
        } catch { }
    }
    if (-not $tunnelId) { throw 'Could not determine tunnel id from cloudflared output.' }
    return $tunnelId
}

function Set-TunnelDnsRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TunnelIdValue
    )

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Creating DNS route' -PercentComplete 65

    # First DNS route always points at the Domain parameter.
    $primary = Invoke-Cloudflared -Arguments @('tunnel','route','dns','--token', $CloudflareToken, $TunnelIdValue, $Domain)
    if ($primary.ExitCode -ne 0) {
        throw "cloudflared tunnel route dns failed for $Domain (exit $($primary.ExitCode))."
    }
}

function Write-TunnelConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TunnelIdValue
    )

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Writing config.yml' -PercentComplete 80

    $ingresses = New-Object System.Collections.Generic.List[string]
    # The RDP/HTTP entries reference localhost because cloudflared runs on
    # the server host.
    $ingresses.Add("  - hostname: $Domain")
    $ingresses.Add('    service: http://localhost:80')

    if ($PublishGuacamole) {
        $guacHost = "guacamole.$($Domain.Substring($Domain.IndexOf('.')+1))"
        $ingresses.Add("  - hostname: $guacHost")
        $ingresses.Add('    service: https://localhost:8443')
        $ingresses.Add('    originRequest:')
        $ingresses.Add('      noTLSVerify: true')
    }

    if ($PublishRdp) {
        $rdpHost = "rdp.$($Domain.Substring($Domain.IndexOf('.')+1))"
        $ingresses.Add("  - hostname: $rdpHost")
        $ingresses.Add('    service: rdp://localhost:3389')
    }

    $ingresses.Add('  - service: http_status:404')

    $config = @"
# Generated by Rdp Virtual Box App - CloudflareTunnelInstaller.ps1 on $(Get-Date)
tunnel: $TunnelIdValue
credentials-file: $script:CredentialFile
logfile: $script:LogFile
loglevel: info
ingress:
$($ingresses -join "`n")
"@

    Set-Content -Path $script:ConfigFile -Value $config -Encoding UTF8 -Force
}

function Install-CloudflaredService {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Installing Windows service' -PercentComplete 90

    $existing = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-CFLog -Level INFO -Message "Service '$($script:ServiceName)' already exists; restarting."
        Restart-Service -Name $script:ServiceName -Force -ErrorAction SilentlyContinue
        return
    }

    $result = Invoke-Cloudflared -Arguments @('service','install','--config', $script:ConfigFile)
    if ($result.ExitCode -ne 0) {
        throw "cloudflared service install failed with exit code $($result.ExitCode)."
    }

    Start-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
}

function Test-TunnelReachable {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Cloudflare Tunnel install' -Status 'Verifying DNS + tunnel' -PercentComplete 95

    try {
        $resolve = Resolve-DnsName -Name $Domain -ErrorAction Stop
        if (-not $resolve) {
            Write-CFLog -Level WARN -Message "DNS lookup for $Domain returned no records."
            return $false
        }
        $cfProxy = $resolve | Where-Object { $_.Section -eq 'Answer' -and $_.Name -eq $Domain }
        if (-not $cfProxy) {
            Write-CFLog -Level WARN -Message "Domain $Domain does not appear to resolve to Cloudflare proxy."
            return $false
        }
        return $true
    } catch {
        Write-CFLog -Level WARN -Message "DNS verification failed: $($_.Exception.Message)"
        return $false
    }
}

function Remove-CloudflareTunnel {
    [CmdletBinding()]
    param()

    Write-CFLog -Level WARN -Message "Rolling back Cloudflare tunnel '$TunnelName'."
    try {
        Invoke-Cloudflared -Arguments @('tunnel','cleanup','--token', $CloudflareToken, $TunnelName) | Out-Null
        Invoke-Cloudflared -Arguments @('tunnel','delete','--token', $CloudflareToken, $TunnelName) | Out-Null
    } catch { Write-CFLog -Level WARN -Message "Tunnel rollback failed: $($_.Exception.Message)" }

    if (Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue) {
        Stop-Service -Name $script:ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $script:ServiceName | Out-Null
    }

    foreach ($path in @($script:ConfigFile, $script:CredentialFile)) {
        if (Test-Path -Path $path) { Remove-Item -Path $path -Force }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Assert-Admin
    if (-not $Domain -or $Domain -notmatch '\.') {
        throw "-Domain must be a fully-qualified hostname (e.g. rdp.example.com)."
    }

    Install-CloudflaredBinary
    Save-CloudflaredCredential
    $tunnelId = New-CloudflareTunnel
    Set-TunnelDnsRoutes -TunnelIdValue $tunnelId
    Write-TunnelConfig -TunnelIdValue $tunnelId
    Install-CloudflaredService
    $ok = Test-TunnelReachable
    Write-Progress -Activity 'Cloudflare Tunnel install' -Completed

    $hostnames = @($Domain)
    if ($PublishGuacamole) { $hostnames += "guacamole.$($Domain.Substring($Domain.IndexOf('.')+1))" }
    if ($PublishRdp)       { $hostnames += "rdp.$($Domain.Substring($Domain.IndexOf('.')+1))" }

    [pscustomobject]@{
        Success     = $ok
        TunnelId    = $tunnelId
        TunnelName  = $TunnelName
        Hostnames   = $hostnames
        ConfigFile  = $script:ConfigFile
        ServiceName = $script:ServiceName
        LogFile     = $script:LogFile
    }
}
catch {
    Write-CFLog -Level ERROR -Message $_.Exception.Message
    Remove-CloudflareTunnel
    throw
}

Export-ModuleMember -Function @() -Variable @() -Cmdlet @()
# End of CloudflareTunnelInstaller.ps1