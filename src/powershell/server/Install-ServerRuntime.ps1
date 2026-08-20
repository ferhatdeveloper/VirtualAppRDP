#requires -Version 5.1
<#
.SYNOPSIS
    First-run runtime: seed ProgramData configs, firewall, Probe API, Caddy SSL.

.DESCRIPTION
    Matches the live architecture:
      * Probe HTTP 8444 (Bearer)
      * Customer download portal on webPort (default 8001; skipped if busy)
      * Caddy HTTPS reverse proxy on 8445 (not 443)
      * One Windows RDP listen port; per-customer WAN ports in customers.json
      * LAN / public / VPN endpoints detected at install (not baked into the EXE)

    Existing ProgramData files are never overwritten (token, customers, endpoints).
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$ApiPort = 8444,

    [ValidateRange(1, 65535)]
    [int]$WebPort = 8001,

    [ValidateRange(1, 65535)]
    [int]$HttpsPort = 8445,

    [ValidateRange(1, 65535)]
    [int]$RdpPort = 3389,

    [switch]$SkipCaddy,
    [switch]$SkipProbe,
    [switch]$SkipFirewall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LogFile = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs\server-runtime.log'
$script:DataConfigDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
$script:PackagedConfigDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Config'
if (-not (Test-Path -LiteralPath $script:PackagedConfigDir)) {
    $alt = Join-Path $PSScriptRoot '..\..\config\server'
    if (Test-Path -LiteralPath $alt) {
        $script:PackagedConfigDir = (Resolve-Path -LiteralPath $alt).Path
    }
}

. (Join-Path $PSScriptRoot 'ProbeApi.ps1')

function Write-RuntimeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Output $line
}

function Get-DetectedEndpoints {
    $lan = Get-LocalPrimaryIpv4
    $vpn = Get-VpnIpv4
    $public = Get-PublicIpv4
    if ([string]::IsNullOrWhiteSpace($public)) { $public = $lan }
    if ([string]::IsNullOrWhiteSpace($vpn)) { $vpn = '' }
    return [ordered]@{
        lan     = [string]$lan
        public  = [string]$public
        vpn     = [string]$vpn
        rdpPort = [int]$RdpPort
    }
}

function Copy-TemplateIfMissing {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][scriptblock]$Builder
    )
    $dest = Join-Path $script:DataConfigDir $FileName
    if (Test-Path -LiteralPath $dest) {
        Write-RuntimeLog -Message "Korundu (mevcut): $dest"
        return $false
    }
    if (-not (Test-Path -LiteralPath $script:DataConfigDir)) {
        New-Item -ItemType Directory -Path $script:DataConfigDir -Force | Out-Null
    }
    $obj = & $Builder
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($dest, ($obj | ConvertTo-Json -Depth 8), $utf8)
    Write-RuntimeLog -Message "Yazildi: $dest"
    return $true
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-EffectiveWebPort {
    $envPort = [string]$env:RDPVB_WEB_PORT
    if ($envPort -match '^\d+$') {
        $n = [int]$envPort
        if ($n -ge 1 -and $n -le 65535) { return $n }
    }
    foreach ($name in @('customers.json', 'probe-api.json')) {
        $j = Read-JsonFile -Path (Join-Path $script:DataConfigDir $name)
        if ($j -and $j.PSObject.Properties['webPort'] -and $j.webPort) {
            $n = [int]$j.webPort
            if ($n -ge 1 -and $n -le 65535) { return $n }
        }
    }
    return [int]$WebPort
}

function Get-EffectiveRdpPort {
    $envPort = [string]$env:RDPVB_RDP_PORT
    if ($envPort -match '^\d+$') {
        $n = [int]$envPort
        if ($n -ge 1 -and $n -le 65535) { return $n }
    }
    $j = Read-JsonFile -Path (Join-Path $script:DataConfigDir 'customers.json')
    if ($j -and $j.listenRdpPort) {
        $n = [int]$j.listenRdpPort
        if ($n -ge 1 -and $n -le 65535) { return $n }
    }
    return [int]$RdpPort
}

$ep = Get-DetectedEndpoints
$listenRdp = Get-EffectiveRdpPort
$ep.rdpPort = $listenRdp

Write-RuntimeLog -Message ("Runtime kurulum basladi lan={0} public={1} vpn={2} rdp={3}" -f $ep.lan, $ep.public, $ep.vpn, $listenRdp)

Copy-TemplateIfMissing -FileName 'probe-api.json' -Builder {
    [ordered]@{
        enabled     = $true
        port        = [int]$ApiPort
        bind        = '0.0.0.0'
        auth        = 'bearer'
        token       = ''
        listenHttps = $false
        rdpPort     = [int]$listenRdp
        httpsPort   = [int]$HttpsPort
        webPort     = [int]$WebPort
    }
} | Out-Null

Copy-TemplateIfMissing -FileName 'client-endpoints.json' -Builder {
    [ordered]@{
        note       = 'NAT: TCP/UDP RDP listen port, TCP 443, TCP 8444, TCP 8445, TCP 8001 -> LAN IP. Probe HTTP 8444, Caddy HTTPS 8445.'
        app        = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe'
        lan        = [string]$ep.lan
        public     = [string]$ep.public
        vpn        = [string]$ep.vpn
        client     = [string]$ep.public
        probe      = [int]$ApiPort
        https      = 443
        rdpPort    = [int]$listenRdp
        probeHttps = [int]$HttpsPort
    }
} | Out-Null

Copy-TemplateIfMissing -FileName 'customers.json' -Builder {
    [ordered]@{
        webPort       = [int]$WebPort
        listenRdpPort = [int]$listenRdp
        customers     = @(
            [ordered]@{
                id         = 'default'
                name       = 'Varsayilan'
                publicIp   = [string]$ep.public
                lanIp      = [string]$ep.lan
                vpnIp      = [string]$ep.vpn
                rdpPort    = [int]$listenRdp
                lanRdpPort = [int]$listenRdp
            }
        )
    }
} | Out-Null

Copy-TemplateIfMissing -FileName 'server.json' -Builder {
    $tplPath = Join-Path $script:PackagedConfigDir 'server.template.json'
    $obj = [ordered]@{
        version     = '1.1.4'
        product     = 'RdpVirtualBoxApp-Server'
        listenPort  = [int]$listenRdp
        webPort     = [int]$WebPort
        rdpDownload = [ordered]@{ enabled = $true; path = '/download' }
        probeApi    = [ordered]@{ enabled = $true; port = [int]$ApiPort; httpsPort = [int]$HttpsPort; webPort = [int]$WebPort; auth = 'bearer' }
        caddy       = [ordered]@{ enabled = $true; httpsPort = [int]$HttpsPort; domain = '' }
        remoteApps  = @(
            [ordered]@{
                alias = 'Tiger3Ent'
                name  = 'Tiger3 Enterprise'
                path  = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe'
            }
        )
        strategies  = [ordered]@{
            direct     = $true
            gateway    = $true
            guacamole  = $false
            tailscale  = $false
            cloudflare = $false
        }
    }
    if (Test-Path -LiteralPath $tplPath) {
        try {
            $tpl = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($tpl.version) { $obj.version = [string]$tpl.version }
            if ($tpl.remoteApps) { $obj.remoteApps = @($tpl.remoteApps) }
        } catch { }
    }
    $obj.listenPort = [int]$listenRdp
    $obj.webPort = [int]$WebPort
    return $obj
} | Out-Null

$portalPort = Get-EffectiveWebPort
$listenRdp = Get-EffectiveRdpPort

$result = [ordered]@{
    version       = '1.1.4'
    lan           = $ep.lan
    public        = $ep.public
    vpn           = $ep.vpn
    apiPort       = [int]$ApiPort
    webPort       = [int]$portalPort
    httpsPort     = [int]$HttpsPort
    listenRdpPort = [int]$listenRdp
    firewall      = $false
    probe         = $null
    caddy         = $null
    downloadUrls  = @(
        "http://127.0.0.1:${portalPort}/download"
        "http://127.0.0.1:${ApiPort}/download"
        "https://127.0.0.1:${HttpsPort}/download"
    )
}

if (-not $SkipFirewall) {
    try {
        $fwScript = Join-Path $PSScriptRoot 'FirewallConfig.ps1'
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $fwJson = & $ps -NoProfile -ExecutionPolicy Bypass -Command @"
`$ErrorActionPreference = 'Stop'
. '$($fwScript.Replace("'", "''"))'
Set-RdpVirtualBoxAppFirewall -RdpPort $listenRdp | ConvertTo-Json -Compress -Depth 5
"@
        $result.firewall = $true
        Write-RuntimeLog -Message "Firewall OK $fwJson"
    } catch {
        Write-RuntimeLog -Level 'WARN' -Message "Firewall: $($_.Exception.Message)"
    }
}

if (-not $SkipProbe) {
    $hostScript = Join-Path $PSScriptRoot 'Start-ProbeApiHost.ps1'
    try {
        $json = & $hostScript -Mode Install -Port $ApiPort -WebPort $portalPort
        $result.probe = $json | ConvertFrom-Json
        Write-RuntimeLog -Message "Probe API kuruldu port=$ApiPort webPort=$portalPort"
    } catch {
        Write-RuntimeLog -Level 'ERROR' -Message "Probe API: $($_.Exception.Message)"
        throw
    }
}

if (-not $SkipCaddy) {
    $caddyScript = Join-Path $PSScriptRoot 'Install-CaddySsl.ps1'
    try {
        & $caddyScript
        $result.caddy = $true
        Write-RuntimeLog -Message "Caddy SSL kuruldu https=$HttpsPort"
    } catch {
        $result.caddy = $false
        Write-RuntimeLog -Level 'WARN' -Message "Caddy SSL atlandi: $($_.Exception.Message)"
    }
}

$result | ConvertTo-Json -Depth 8
