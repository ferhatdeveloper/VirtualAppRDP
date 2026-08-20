#requires -Version 5.1
<#
.SYNOPSIS
    Rdp Virtual Box App - Probe REST API (logic + request dispatcher).

.DESCRIPTION
    Windows istemcisi ServerProbe.ps1'i WinRM uzerinden cagirir. macOS
    ve diger HTTP istemcileri icin sunucuda bir REST endpoint barindirilir.

    Bu dosya is mantigini tutar. Gercek HTTP dinleyici
    Start-ProbeApiHost.ps1 icindedir (TcpListener, extra runtime gerekmez).

    Endpointler (varsayilan port 8444):
        GET  /health
        GET  /api/health
        GET  /probe/api/health
        GET  /probe/api/probe
        GET  /api/probe
        GET  /probe/api/manifest
        GET  /api/manifest
        GET  /probe/api/apps
        GET  /api/apps
        GET  /probe/api/status
        GET  /api/status
        GET  /download              React dashboard (anonim)
        GET  /api/browse            Sunucu dosya gezgini (LAN / Bearer)
        POST /api/apps              RemoteApp yayinla (LAN / Bearer)
        GET  /rdp                   Indirme listesi JSON (anonim)
        GET  /rdp/public.rdp        Public IP .rdp (anonim)
        GET  /rdp/lan.rdp
        GET  /rdp/vpn.rdp

    Authorization: Bearer <token>  (health, kok, /download ve /rdp* haric; token yoksa auth kapali)

    JSON semasi ServerProbe.ps1 + macOS Swift ProbeResult ile uyumludur.

.NOTES
    Author  : Rdp Virtual Box App
    Version : 1.1.5
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Sabitler
# ---------------------------------------------------------------------------

$Script:ProbeApiVersion  = '1.1.5'
$Script:DefaultProbePath = '/probe/api/probe'
$Script:DefaultProbePort = 8444
$Script:RdpPort          = 3389
$Script:HttpsPort        = 443
$Script:GuacamolePort    = 8443
$Script:WinRmPort        = 5985
$Script:ConfigFileName   = 'probe-api.json'
$Script:ManifestRelPath  = 'RdpVirtualBoxApp\Manifest\server-manifest.json'

if (-not ('RdpProbeJson' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Globalization;
using System.Text;

public static class RdpProbeJson {
    public static string Encode(object value) {
        var sb = new StringBuilder();
        Write(sb, value, 0);
        return sb.ToString();
    }

    static object Unwrap(object value) {
        var guard = 0;
        while (value != null && guard++ < 6) {
            var t = value.GetType();
            if (t.FullName != "System.Management.Automation.PSObject") break;
            var prop = t.GetProperty("BaseObject");
            if (prop == null) break;
            var baseObj = prop.GetValue(value, null);
            if (baseObj == null || object.ReferenceEquals(baseObj, value)) break;
            value = baseObj;
        }
        return value;
    }

    static void Write(StringBuilder sb, object value, int depth) {
        value = Unwrap(value);
        if (depth > 40) { sb.Append("null"); return; }
        if (value == null || value is DBNull) { sb.Append("null"); return; }
        if (value is bool) { sb.Append(((bool)value) ? "true" : "false"); return; }
        var s = value as string;
        if (s != null) { sb.Append('"'); Escape(sb, s); sb.Append('"'); return; }
        if (value is byte || value is short || value is ushort || value is int || value is uint || value is long || value is ulong || value is decimal || value is float || value is double) {
            sb.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
            return;
        }
        var dict = value as IDictionary;
        if (dict != null) {
            sb.Append('{');
            var first = true;
            foreach (DictionaryEntry e in dict) {
                if (!first) sb.Append(',');
                first = false;
                sb.Append('"');
                Escape(sb, Convert.ToString(e.Key, CultureInfo.InvariantCulture));
                sb.Append('"');
                sb.Append(':');
                Write(sb, e.Value, depth + 1);
            }
            sb.Append('}');
            return;
        }
        var en = value as IEnumerable;
        if (en != null) {
            sb.Append('[');
            var first = true;
            foreach (var item in en) {
                if (!first) sb.Append(',');
                first = false;
                Write(sb, item, depth + 1);
            }
            sb.Append(']');
            return;
        }
        sb.Append('"');
        Escape(sb, Convert.ToString(value, CultureInfo.InvariantCulture));
        sb.Append('"');
    }

    static void Escape(StringBuilder sb, string text) {
        if (string.IsNullOrEmpty(text)) return;
        foreach (var ch in text) {
            switch (ch) {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (ch < 32) sb.AppendFormat("\\u{0:x4}", (int)ch);
                    else sb.Append(ch);
                    break;
            }
        }
    }
}
'@
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

function Get-ProbeApiConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path -Path $env:ProgramData -ChildPath "RdpVirtualBoxApp\Config\$($Script:ConfigFileName)")
}

function Get-ProbeApiConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $defaults = [ordered]@{
        enabled     = $true
        port        = $Script:DefaultProbePort
        bind        = '0.0.0.0'
        auth        = 'bearer'
        token       = ''
        listenHttps = $false
        rdpPort     = $Script:RdpPort
        httpsPort   = 8445
        webPort     = 8001
    }

    $path = Get-ProbeApiConfigPath
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $defaults[$p.Name] = $p.Value
            }
        } catch {
            Write-Verbose "Probe API config okunamadi: $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:RDPVB_PROBE_TOKEN)) {
        $defaults.token = $env:RDPVB_PROBE_TOKEN
    }

    return $defaults
}

function Get-ConfiguredRdpPort {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    $envPort = [string]$env:RDPVB_RDP_PORT
    if ($envPort -match '^\d+$') {
        $n = [int]$envPort
        if ($n -ge 1 -and $n -le 65535) { return $n }
    }
    try {
        $cfg = Get-ProbeApiConfig
        if ($cfg.Contains('rdpPort') -and $cfg.rdpPort) {
            $n = [int]$cfg.rdpPort
            if ($n -ge 1 -and $n -le 65535) { return $n }
        }
    } catch {}
    $ep = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\client-endpoints.json'
    if (Test-Path -LiteralPath $ep) {
        try {
            $j = Get-Content -LiteralPath $ep -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.PSObject.Properties['rdpPort'] -and $j.rdpPort) {
                $n = [int]$j.rdpPort
                if ($n -ge 1 -and $n -le 65535) { return $n }
            }
        } catch {}
    }
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -ErrorAction Stop
        $n = [int]$reg.PortNumber
        if ($n -ge 1 -and $n -le 65535) { return $n }
    } catch {}
    return [int]$Script:RdpPort
}

function Get-PublishedEndpointSet {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $lan = $null
    $public = $null
    $vpn = $null
    $httpsPort = 8445
    $ep = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\client-endpoints.json'
    if (Test-Path -LiteralPath $ep) {
        try {
            $j = Get-Content -LiteralPath $ep -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.lan) { $lan = [string]$j.lan }
            if ($j.public) { $public = [string]$j.public }
            elseif ($j.client) { $public = [string]$j.client }
            if ($j.vpn) { $vpn = [string]$j.vpn }
            if ($j.PSObject.Properties['probeHttps'] -and $j.probeHttps) { $httpsPort = [int]$j.probeHttps }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($lan)) { $lan = Get-LocalPrimaryIpv4 }
    if ([string]::IsNullOrWhiteSpace($public)) { $public = $lan }
    if ([string]::IsNullOrWhiteSpace($vpn)) { $vpn = Get-VpnIpv4 }
    return [ordered]@{
        lan       = $lan
        public    = $public
        vpn       = $vpn
        rdpPort   = Get-ConfiguredRdpPort
        httpsPort = $httpsPort
        probePort = [int]((Get-ProbeApiConfig).port)
        webPort   = $(
            $wp = 8001
            try {
                $c = Get-ProbeApiConfig
                if ($c.Contains('webPort') -and $c.webPort) { $wp = [int]$c.webPort }
            } catch {}
            $wp
        )
    }
}

function Get-CustomerPortalConfigPath {
    return (Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\customers.json')
}

function Get-CustomerPortalConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $ep = Get-PublishedEndpointSet
    $cfgApi = Get-ProbeApiConfig
    $webPort = 8001
    try { if ($cfgApi.Contains('webPort') -and $cfgApi.webPort) { $webPort = [int]$cfgApi.webPort } } catch {}
    $listen = Get-ConfiguredRdpPort
    $defaults = [ordered]@{
        webPort       = $webPort
        listenRdpPort = $listen
        customers     = @(
            [ordered]@{
                id         = 'default'
                name       = 'Varsayilan'
                publicIp   = $ep.public
                lanIp      = $ep.lan
                vpnIp      = $ep.vpn
                rdpPort    = $listen
                lanRdpPort = $listen
            }
        )
    }
    $path = Get-CustomerPortalConfigPath
    if (Test-Path -LiteralPath $path) {
        try {
            $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($obj.webPort) { $defaults.webPort = [int]$obj.webPort }
            if ($obj.listenRdpPort) { $defaults.listenRdpPort = [int]$obj.listenRdpPort }
            $list = New-Object System.Collections.Generic.List[object]
            foreach ($c in @($obj.customers)) {
                if ($null -eq $c) { continue }
                $id = [string]$c.id
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                [void]$list.Add([ordered]@{
                    id         = $id.ToLowerInvariant()
                    name       = $(if ($c.name) { [string]$c.name } else { $id })
                    publicIp   = $(if ($c.publicIp) { [string]$c.publicIp } else { $ep.public })
                    lanIp      = $(if ($c.lanIp) { [string]$c.lanIp } else { $ep.lan })
                    vpnIp      = $(if ($c.vpnIp) { [string]$c.vpnIp } else { $ep.vpn })
                    rdpPort    = $(if ($c.rdpPort) { [int]$c.rdpPort } else { $listen })
                    lanRdpPort = $(if ($c.lanRdpPort) { [int]$c.lanRdpPort } else { $listen })
                })
            }
            if ($list.Count -gt 0) { $defaults.customers = $list.ToArray() }
        } catch {}
    }
    return $defaults
}

function Save-CustomerPortalConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $path = Get-CustomerPortalConfigPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, ($Config | ConvertTo-Json -Depth 8), $utf8)
}

function Get-CustomerPortalEntry {
    param([string]$CustomerId)
    $cfg = Get-CustomerPortalConfig
    $id = if ([string]::IsNullOrWhiteSpace($CustomerId)) { 'default' } else { $CustomerId.ToLowerInvariant() }
    foreach ($c in @($cfg.customers)) {
        $cid = [string]$c['id']
        if (-not $cid) { $cid = [string]$c.id }
        if ($cid.ToLowerInvariant() -eq $id) { return @{ Config = $cfg; Customer = $c } }
    }
    $first = @($cfg.customers)[0]
    return @{ Config = $cfg; Customer = $first }
}

function Test-IsPrivateClientIp {
    param([string]$Ip)
    if ([string]::IsNullOrWhiteSpace($Ip)) { return $true }
    $ip = $Ip.Trim()
    if ($ip -eq '::1' -or $ip -eq '127.0.0.1') { return $true }
    if ($ip -like '::ffff:*') { $ip = $ip.Substring(7) }
    return [bool]($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)')
}

function ConvertTo-CustomerSlug {
    param([string]$Name)
    $s = ([string]$Name).ToLowerInvariant()
    $s = $s -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    if ([string]::IsNullOrWhiteSpace($s)) { $s = 'musteri' }
    return $s
}

function Save-CustomerPortalFromJson {
    [CmdletBinding()]
    param([string]$JsonText)
    $cfg = Get-CustomerPortalConfig
    $obj = $null
    if (-not [string]::IsNullOrWhiteSpace($JsonText)) {
        try { $obj = $JsonText | ConvertFrom-Json } catch { throw 'Gecersiz JSON' }
    }
    if ($null -eq $obj) { return $cfg }
    if ($obj.PSObject.Properties['webPort'] -and $obj.webPort) {
        $wp = [int]$obj.webPort
        if ($wp -ge 1 -and $wp -le 65535) { $cfg.webPort = $wp }
    }
    if ($obj.PSObject.Properties['listenRdpPort'] -and $obj.listenRdpPort) {
        $lp = [int]$obj.listenRdpPort
        if ($lp -ge 1 -and $lp -le 65535) { $cfg.listenRdpPort = $lp }
    }
    $incoming = @()
    if ($obj.PSObject.Properties['customers'] -and $obj.customers) { $incoming = @($obj.customers) }
    elseif ($obj.PSObject.Properties['customer'] -and $obj.customer) { $incoming = @($obj.customer) }
    $map = @{}
    foreach ($c in @($cfg.customers)) {
        $id = [string]$c['id']
        if (-not $id) { $id = [string]$c.id }
        if ($id) { $map[$id.ToLowerInvariant()] = $c }
    }
    foreach ($c in $incoming) {
        $id = [string]$c.id
        if ([string]::IsNullOrWhiteSpace($id)) { $id = ConvertTo-CustomerSlug -Name ([string]$c.name) }
        $id = $id.ToLowerInvariant()
        $existing = $null
        if ($map.ContainsKey($id)) { $existing = $map[$id] }
        $name = $id
        $publicIp = ''
        $lanIp = ''
        $vpnIp = ''
        $rdpPort = [int]$cfg.listenRdpPort
        $lanRdpPort = [int]$cfg.listenRdpPort
        if ($existing) {
            if ($existing['name']) { $name = [string]$existing['name'] }
            if ($existing['publicIp']) { $publicIp = [string]$existing['publicIp'] }
            if ($existing['lanIp']) { $lanIp = [string]$existing['lanIp'] }
            if ($existing['vpnIp']) { $vpnIp = [string]$existing['vpnIp'] }
            if ($existing['rdpPort']) { $rdpPort = [int]$existing['rdpPort'] }
            if ($existing['lanRdpPort']) { $lanRdpPort = [int]$existing['lanRdpPort'] }
        }
        if ($c.PSObject.Properties['name'] -and $c.name) { $name = [string]$c.name }
        if ($c.PSObject.Properties['publicIp'] -and $c.publicIp) { $publicIp = [string]$c.publicIp }
        if ($c.PSObject.Properties['lanIp'] -and $c.lanIp) { $lanIp = [string]$c.lanIp }
        if ($c.PSObject.Properties['vpnIp'] -and $c.vpnIp) { $vpnIp = [string]$c.vpnIp }
        if ($c.PSObject.Properties['rdpPort'] -and $c.rdpPort) { $rdpPort = [int]$c.rdpPort }
        if ($c.PSObject.Properties['lanRdpPort'] -and $c.lanRdpPort) { $lanRdpPort = [int]$c.lanRdpPort }
        $merged = [ordered]@{
            id         = $id
            name       = $name
            publicIp   = $publicIp
            lanIp      = $lanIp
            vpnIp      = $vpnIp
            rdpPort    = $rdpPort
            lanRdpPort = $lanRdpPort
        }
        $map[$id] = $merged
    }
    $cfg.customers = @($map.Values)
    Save-CustomerPortalConfig -Config $cfg
    $api = Get-ProbeApiConfig
    $api.webPort = [int]$cfg.webPort
    Save-ProbeApiConfig -Config $api
    return $cfg
}

function ConvertTo-RemoteAppAlias {
    param([string]$Name)
    $s = [string]$Name
    $s = $s -replace '\.exe$', ''
    $s = $s -replace '[^A-Za-z0-9]', ''
    if ([string]::IsNullOrWhiteSpace($s)) { $s = 'App' }
    if ($s.Length -gt 24) { $s = $s.Substring(0, 24) }
    return $s
}

function Register-TsRemoteApp {
    [CmdletBinding()]
    param(
        [string]$Alias,
        [string]$Name,
        [string]$FilePath,
        [string]$IconPath
    )
    $exe = [string]$FilePath
    if ([string]::IsNullOrWhiteSpace($exe)) { throw 'path_required' }
    $exe = $exe.Trim().Trim('"')
    if ($exe -notmatch '^[A-Za-z]:\\') { throw 'local_path_required' }
    if ($exe -match '\.\.') { throw 'invalid_path' }
    if (-not (Test-Path -LiteralPath $exe)) { throw 'exe_not_found' }
    $item = Get-Item -LiteralPath $exe -ErrorAction Stop
    if ($item.PSIsContainer) { throw 'not_a_file' }
    if ($item.Extension -notin @('.exe', '.EXE')) { throw 'not_exe' }
    $safe = ConvertTo-RemoteAppAlias -Name $(if ($Alias) { $Alias } else { $item.BaseName })
    $display = if ([string]::IsNullOrWhiteSpace($Name)) { $item.BaseName } else { [string]$Name }
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -Path $root -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $root -Name 'fDisabledAllowList' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -LiteralPath $root -Name 'fDisabledAllowList' -Value 0 -Type DWord -Force
    $appsRoot = Join-Path $root 'Applications'
    if (-not (Test-Path -LiteralPath $appsRoot)) {
        New-Item -Path $appsRoot -Force | Out-Null
    }
    $key = Join-Path $appsRoot $safe
    if (-not (Test-Path -LiteralPath $key)) {
        New-Item -Path $key -Force | Out-Null
    }
    $full = $item.FullName
    $iconFull = $full
    if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
        $ip = $IconPath.Trim().Trim('"')
        if ($ip -match '^[A-Za-z]:\\' -and $ip -notmatch '\.\.' -and (Test-Path -LiteralPath $ip)) {
            $iconFull = (Get-Item -LiteralPath $ip).FullName
        }
    }
    Set-ItemProperty -LiteralPath $key -Name 'Name' -Value $display -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'Path' -Value $full -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'VPath' -Value $full -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'IconPath' -Value $iconFull -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'IconIndex' -Value 0 -Type DWord -Force
    Set-ItemProperty -LiteralPath $key -Name 'CommandLineSetting' -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $key -Name 'RequiredCommandLine' -Value '' -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'ShowInTSWA' -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $key -Name 'Alias' -Value $safe -Type String -Force
    return [ordered]@{
        alias     = $safe
        name      = $display
        path      = $full
        publisher = 'TSAppAllowList'
        published = $true
        iconPath  = $iconFull
    }
}

function Save-PublishedAppFromJson {
    [CmdletBinding()]
    param([string]$JsonText)
    if ([string]::IsNullOrWhiteSpace($JsonText)) { throw 'empty_body' }
    $obj = $JsonText | ConvertFrom-Json
    $path = ''
    $alias = ''
    $name = ''
    if ($obj.PSObject.Properties['path']) { $path = [string]$obj.path }
    elseif ($obj.PSObject.Properties['file']) { $path = [string]$obj.file }
    if ($obj.PSObject.Properties['alias']) { $alias = [string]$obj.alias }
    if ($obj.PSObject.Properties['name']) { $name = [string]$obj.name }
    $iconPath = ''
    if ($obj.PSObject.Properties['iconPath']) { $iconPath = [string]$obj.iconPath }
    if ($obj.PSObject.Properties['action'] -and [string]$obj.action -eq 'icon') {
        return (Set-TsRemoteAppIcon -Alias $alias -IconPath $(if ($iconPath) { $iconPath } else { $path }))
    }
    return (Register-TsRemoteApp -Alias $alias -Name $name -FilePath $path -IconPath $iconPath)
}

function Get-DashboardRoot {
    $cands = @(
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'Dashboard'),
        (Join-Path $PSScriptRoot '..\..\dashboard\dist'),
        (Join-Path $env:ProgramFiles 'RdpVirtualBoxApp\Dashboard'),
        (Join-Path $env:ProgramData 'RdpVirtualBoxApp\Dashboard')
    )
    foreach ($c in $cands) {
        try {
            if ([string]::IsNullOrWhiteSpace($c)) { continue }
            $resolved = [System.IO.Path]::GetFullPath($c)
            $index = Join-Path $resolved 'index.html'
            if (Test-Path -LiteralPath $index) { return $resolved }
        } catch { }
    }
    return $null
}

function Get-DashboardContentType {
    param([string]$Path)
    switch -Regex ($Path) {
        '\.html$' { return 'text/html; charset=utf-8' }
        '\.js$'   { return 'application/javascript; charset=utf-8' }
        '\.css$'  { return 'text/css; charset=utf-8' }
        '\.svg$'  { return 'image/svg+xml' }
        '\.json$' { return 'application/json; charset=utf-8' }
        '\.ico$'  { return 'image/x-icon' }
        '\.woff2$' { return 'font/woff2' }
        default   { return 'application/octet-stream' }
    }
}

function Get-DashboardStaticResponse {
    param([string]$RequestPath)
    $root = Get-DashboardRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    $p = [string]$RequestPath
    if ([string]::IsNullOrWhiteSpace($p) -or $p -eq '/') { return $null }
    $low = $p.ToLowerInvariant()
    $rel = $null
    if ($low -eq '/download' -or $low -eq '/app' -or $low -eq '/index.html' -or $low -eq '/dashboard') {
        $rel = 'index.html'
    } elseif ($low.StartsWith('/assets/') -or $low -eq '/favicon.ico' -or $low.StartsWith('/dashboard/')) {
        $rel = $p.TrimStart('/').Replace('/', '\')
        if ($low.StartsWith('/dashboard/')) {
            $rel = $p.Substring('/dashboard/'.Length).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
        }
    } else {
        return $null
    }
    if ($rel -match '\.\.') { return $null }
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
    $rootFull = [System.IO.Path]::GetFullPath($root)
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not (Test-Path -LiteralPath $full)) { return $null }
    $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    $cache = 'no-store'
    if ($rel -like 'assets\*') { $cache = 'public, max-age=86400' }
    return (New-ProbeApiHttpResponse -Body $text -ContentType (Get-DashboardContentType -Path $full) -Headers @{ 'Cache-Control' = $cache })
}

function Get-ServerBrowseListing {
    [CmdletBinding()]
    param([string]$DirPath)
    $rootItems = New-Object System.Collections.ArrayList
    foreach ($d in @('C:\', 'C:\LOGO', 'C:\Program Files', 'C:\Program Files (x86)')) {
        if (Test-Path -LiteralPath $d) {
            [void]$rootItems.Add(@{ name = $d; path = $d; kind = 'root' })
        }
    }
    $desk = [Environment]::GetFolderPath('Desktop')
    if ($desk -and (Test-Path -LiteralPath $desk)) {
        [void]$rootItems.Add(@{ name = 'Masaustu'; path = $desk; kind = 'root' })
    }
    $fail = {
        param($msg, $p)
        $o = New-Object System.Collections.Specialized.OrderedDictionary
        $o.Add('error', [string]$msg)
        $o.Add('path', [string]$p)
        $o.Add('roots', $rootItems.ToArray())
        $o.Add('entries', @())
        return $o
    }
    try {
        $target = [string]$DirPath
        if ([string]::IsNullOrWhiteSpace($target)) { $target = 'C:\' }
        $target = $target.Trim().Trim('"')
        if ($target -match '\.\.' -or $target -notmatch '^[A-Za-z]:\\') {
            return (& $fail 'invalid_path' $target)
        }
        if (-not (Test-Path -LiteralPath $target)) {
            return (& $fail 'not_found' $target)
        }
        $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
        $dir = $item.FullName
        if (-not $item.PSIsContainer) {
            $dir = Split-Path -Parent $item.FullName
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { $parent = '' }
        $entryItems = New-Object System.Collections.ArrayList
        $count = 0
        foreach ($child in @(Get-ChildItem -LiteralPath $dir -ErrorAction SilentlyContinue)) {
            if ($count -ge 400) { break }
            $isDir = [bool]$child.PSIsContainer
            $ext = ''
            $previewable = $false
            if (-not $isDir) {
                $ext = ([string]$child.Extension).ToLowerInvariant()
                $previewable = $false
                if ($ext -in @('.txt','.log','.csv','.json','.xml','.ini','.rdp','.ps1','.md','.cfg','.conf','.bat','.cmd','.html','.css','.js','.yml','.yaml')) {
                    $previewable = $true
                }
            }
            $size = 0
            if (-not $isDir) {
                try { $size = [int64]$child.Length } catch { $size = 0 }
            }
            $kindName = 'file'
            if ($isDir) { $kindName = 'dir' }
            [void]$entryItems.Add(@{
                name      = [string]$child.Name
                path      = [string]$child.FullName
                kind      = $kindName
                extension = $ext
                size      = $size
                previewable = $previewable
            })
            $count++
        }
        $o = New-Object System.Collections.Specialized.OrderedDictionary
        $o.Add('path', [string]$dir)
        $o.Add('parent', [string]$parent)
        $o.Add('roots', $rootItems.ToArray())
        $o.Add('entries', $entryItems.ToArray())
        $o.Add('error', '')
        return $o
    } catch {
        return (& $fail ([string]$_.Exception.Message) $DirPath)
    }
}

function Save-ProbeApiConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $path = Get-ProbeApiConfigPath
    $dir  = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Config | ConvertTo-Json -Depth 6)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8)
}

function New-ProbeApiToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
}

# ---------------------------------------------------------------------------
# Token validation
# ---------------------------------------------------------------------------
function Test-ProbeApiToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProvidedToken,

        [string]$ConfiguredToken
    )

    if (-not $PSBoundParameters.ContainsKey('ConfiguredToken')) {
        $cfg = Get-ProbeApiConfig
        $ConfiguredToken = [string]$cfg.token
        if ([string]::IsNullOrWhiteSpace($ConfiguredToken) -and -not [string]::IsNullOrWhiteSpace($env:RDPVB_PROBE_TOKEN)) {
            $ConfiguredToken = $env:RDPVB_PROBE_TOKEN
        }
    }

    if ([string]::IsNullOrWhiteSpace($ConfiguredToken)) {
        # Token tanimlanmamis; auth devre disi (gelistirme kolayligi)
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($ProvidedToken)) { return $false }
    return [string]::Equals($ProvidedToken, $ConfiguredToken, [StringComparison]::OrdinalIgnoreCase)
}

# ---------------------------------------------------------------------------
# JSON helpers (PS 5.1 ConvertTo-Json + hashtable uyumu)
# ---------------------------------------------------------------------------
function ConvertTo-ProbePlainObject {
    [CmdletBinding()]
    param([Parameter()]$Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $o[[string]$k] = ConvertTo-ProbePlainObject -Value $Value[$k]
        }
        return [pscustomobject]$o
    }

    if ($Value -is [pscustomobject]) {
        $o = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) {
            $o[$p.Name] = ConvertTo-ProbePlainObject -Value $p.Value
        }
        return [pscustomobject]$o
    }

    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $o[[string]$k] = ConvertTo-ProbePlainObject -Value $Value[$k]
        }
        return [pscustomobject]$o
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $arr = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $arr.Add((ConvertTo-ProbePlainObject -Value $item))
        }
        return @($arr.ToArray())
    }

    return $Value
}

function ConvertTo-ProbeSerializable {
    [CmdletBinding()]
    param([Parameter()]$Value)

    if ($null -eq $Value) { return $null }

    $guard = 0
    while ($guard -lt 6 -and $null -ne $Value -and $Value -is [System.Management.Automation.PSObject]) {
        $base = $Value.PSObject.BaseObject
        if ($null -eq $base -or [object]::ReferenceEquals($base, $Value)) { break }
        $Value = $base
        $guard++
    }

    if ($Value -is [string]) { return [string]$Value }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [enum]) { return $Value.ToString() }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) {
        return $Value
    }

    if ($Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary] -or $Value -is [System.Collections.IDictionary]) {
        $map = New-Object 'System.Collections.Generic.Dictionary[string,object]'
        foreach ($k in @($Value.Keys)) {
            $map[[string]$k] = ConvertTo-ProbeSerializable -Value $Value[$k]
        }
        return $map
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            [void]$list.Add((ConvertTo-ProbeSerializable -Value $item))
        }
        return $list
    }

    if ($Value -is [pscustomobject]) {
        $map = New-Object 'System.Collections.Generic.Dictionary[string,object]'
        foreach ($p in $Value.PSObject.Properties) {
            if ($p.MemberType -ne 'NoteProperty') { continue }
            $map[$p.Name] = ConvertTo-ProbeSerializable -Value $p.Value
        }
        return $map
    }

    if ($null -eq $Value) { return $null }
    return [string]$Value
}

function ConvertTo-JsonEscapedString {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        switch ([int]$ch) {
            34 { [void]$sb.Append('\"') }      # "
            92 { [void]$sb.Append('\\') }      # \
            8  { [void]$sb.Append('\b') }
            12 { [void]$sb.Append('\f') }
            10 { [void]$sb.Append('\n') }
            13 { [void]$sb.Append('\r') }
            9  { [void]$sb.Append('\t') }
            default {
                if ($ch -lt [char]32) {
                    [void]$sb.AppendFormat('\u{0:x4}', [int]$ch)
                } else {
                    [void]$sb.Append($ch)
                }
            }
        }
    }
    return $sb.ToString()
}

function ConvertTo-ProbeJsonText {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return ('"{0}"' -f (ConvertTo-JsonEscapedString -Text $Value)) }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) {
        return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($k in @($Value.Keys)) {
            $keyJson = '"{0}"' -f (ConvertTo-JsonEscapedString -Text ([string]$k))
            $valJson = ConvertTo-ProbeJsonText -Value $Value[$k]
            [void]$parts.Add(($keyJson + ':' + $valJson))
        }
        return ('{' + ($parts -join ',') + '}')
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in $Value) {
            [void]$parts.Add((ConvertTo-ProbeJsonText -Value $item))
        }
        return ('[' + ($parts -join ',') + ']')
    }
    return ('"{0}"' -f (ConvertTo-JsonEscapedString -Text ([string]$Value)))
}

function ConvertTo-ProbeJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $InputObject,
        [int]$Depth = 10
    )
    return [RdpProbeJson]::Encode($InputObject)
}

function New-ProbeComponent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok','warning','error','unknown')][string]$Status,
        [string]$Value = '',
        [string[]]$Details = @()
    )
    $detailItems = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($Details)) {
        if ($null -ne $d -and $d -ne '') { [void]$detailItems.Add([string]$d) }
    }
    $result = New-Object System.Collections.Specialized.OrderedDictionary
    $result.Add('name', $Name)
    $result.Add('status', $Status)
    $result.Add('value', $Value)
    $result.Add('details', $detailItems.ToArray())
    return $result
}

function Test-LocalTcpPortOpen {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port
    )
    try {
        $props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        foreach ($ep in $props.GetActiveTcpListeners()) {
            if ($ep.Port -eq $Port) { return $true }
        }
    } catch {
        Write-Verbose "TCP listener taramasi basarisiz: $($_.Exception.Message)"
    }
    return $false
}

function Get-LocalPrimaryIpv4 {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    try {
        $addrs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.PrefixOrigin -ne 'WellKnown' -and
                $_.InterfaceAlias -notmatch 'Loopback'
            })
        $lan = $addrs | Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -First 1
        if ($lan) { return $lan.IPAddress.ToString() }
        if ($addrs.Count -gt 0) { return $addrs[0].IPAddress.ToString() }
    } catch { }
    try {
        $hostEntry = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)
        $ips = @($hostEntry.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.ToString() })
        $lan = $ips | Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } | Select-Object -First 1
        if ($lan) { return [string]$lan }
        if ($ips.Count -gt 0) { return [string]$ips[0] }
    } catch { }
    return '127.0.0.1'
}

function Get-PublicIpv4 {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com')) {
        try {
            $txt = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 6).Content
            $txt = ($txt -replace '\s', '')
            if ($txt -match '^\d{1,3}(\.\d{1,3}){3}$') { return $txt }
        } catch { }
    }
    return $null
}

function Get-VpnIpv4 {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    try {
        $addr = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceAlias -match 'Radmin|VPN|Tailscale|WireGuard' -and $_.IPAddress -notlike '127.*' } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($addr) { return [string]$addr }
    } catch { }
    return $null
}

function Get-LocalRdsFeatureMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $map = [ordered]@{
        SessionHost       = $false
        WebAccess         = $false
        Gateway           = $false
        Licensing         = $false
        ConnectionBroker  = $false
        AnyRds            = $false
    }

    try {
        $features = @(Get-WindowsFeature -Name 'RDS-*' -ErrorAction Stop)
        foreach ($f in $features) {
            if ($f.InstallState -ne 'Installed') { continue }
            $map.AnyRds = $true
            switch -Regex ($f.Name) {
                '^RDS-RD-Server$'           { $map.SessionHost = $true }
                '^RDS-Web-Access$'          { $map.WebAccess = $true }
                '^RDS-Gateway$'             { $map.Gateway = $true }
                '^RDS-Licensing$'           { $map.Licensing = $true }
                '^RDS-Connection-Broker$'   { $map.ConnectionBroker = $true }
            }
        }
    } catch {
        Write-Verbose "Get-WindowsFeature RDS-* basarisiz: $($_.Exception.Message)"
    }

    return $map
}

function Get-LocalRemoteAppEntries {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $apps = New-Object System.Collections.Generic.List[object]
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
        if ($isAdmin -and (Get-Command -Name 'Get-RDRemoteApp' -ErrorAction SilentlyContinue)) {
            $items = @(Get-RDRemoteApp -ErrorAction Stop)
            foreach ($item in $items) {
                $alias = [string]$item.Alias
                $name  = [string]$item.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $alias }
                $apps.Add([ordered]@{
                    id       = $alias
                    alias    = $alias
                    name     = $name
                    path     = [string]$item.FilePath
                    publisher = [string]$item.CollectionName
                    icon     = [string]$item.FilePath
                    iconPath = [string]$item.FilePath
                })
            }
        }
    } catch {
        Write-Verbose "Get-RDRemoteApp basarisiz: $($_.Exception.Message)"
    }

    if ($apps.Count -eq 0) {
        $manifest = Get-ProbeManifestObject -ErrorAction SilentlyContinue
        if ($manifest) {
            $remoteAppsProp = $manifest.PSObject.Properties['remoteApps']
            $remoteApps = $null
            if ($remoteAppsProp) { $remoteApps = $remoteAppsProp.Value }
            foreach ($item in @($remoteApps)) {
                if ($null -eq $item) { continue }
                $alias = $null
                $name  = $null
                $path  = $null
                $publisher = $null
                $icon = $null
                if ($item -is [System.Collections.IDictionary]) {
                    if ($item.Contains('alias')) { $alias = [string]$item['alias'] }
                    if ($item.Contains('name')) { $name = [string]$item['name'] }
                    if ($item.Contains('path')) { $path = [string]$item['path'] }
                    if ($item.Contains('publisher')) { $publisher = [string]$item['publisher'] }
                    if ($item.Contains('icon')) { $icon = [string]$item['icon'] }
                } else {
                    $pAlias = $item.PSObject.Properties['alias']
                    $pName  = $item.PSObject.Properties['name']
                    $pPath  = $item.PSObject.Properties['path']
                    $pPub   = $item.PSObject.Properties['publisher']
                    $pIcon  = $item.PSObject.Properties['icon']
                    if ($pAlias) { $alias = [string]$pAlias.Value }
                    if ($pName)  { $name  = [string]$pName.Value }
                    if ($pPath)  { $path  = [string]$pPath.Value }
                    if ($pPub)   { $publisher = [string]$pPub.Value }
                    if ($pIcon)  { $icon  = [string]$pIcon.Value }
                }
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $apps.Add([ordered]@{
                    id        = $alias
                    alias     = $alias
                    name      = $(if ($name) { $name } else { $alias })
                    path      = $path
                    publisher = $publisher
                    icon      = $icon
                    iconPath  = $icon
                })
            }
        }
    }

    $seen = @{}
    foreach ($existingApp in $apps) {
        $id = [string]$existingApp['alias']
        if ($id) { $seen[$id.ToLowerInvariant()] = $true }
    }
    $allowKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\Applications'
    if (Test-Path -LiteralPath $allowKey) {
        foreach ($child in @(Get-ChildItem -LiteralPath $allowKey -ErrorAction SilentlyContinue)) {
            $alias = [string]$child.PSChildName
            if ([string]::IsNullOrWhiteSpace($alias)) { continue }
            if ($seen.ContainsKey($alias.ToLowerInvariant())) { continue }
            try {
                $prop = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction Stop
                $name = [string]$prop.Name
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $alias }
                $apps.Add([ordered]@{
                    id        = $alias
                    alias     = $alias
                    name      = $name
                    path      = [string]$prop.Path
                    publisher = 'TSAppAllowList'
                    icon      = [string]$prop.Path
                    iconPath  = [string]$prop.Path
                })
                $seen[$alias.ToLowerInvariant()] = $true
            } catch {}
        }
    }

    return $apps
}

function Get-ProbeManifestPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path -Path $env:ProgramData -ChildPath $Script:ManifestRelPath)
}

function Get-ProbeManifestObject {
    [CmdletBinding()]
    param()
    $path = Get-ProbeManifestPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Verbose "Manifest okunamadi: $($_.Exception.Message)"
        return $null
    }
}

function Get-LocalCertificateStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $details = @()
    $thumb = $null
    try {
        $setting = Get-CimInstance -Namespace 'root\cimv2\TerminalServices' -ClassName 'Win32_TSGeneralSetting' -ErrorAction Stop |
            Select-Object -First 1
        if ($setting -and $setting.SSLCertificateSHA1Hash) {
            $thumb = [string]$setting.SSLCertificateSHA1Hash
        }
    } catch {
        $details += "Win32_TSGeneralSetting: $($_.Exception.Message)"
    }

    if ($thumb) {
        return New-ProbeComponent -Name 'Certificate' -Status 'ok' -Value $thumb -Details $details
    }
    return New-ProbeComponent -Name 'Certificate' -Status 'warning' -Value 'Not bound' -Details $details
}

function Get-LocalLicenseStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $role = $false
    try {
        $feat = Get-WindowsFeature -Name 'RDS-Licensing' -ErrorAction SilentlyContinue
        $role = [bool]($feat -and $feat.InstallState -eq 'Installed')
    } catch { }

    $grace = 0
    try {
        $key = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters\License' -ErrorAction SilentlyContinue
        if ($key -and $null -ne $key.GracePeriod) {
            $grace = [int]$key.GracePeriod
        }
    } catch { }

    if ($role) {
        return New-ProbeComponent -Name 'License' -Status 'ok' -Value "RDS-Licensing installed (grace=$grace)" -Details @()
    }
    if ($grace -gt 0) {
        return New-ProbeComponent -Name 'License' -Status 'warning' -Value "Grace period (~$grace days)" -Details @('Activate RDS CAL or use Guacamole fallback')
    }
    return New-ProbeComponent -Name 'License' -Status 'warning' -Value 'No RDS licensing role' -Details @('Install Guacamole or activate RDS CAL')
}

# ---------------------------------------------------------------------------
# Yerel probe (WinRM gerekmez — bu API sunucunun kendisinde kosar)
# ---------------------------------------------------------------------------
function Get-LocalServerProbeResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ServerName = $env:COMPUTERNAME
    )

    if ([string]::IsNullOrWhiteSpace($ServerName)) { $ServerName = $env:COMPUTERNAME }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    $ip  = Get-LocalPrimaryIpv4
    $publicIp = Get-PublicIpv4
    $vpnIp = Get-VpnIpv4
    $clientIp = if ($publicIp) { $publicIp } else { $ip }
    $os  = ''
    $domain = 'WORKGROUP'

    try {
        $osCim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $os = (($osCim.Caption -replace '\s+', ' ').Trim())
    } catch { $os = [System.Environment]::OSVersion.ToString() }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Domain) { $domain = [string]$cs.Domain }
        if ($cs.DNSHostName) { $ServerName = [string]$cs.DNSHostName }
    } catch { }

    $features = Get-LocalRdsFeatureMap
    $rdpPort = Get-ConfiguredRdpPort
    $rdpOpen  = Test-LocalTcpPortOpen -Port $rdpPort
    $httpsOpen = Test-LocalTcpPortOpen -Port $Script:HttpsPort
    $guacOpen  = Test-LocalTcpPortOpen -Port $Script:GuacamolePort
    $winrmOpen = Test-LocalTcpPortOpen -Port $Script:WinRmPort
    $probeOpen = Test-LocalTcpPortOpen -Port $Script:DefaultProbePort

    $apps = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-LocalRemoteAppEntries)) {
        [void]$apps.Add($entry)
    }

    $rdWebUrl = "https://${clientIp}/RDWeb/webclient"
    $rdWebUrlLan = "https://${ip}/RDWeb/webclient"
    $guacUrl  = "https://${clientIp}:$($Script:GuacamolePort)/guacamole"
    $rdWebOk  = ($features.WebAccess -and $httpsOpen)
    $guacOk   = $guacOpen

    $webType = 'None'
    $webUrl  = ''
    if ($rdWebOk -and $guacOk) { $webType = 'Both'; $webUrl = $guacUrl }
    elseif ($rdWebOk) { $webType = 'RDWeb'; $webUrl = $rdWebUrl }
    elseif ($guacOk) { $webType = 'Guacamole'; $webUrl = $guacUrl }

    $recommendations = New-Object System.Collections.Generic.List[string]
    if (-not $features.AnyRds) { $recommendations.Add('RDS rollerini kurun (Server Setup sihirbazi).') }
    if (-not $rdpOpen) { $recommendations.Add('RDP 3389 dinlemiyor; TermService / firewall kontrol edin.') }
    if ($apps.Count -eq 0) { $recommendations.Add('Henuz RemoteApp yayinlanmamis. AppScanner + RemoteAppPublisher kullanin.') }
    if (-not $guacOk -and -not $rdWebOk) { $recommendations.Add('HTML5 erisim icin RD Web veya Guacamole kurun.') }

    $probe = [ordered]@{
        server     = $ServerName
        reachable  = $true
        os         = $os
        domain     = $domain
        ip         = $clientIp
        ips        = [ordered]@{
            lan    = $ip
            public = $publicIp
            vpn    = $vpnIp
            client = $clientIp
        }
        components = [ordered]@{
            WinRM          = New-ProbeComponent -Name 'WinRM' -Status $(if ($winrmOpen) { 'ok' } else { 'warning' }) -Value $(if ($winrmOpen) { "$($Script:WinRmPort) open" } else { "$($Script:WinRmPort) closed" })
            OS             = New-ProbeComponent -Name 'OS' -Status 'ok' -Value $os
            Domain         = New-ProbeComponent -Name 'Domain' -Status $(if ($domain -and $domain -ne 'WORKGROUP') { 'ok' } else { 'warning' }) -Value $domain
            RDS_Role       = New-ProbeComponent -Name 'RDS_Role' -Status $(if ($features.AnyRds) { 'ok' } else { 'error' }) -Value $(if ($features.AnyRds) { 'Installed' } else { 'Not Installed' })
            RD_SessionHost = New-ProbeComponent -Name 'RD_SessionHost' -Status $(if ($features.SessionHost) { 'ok' } else { 'error' }) -Value $(if ($features.SessionHost) { 'Installed' } else { 'Not Installed' })
            RD_WebAccess   = New-ProbeComponent -Name 'RD_WebAccess' -Status $(if ($features.WebAccess) { 'ok' } else { 'warning' }) -Value $(if ($features.WebAccess) { 'Installed' } else { 'Not Installed' })
            RD_Gateway     = New-ProbeComponent -Name 'RD_Gateway' -Status $(if ($features.Gateway) { 'ok' } else { 'warning' }) -Value $(if ($features.Gateway) { 'Installed' } else { 'Missing' })
            RemoteApps     = New-ProbeComponent -Name 'RemoteApps' -Status $(if ($apps.Count -gt 0) { 'ok' } else { 'warning' }) -Value "$($apps.Count) application(s) published"
            RDP_Port       = New-ProbeComponent -Name 'RDP_Port' -Status $(if ($rdpOpen) { 'ok' } else { 'error' }) -Value $(if ($rdpOpen) { "$rdpPort open" } else { "$rdpPort closed/filtered" })
            HTTPS_Port     = New-ProbeComponent -Name 'HTTPS_Port' -Status $(if ($httpsOpen) { 'ok' } else { 'warning' }) -Value $(if ($httpsOpen) { "$($Script:HttpsPort) open" } else { "$($Script:HttpsPort) closed/filtered" })
            Guacamole_Port = New-ProbeComponent -Name 'Guacamole_Port' -Status $(if ($guacOk) { 'ok' } else { 'warning' }) -Value $(if ($guacOk) { "$($Script:GuacamolePort) open" } else { "$($Script:GuacamolePort) closed/filtered" })
            ProbeApi_Port  = New-ProbeComponent -Name 'ProbeApi_Port' -Status $(if ($probeOpen) { 'ok' } else { 'warning' }) -Value $(if ($probeOpen) { "$($Script:DefaultProbePort) open" } else { "$($Script:DefaultProbePort) starting" })
            Certificate    = Get-LocalCertificateStatus
            License        = Get-LocalLicenseStatus
        }
        existingRemoteApps = $null
        webEndpoint = [ordered]@{
            type               = $webType
            url                = $webUrl
            rdWebAvailable     = [bool]$rdWebOk
            guacamoleAvailable = [bool]$guacOk
            rdWebUrl           = $(if ($rdWebOk) { $rdWebUrl } else { $null })
            rdWebUrlLan        = $(if ($rdWebOk) { $rdWebUrlLan } else { $null })
            guacamoleUrl       = $(if ($guacOk) { $guacUrl } else { $null })
        }
        connectionStrategies = [ordered]@{
            direct     = [ordered]@{ available = [bool]$rdpOpen;  port = $rdpPort;  url = "${clientIp}:$rdpPort"; lanUrl = "${ip}:$rdpPort" }
            gateway    = [ordered]@{ available = [bool]($httpsOpen -and $features.Gateway); port = $Script:HttpsPort; url = $(if ($httpsOpen -and $features.Gateway) { "https://${clientIp}:$($Script:HttpsPort)" } else { $null }) }
            guacamole  = [ordered]@{ available = [bool]$guacOk; url = $(if ($guacOk) { $guacUrl } else { $null }) }
            tailscale  = [ordered]@{ available = $false }
            cloudflare = [ordered]@{ available = $false }
        }
        recommendations = $null
        generatedAt     = $now
        timestamp       = $now
        probeApi        = [ordered]@{
            enabled = $true
            version = $Script:ProbeApiVersion
            port    = $Script:DefaultProbePort
            url     = "http://${clientIp}:$($Script:DefaultProbePort)$($Script:DefaultProbePath)"
        }
    }

    $probe['existingRemoteApps'] = $apps.ToArray()
    $probe['recommendations'] = $recommendations.ToArray()

    return $probe
}

function Get-ServerProbeResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    return Get-LocalServerProbeResult -ServerName $ServerName
}

function Get-LiveServerManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $existing = Get-ProbeManifestObject
    $probe    = Get-LocalServerProbeResult
    $cfg      = Get-ProbeApiConfig

    $remoteApps = $probe.existingRemoteApps
    $certComp   = $probe.components['Certificate']

    $manifest = [ordered]@{
        manifestVersion = '1.0.0'
        generatedAt     = $probe.generatedAt
        server = [ordered]@{
            fqdn   = $probe.server
            ip     = $probe.ip
            domain = $probe.domain
            os     = $probe.os
        }
        connectionStrategies = [ordered]@{
            direct     = [ordered]@{ enabled = [bool]$probe.connectionStrategies.direct.available;     port = (Get-ConfiguredRdpPort);    url = $probe.connectionStrategies.direct.url }
            gateway    = [ordered]@{ enabled = [bool]$probe.connectionStrategies.gateway.available;    port = $Script:HttpsPort;  url = $probe.connectionStrategies.gateway.url }
            guacamole  = [ordered]@{ enabled = [bool]$probe.connectionStrategies.guacamole.available;  port = $Script:GuacamolePort; url = $probe.connectionStrategies.guacamole.url }
            tailscale  = [ordered]@{ enabled = $false; url = $null }
            cloudflare = [ordered]@{ enabled = $false; url = $null }
        }
        webEndpoint = [ordered]@{
            type = $probe.webEndpoint.type
            url  = $probe.webEndpoint.url
        }
        remoteApps  = $null
        certificate = [ordered]@{
            thumbprint = $(if ($certComp.value -and $certComp.status -eq 'ok') { $certComp.value } else { $null })
            type       = $(if ($certComp.status -eq 'ok') { 'Unknown' } else { $null })
        }
        probeApi = [ordered]@{
            enabled = $true
            port    = [int]$cfg.port
            auth    = [string]$cfg.auth
            url     = $probe.probeApi.url
        }
    }

    if ($null -eq $remoteApps) {
        $manifest['remoteApps'] = New-Object object[] 0
    } elseif ($remoteApps -is [System.Collections.IList]) {
        $tmp = New-Object System.Collections.Generic.List[object]
        foreach ($ra in $remoteApps) { [void]$tmp.Add($ra) }
        $manifest['remoteApps'] = $tmp.ToArray()
    } else {
        $manifest['remoteApps'] = @($remoteApps)
    }

    if ($existing) {
        try {
            if ($existing.certificate -and $existing.certificate.thumbprint) {
                $manifest.certificate.thumbprint = [string]$existing.certificate.thumbprint
                $manifest.certificate.type       = [string]$existing.certificate.type
            }
            if ($existing.connectionStrategies) {
                foreach ($name in @('tailscale','cloudflare')) {
                    $src = $existing.connectionStrategies.$name
                    if ($src -and $src.enabled) {
                        $manifest.connectionStrategies[$name] = [ordered]@{
                            enabled = $true
                            url     = $src.url
                        }
                    }
                }
            }
        } catch { }
    }

    return $manifest
}

function Get-ProbeHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $cfg = Get-ProbeApiConfig
    return [ordered]@{
        status   = 'ok'
        service  = 'RdpVirtualBoxApp-ProbeApi'
        version  = $Script:ProbeApiVersion
        hostname = $env:COMPUTERNAME
        port     = [int]$cfg.port
        rdpPort  = Get-ConfiguredRdpPort
        time     = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-ProbeStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $probe = Get-LocalServerProbeResult
    $health = Get-ProbeHealth
    return [ordered]@{
        health   = $health
        server   = $probe.server
        os       = $probe.os
        ip       = $probe.ip
        ips      = $probe.ips
        domain   = $probe.domain
        rds      = [ordered]@{
            sessionHost = ($probe.components['RD_SessionHost'].status -eq 'ok')
            webAccess   = ($probe.components['RD_WebAccess'].status -eq 'ok')
            gateway     = ($probe.components['RD_Gateway'].status -eq 'ok')
        }
        ports    = [ordered]@{
            rdp       = ($probe.components['RDP_Port'].status -eq 'ok')
            https     = ($probe.components['HTTPS_Port'].status -eq 'ok')
            guacamole = ($probe.components['Guacamole_Port'].status -eq 'ok')
            probeApi  = $true
        }
        remoteAppCount = @($probe.existingRemoteApps).Count
        webEndpoint    = $probe.webEndpoint
        generatedAt    = $probe.generatedAt
    }
}

function Get-ProbeCatalog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return [ordered]@{
        service   = 'RdpVirtualBoxApp-ProbeApi'
        version   = $Script:ProbeApiVersion
        endpoints = @(
            [ordered]@{ method = 'GET'; path = '/health';              auth = $false; description = 'Liveness' }
            [ordered]@{ method = 'GET'; path = '/api/health';          auth = $false; description = 'Liveness (alias)' }
            [ordered]@{ method = 'GET'; path = '/probe/api/health';    auth = $false; description = 'Liveness (probe prefix)' }
            [ordered]@{ method = 'GET'; path = '/probe/api/probe';     auth = $true;  description = 'Full server probe (Swift / client)' }
            [ordered]@{ method = 'GET'; path = '/api/probe';           auth = $true;  description = 'Full server probe (alias)' }
            [ordered]@{ method = 'GET'; path = '/probe/api/manifest';  auth = $true;  description = 'server-manifest.json' }
            [ordered]@{ method = 'GET'; path = '/api/manifest';        auth = $true;  description = 'server-manifest.json (alias)' }
            [ordered]@{ method = 'GET'; path = '/probe/api/apps';      auth = $true;  description = 'Published RemoteApps' }
            [ordered]@{ method = 'GET';  path = '/api/apps';            auth = $false; description = 'Yayinli RemoteApps' }
            [ordered]@{ method = 'POST'; path = '/api/apps';            auth = $true;  description = 'EXE yolundan RemoteApp yayinla' }
            [ordered]@{ method = 'GET';  path = '/api/browse';          auth = $true;  description = 'Sunucu klasor / EXE gezgini' }
            [ordered]@{ method = 'GET';  path = '/probe/api/status';    auth = $true;  description = 'Compact status' }
            [ordered]@{ method = 'GET';  path = '/api/status';          auth = $true;  description = 'Compact status (alias)' }
            [ordered]@{ method = 'GET';  path = '/download';            auth = $false; description = 'React RemoteApp dashboard' }
            [ordered]@{ method = 'GET'; path = '/rdp';                 auth = $false; description = 'Indirilebilir .rdp listesi' }
            [ordered]@{ method = 'GET'; path = '/rdp/public.rdp';      auth = $false; description = 'Public IP RemoteApp .rdp' }
            [ordered]@{ method = 'GET'; path = '/';                    auth = $false; description = 'This catalog' }
        )
    }
}

# ---------------------------------------------------------------------------
# ServerProbe.ps1 sarmalayicisi (uzak WinRM yolu; yerelde Get-Local* kullanilir)
# ---------------------------------------------------------------------------
function Invoke-ProbeApi {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,

        [int]$ProbePort = 8444
    )

    try {
        if (Get-Command -Name 'Invoke-ServerProbe' -ErrorAction SilentlyContinue) {
            # Istemci modulu yuklu ise (nadir, sunucu hostunda) uzak tarama.
            # Credential yok; yerel sonuca dus.
        }
        return Get-LocalServerProbeResult -ServerName $ServerName
    }
    catch {
        Write-Error -ErrorRecord $_
        return @{
            server = $ServerName
            components = @{
                _error = @{
                    status  = 'error'
                    value   = $_.Exception.Message
                    details = @()
                }
            }
            webEndpoint = @{ rdWebAvailable = $false; guacamoleAvailable = $false }
            existingRemoteApps = @()
            recommendations = @("Probe API hatasi: $($_.Exception.Message)")
            generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

function Get-HeaderValue {
    [CmdletBinding()]
    param(
        $Headers,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Headers) { return $null }
    if ($Headers -is [hashtable] -or $Headers -is [System.Collections.IDictionary]) {
        foreach ($k in $Headers.Keys) {
            if ([string]::Equals([string]$k, $Name, [StringComparison]::OrdinalIgnoreCase)) {
                return [string]$Headers[$k]
            }
        }
        return $null
    }
    try {
        $prop = $Headers.$Name
        if ($prop) { return [string]$prop }
    } catch { }
    return $null
}

function ConvertFrom-QueryString {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$RawQuery)

    $q = @{}
    if ([string]::IsNullOrWhiteSpace($RawQuery)) { return $q }
    $trimmed = $RawQuery.TrimStart('?')
    foreach ($part in ($trimmed -split '&')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $kv = $part -split '=', 2
        $key = [Uri]::UnescapeDataString($kv[0])
        $val = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { '' }
        $q[$key] = $val
    }
    return $q
}

function New-RemoteAppRdpText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$TargetIp,
        [int]$Port = 3389,
        [Parameter(Mandatory)][string]$Alias,
        [string]$DisplayName,
        [string]$UserName
    )
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Alias }
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $dom = $env:USERDOMAIN
        if ([string]::IsNullOrWhiteSpace($dom)) { $dom = $env:COMPUTERNAME }
        $UserName = '{0}\{1}' -f $dom, $env:USERNAME
    }
    $lines = @(
        "full address:s:$TargetIp"
        "server port:i:$Port"
        "username:s:$UserName"
        'prompt for credentials:i:1'
        'authentication level:i:2'
        'negotiate security layer:i:1'
        'remoteapplicationmode:i:1'
        "remoteapplicationprogram:s:||$Alias"
        "remoteapplicationname:s:$DisplayName"
        'disableremoteappcapscheck:i:1'
        'alternate shell:s:rdpinit.exe'
        'screen mode id:i:2'
        'use multimon:i:1'
        'audiomode:i:0'
        'redirectprinters:i:0'
        'redirectcomports:i:0'
        'redirectsmartcards:i:0'
        'redirectclipboard:i:1'
        'autoreconnection enabled:i:1'
        'bandwidthautodetect:i:1'
        'networkautodetect:i:1'
    )
    return (($lines -join "`r`n") + "`r`n")
}

function Get-RemoteAppDownloadItems {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$CustomerId)
    $entry = Get-CustomerPortalEntry -CustomerId $CustomerId
    $cust = $entry.Customer
    $cfg = $entry.Config
    $publicIp = [string]$cust['publicIp']; if (-not $publicIp) { $publicIp = [string]$cust.publicIp }
    $lanIp = [string]$cust['lanIp']; if (-not $lanIp) { $lanIp = [string]$cust.lanIp }
    $vpnIp = [string]$cust['vpnIp']; if (-not $vpnIp) { $vpnIp = [string]$cust.vpnIp }
    $wanPort = [int]$cust['rdpPort']; if (-not $wanPort) { $wanPort = [int]$cust.rdpPort }
    $lanPort = [int]$cust['lanRdpPort']; if (-not $lanPort) { $lanPort = [int]$cust.lanRdpPort }
    if ($wanPort -lt 1) { $wanPort = [int]$cfg.listenRdpPort }
    if ($lanPort -lt 1) { $lanPort = [int]$cfg.listenRdpPort }
    $cid = [string]$cust['id']; if (-not $cid) { $cid = [string]$cust.id }
    $q = 'customer=' + [Uri]::EscapeDataString($cid)
    $apps = @(Get-LocalRemoteAppEntries)
    if ($apps.Count -eq 0) {
        $apps = @([ordered]@{ alias = 'Tiger3Ent'; name = 'Tiger3 Enterprise'; path = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe' })
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($app in $apps) {
        $alias = [string]$app['alias']
        if (-not $alias) { $alias = [string]$app.alias }
        $name = [string]$app['name']
        if (-not $name) { $name = [string]$app.name }
        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
        $targets = @(
            @{ Kind = 'public'; Label = 'Public (WAN)'; Host = $publicIp; Port = $wanPort; File = "$alias-Public.rdp"; Url = "/rdp/$alias-public.rdp?$q" }
            @{ Kind = 'lan';    Label = 'LAN';          Host = $lanIp;    Port = $lanPort; File = "$alias-LAN.rdp";    Url = "/rdp/$alias-lan.rdp?$q" }
        )
        if ($vpnIp) {
            $targets += @{ Kind = 'vpn'; Label = 'VPN'; Host = $vpnIp; Port = $lanPort; File = "$alias-VPN.rdp"; Url = "/rdp/$alias-vpn.rdp?$q" }
        }
        foreach ($t in $targets) {
            if ([string]::IsNullOrWhiteSpace($t.Host)) { continue }
            [void]$items.Add([ordered]@{
                alias       = $alias
                name        = $name
                kind        = $t.Kind
                label       = $t.Label
                host        = $t.Host
                port        = [int]$t.Port
                fileName    = $t.File
                url         = $t.Url.ToLowerInvariant()
                customerId  = $cid
            })
        }
    }
    return $items.ToArray()
}

function Get-RemoteAppRdpDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$CustomerId,
        [int]$RdpPort = 0
    )

    $safe = [string]$FileName
    $safe = $safe.Trim().TrimStart('/')
    if ($safe -like '*/*' -or $safe -like '*..*') { return $null }
    $lower = $safe.ToLowerInvariant()
    if ($lower -notlike '*.rdp') { return $null }

    $entry = Get-CustomerPortalEntry -CustomerId $CustomerId
    $cust = $entry.Customer
    $cfg = $entry.Config
    $apps = @(Get-LocalRemoteAppEntries)
    if ($apps.Count -eq 0) {
        $apps = @([ordered]@{ alias = 'Tiger3Ent'; name = 'Tiger3 Enterprise'; path = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe' })
    }

    $kind = $null
    $alias = $null
    if ($lower -eq 'public.rdp' -or $lower -eq 'wan.rdp') { $kind = 'public' }
    elseif ($lower -eq 'lan.rdp') { $kind = 'lan' }
    elseif ($lower -eq 'vpn.rdp') { $kind = 'vpn' }
    elseif ($lower -match '^([a-z0-9._-]+)-(public|wan|lan|vpn)\.rdp$') {
        $alias = $Matches[1]
        $kind = $Matches[2]
        if ($kind -eq 'wan') { $kind = 'public' }
    } else {
        return $null
    }

    $app = $null
    if ($alias) {
        $app = $apps | Where-Object {
            $a = $null
            if ($_ -is [System.Collections.IDictionary]) { $a = [string]$_['alias'] }
            else { $a = [string]$_.alias }
            $a -and ($a.ToLowerInvariant() -eq $alias)
        } | Select-Object -First 1
    }
    if (-not $app) { $app = $apps | Select-Object -First 1 }
    $appAlias = [string]$app['alias']; if (-not $appAlias) { $appAlias = [string]$app.alias }
    $appName  = [string]$app['name']; if (-not $appName) { $appName = [string]$app.name }

    $publicIp = [string]$cust['publicIp']; if (-not $publicIp) { $publicIp = [string]$cust.publicIp }
    $lanIp = [string]$cust['lanIp']; if (-not $lanIp) { $lanIp = [string]$cust.lanIp }
    $vpnIp = [string]$cust['vpnIp']; if (-not $vpnIp) { $vpnIp = [string]$cust.vpnIp }
    $wanPort = [int]$cust['rdpPort']; if (-not $wanPort) { $wanPort = [int]$cust.rdpPort }
    $lanPort = [int]$cust['lanRdpPort']; if (-not $lanPort) { $lanPort = [int]$cust.lanRdpPort }
    if ($wanPort -lt 1) { $wanPort = [int]$cfg.listenRdpPort }
    if ($lanPort -lt 1) { $lanPort = [int]$cfg.listenRdpPort }

    $hostIp = $null
    $port = $lanPort
    switch ($kind) {
        'public' { $hostIp = $publicIp; $port = $wanPort }
        'lan'    { $hostIp = $lanIp; $port = $lanPort }
        'vpn'    { $hostIp = $vpnIp; $port = $lanPort }
    }
    if ($RdpPort -ge 1 -and $RdpPort -le 65535) { $port = $RdpPort }
    if ([string]::IsNullOrWhiteSpace($hostIp)) { return $null }

    $outName = '{0}-{1}.rdp' -f $appAlias, ($(if ($kind -eq 'public') { 'Public' } elseif ($kind -eq 'lan') { 'LAN' } else { 'VPN' }))
    $text = New-RemoteAppRdpText -TargetIp $hostIp -Port $port -Alias $appAlias -DisplayName $appName
    return [ordered]@{ FileName = $outName; Content = $text; Host = $hostIp; Port = $port }
}

function Get-RemoteAppDownloadIndex {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$CustomerId)
    $entry = Get-CustomerPortalEntry -CustomerId $CustomerId
    $cfg = $entry.Config
    $cust = $entry.Customer
    $items = @(Get-RemoteAppDownloadItems -CustomerId $CustomerId)
    return [ordered]@{
        webPort        = [int]$cfg.webPort
        listenRdpPort  = [int]$cfg.listenRdpPort
        customer       = $cust
        customers      = @($cfg.customers)
        rdpPort        = $(if ($cust.rdpPort) { [int]$cust.rdpPort } else { [int]$cust['rdpPort'] })
        publicIp       = $(if ($cust.publicIp) { [string]$cust.publicIp } else { [string]$cust['publicIp'] })
        lanIp          = $(if ($cust.lanIp) { [string]$cust.lanIp } else { [string]$cust['lanIp'] })
        vpnIp          = $(if ($cust.vpnIp) { [string]$cust.vpnIp } else { [string]$cust['vpnIp'] })
        download       = '/download'
        files          = $items
    }
}

function Get-RemoteAppDownloadHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return @'
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RemoteApp portal</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#0f172a;color:#e2e8f0}
.wrap{max-width:860px;margin:24px auto;padding:0 16px}
.card{background:#1e293b;border-radius:12px;padding:20px;margin-bottom:16px}
h1{margin:0 0 8px;font-size:22px}
label{display:block;margin:10px 0 4px;color:#94a3b8;font-size:13px}
input,select{width:100%;box-sizing:border-box;padding:8px;border-radius:8px;border:1px solid #334155;background:#0f172a;color:#e2e8f0}
.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
button,.btn{display:inline-block;margin:8px 8px 0 0;padding:8px 14px;border-radius:8px;border:0;background:#38bdf8;color:#0f172a;font-weight:700;cursor:pointer;text-decoration:none}
button.secondary{background:#334155;color:#e2e8f0}
a{color:#38bdf8}
.note{font-size:13px;color:#94a3b8;line-height:1.45}
#status{min-height:1.2em;margin-top:8px}
ul{padding-left:18px}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <h1>RemoteApp indirme</h1>
    <p class="note">Web portu <code>8001</code>. Her musteri icin WAN RDP portu farkli olabilir; .rdp bu portu yazar. Sunucu iceride tek RDP portu dinler (NAT: musteri WAN portu -&gt; sunucu dinleme portu).</p>
    <label>Musteri</label>
    <select id="customer"></select>
    <div class="row">
      <div><label>Musteri adi</label><input id="name"></div>
      <div><label>Public IP</label><input id="publicIp"></div>
    </div>
    <div class="row">
      <div><label>WAN RDP portu (musteri .rdp)</label><input id="rdpPort" type="number" min="1" max="65535"></div>
      <div><label>LAN/VPN RDP portu</label><input id="lanRdpPort" type="number" min="1" max="65535"></div>
    </div>
    <div class="row">
      <div><label>LAN IP</label><input id="lanIp"></div>
      <div><label>Web portu</label><input id="webPort" type="number" min="1" max="65535"></div>
    </div>
    <label>Yonetici token (kayit icin, istege bagli)</label>
    <input id="token" placeholder="Bearer token" type="password">
    <div>
      <button type="button" id="save">Kaydet</button>
      <button type="button" id="add" class="secondary">Yeni musteri</button>
    </div>
    <p id="status" class="note"></p>
  </div>
  <div class="card">
    <h2>Indir</h2>
    <ul id="files"></ul>
    <p>
      <a class="btn" id="dlPublic" href="/rdp/public.rdp">Public .rdp</a>
      <a class="btn" id="dlLan" href="/rdp/lan.rdp">LAN .rdp</a>
      <a class="btn" id="dlVpn" href="/rdp/vpn.rdp">VPN .rdp</a>
    </p>
  </div>
</div>
<script>
const $ = (id) => document.getElementById(id);
let portal = { customers: [] };
function headers() {
  const h = { 'Content-Type': 'application/json' };
  const t = $('token').value.trim();
  if (t) h.Authorization = 'Bearer ' + t;
  return h;
}
function selectedId() { return $('customer').value || 'default'; }
function fillForm(c) {
  if (!c) return;
  $('name').value = c.name || '';
  $('publicIp').value = c.publicIp || '';
  $('lanIp').value = c.lanIp || '';
  $('rdpPort').value = c.rdpPort || 3389;
  $('lanRdpPort').value = c.lanRdpPort || 3389;
}
function renderSelect() {
  const cur = selectedId();
  $('customer').innerHTML = (portal.customers || []).map(c =>
    '<option value="'+c.id+'"'+(c.id===cur?' selected':'')+'>'+c.name+' ('+c.id+')</option>'
  ).join('');
  const c = (portal.customers || []).find(x => x.id === selectedId()) || (portal.customers||[])[0];
  fillForm(c);
  renderFiles();
}
function renderFiles() {
  const id = selectedId();
  const q = '?customer=' + encodeURIComponent(id);
  $('dlPublic').href = '/rdp/public.rdp' + q;
  $('dlLan').href = '/rdp/lan.rdp' + q;
  $('dlVpn').href = '/rdp/vpn.rdp' + q;
  fetch('/rdp' + q).then(r => r.json()).then(idx => {
    $('files').innerHTML = (idx.files || []).map(f =>
      '<li><a href="'+f.url+'">'+f.name+' - '+f.label+' ('+f.host+':'+f.port+')</a></li>'
    ).join('');
  }).catch(() => {});
}
function load() {
  fetch('/api/portal').then(r => r.json()).then(p => {
    portal = p;
    $('webPort').value = p.webPort || 8001;
    renderSelect();
  });
}
$('customer').addEventListener('change', () => {
  const c = (portal.customers || []).find(x => x.id === selectedId());
  fillForm(c); renderFiles();
});
$('save').addEventListener('click', async () => {
  const body = {
    webPort: parseInt($('webPort').value, 10) || 8001,
    customer: {
      id: selectedId(),
      name: $('name').value.trim() || selectedId(),
      publicIp: $('publicIp').value.trim(),
      lanIp: $('lanIp').value.trim(),
      rdpPort: parseInt($('rdpPort').value, 10),
      lanRdpPort: parseInt($('lanRdpPort').value, 10)
    }
  };
  $('status').textContent = 'Kaydediliyor...';
  try {
    const r = await fetch('/api/portal', { method: 'POST', headers: headers(), body: JSON.stringify(body) });
    const j = await r.json();
    if (!r.ok) { $('status').textContent = 'Kayit reddedildi: ' + (j.error || r.status) + '. LAN uzerinden veya token ile kaydedin.'; return; }
    portal = j;
    $('status').textContent = 'Kaydedildi. WAN RDP portu ' + body.customer.rdpPort + '. Web ' + (j.webPort || 8001) + ' (dinleme icin servis yeniden baslatilir).';
    renderSelect();
  } catch (e) { $('status').textContent = 'Hata: ' + e; }
});
$('add').addEventListener('click', () => {
  const name = prompt('Yeni musteri adi');
  if (!name) return;
  const id = name.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'') || 'musteri';
  portal.customers = portal.customers || [];
  portal.customers.push({ id: id, name: name, publicIp: $('publicIp').value, lanIp: $('lanIp').value, rdpPort: 3389, lanRdpPort: parseInt($('lanRdpPort').value,10)||3389 });
  $('customer').innerHTML += '<option value="'+id+'">'+name+'</option>';
  $('customer').value = id;
  fillForm(portal.customers[portal.customers.length-1]);
  $('status').textContent = 'Form dolduruldu. Kaydet ile kalici olur.';
});
$('token').value = sessionStorage.getItem('rdpvb_token') || '';
$('token').addEventListener('change', () => sessionStorage.setItem('rdpvb_token', $('token').value));
load();
</script>
</body></html>
'@
}

function Save-RemoteAppRdpFiles {
    [CmdletBinding()]
    param()
    $desk = [Environment]::GetFolderPath('Desktop')
    $rdpDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp'
    if (-not (Test-Path -LiteralPath $rdpDir)) { New-Item -ItemType Directory -Path $rdpDir -Force | Out-Null }
    $utf16 = New-Object System.Text.UnicodeEncoding $false, $true
    $written = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-RemoteAppDownloadItems)) {
        $text = New-RemoteAppRdpText -TargetIp $item.host -Port $item.port -Alias $item.alias -DisplayName $item.name
        foreach ($dir in @($desk, $rdpDir)) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $path = Join-Path $dir $item.fileName
            [System.IO.File]::WriteAllText($path, $text, $utf16)
            [void]$written.Add($path)
        }
    }
    return $written.ToArray()
}

function Test-ProbeApiAnonymousPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    $p = $Path.ToLowerInvariant().TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($p)) { $p = '/' }
    if ($p -eq '/' -or $p -eq '/health' -or $p -eq '/api/health' -or $p -eq '/probe/api/health') { return $true }
    if ($p -eq '/download' -or $p -eq '/rdp' -or $p -eq '/api/portal' -or $p -eq '/api/apps' -or $p -eq '/app' -or $p -eq '/dashboard' -or $p -eq '/index.html' -or $p -eq '/api/icon') { return $true }
    if ($p.StartsWith('/rdp/')) { return $true }
    if ($p.StartsWith('/assets/')) { return $true }
    return $false
}

function New-ProbeApiHttpResponse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [int]$Status = 200,
        $Body,
        [hashtable]$Headers,
        [string]$ContentType = 'application/json; charset=utf-8'
    )

    $json = if ($Body -is [string]) { $Body } else { ConvertTo-ProbeJson -InputObject $Body }
    $h = @{
        'Content-Type'  = $ContentType
        'Cache-Control' = 'no-store'
        'Access-Control-Allow-Origin'  = '*'
        'Access-Control-Allow-Headers' = 'Authorization, Content-Type'
        'Access-Control-Allow-Methods' = 'GET, POST, OPTIONS'
    }
    if ($Headers) {
        foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
    }
    return @{
        status  = $Status
        headers = $h
        body    = $json
    }
}

# ---------------------------------------------------------------------------
# IIS / HttpModule / TcpListener ortak dispatcher.
#
# Parametre $Request bir PSObject olup su alanlari icermelidir:
#   Headers   : hashtable (Authorization vs.)
#   Query     : hashtable (server vs.)
#   Method    : string
#   Path      : string  (ornek /probe/api/probe)
#
# Cikti: $Response hashtable'i { status, headers, body }
# ---------------------------------------------------------------------------
function Invoke-ProbeApiRequest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Request
    )

    $method = [string]$Request.Method
    if ([string]::IsNullOrWhiteSpace($method)) { $method = 'GET' }
    $method = $method.ToUpperInvariant()

    $path = [string]$Request.Path
    if ([string]::IsNullOrWhiteSpace($path)) {
        if ($Request.PSObject.Properties['RawUrl']) { $path = [string]$Request.RawUrl }
        elseif ($Request.PSObject.Properties['Url']) { $path = [string]$Request.Url }
        else { $path = $Script:DefaultProbePath }
    }

    $query = @{}
    if ($Request.PSObject.Properties['Query'] -and $Request.Query) {
        if ($Request.Query -is [hashtable] -or $Request.Query -is [System.Collections.IDictionary]) {
            $query = $Request.Query
        }
    }
    $qIndex = $path.IndexOf('?')
    if ($qIndex -ge 0) {
        $parsed = ConvertFrom-QueryString -RawQuery $path.Substring($qIndex)
        foreach ($k in $parsed.Keys) { $query[$k] = $parsed[$k] }
        $path = $path.Substring(0, $qIndex)
    }
    $pathNorm = $path.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($pathNorm)) { $pathNorm = '/' }

    if ($method -eq 'OPTIONS') {
        return New-ProbeApiHttpResponse -Status 204 -Body '' -Headers @{
            'Access-Control-Allow-Origin'  = '*'
            'Access-Control-Allow-Headers' = 'Authorization, Content-Type'
            'Access-Control-Allow-Methods' = 'GET, POST, OPTIONS'
        }
    }

    $lowPath = $pathNorm.ToLowerInvariant()
    $isWritePost = ($method -eq 'POST' -and ($lowPath -eq '/api/portal' -or $lowPath -eq '/api/apps' -or $lowPath -eq '/api/clients' -or $lowPath -eq '/api/totp'))
    $isBrowse = ($method -eq 'GET' -and ($lowPath -eq '/api/browse' -or $lowPath -eq '/api/file' -or $lowPath -eq '/api/totp' -or $lowPath -eq '/api/clients'))
    if ($method -ne 'GET' -and -not $isWritePost) {
        return New-ProbeApiHttpResponse -Status 405 -Body @{ error = 'method_not_allowed' } -Headers @{ 'Allow' = 'GET, POST, OPTIONS' }
    }

    $headers = $null
    $hProp = $Request.PSObject.Properties['Headers']
    if ($hProp) { $headers = $hProp.Value }
    $authHeader = Get-HeaderValue -Headers $headers -Name 'Authorization'
    $token = $null
    if ($authHeader -and $authHeader -like 'Bearer *') {
        $token = $authHeader.Substring(7).Trim()
    }

    $anon = Test-ProbeApiAnonymousPath -Path $pathNorm
    $isClientRegister = $false
    $isClientAdmin = $false
    if ($method -eq 'POST' -and $lowPath -eq '/api/clients') {
        $isClientRegister = $true
        try {
            $tmpBody = ''
            if ($Request.PSObject.Properties['Body']) { $tmpBody = [string]$Request.Body }
            $tmp = $tmpBody | ConvertFrom-Json
            $act = ''
            if ($tmp.PSObject.Properties['action']) { $act = [string]$tmp.action }
            if ($act -match 'approve|allow|deny|block' -or $tmp.PSObject.Properties['requireApproval']) {
                $isClientAdmin = $true
                $isClientRegister = $false
            }
        } catch {}
    }
    # Anonim POST /api/clients (pending kayit) LAN/Bearer istemez; approve/deny/requireApproval ister.
    $needsLanOrBearer = ($isBrowse -or $isClientAdmin -or ($isWritePost -and -not $isClientRegister))
    if ($needsLanOrBearer) {
        $remoteIp = ''
        if ($Request.PSObject.Properties['RemoteIp']) { $remoteIp = [string]$Request.RemoteIp }
        $okWrite = (Test-IsPrivateClientIp -Ip $remoteIp) -or (Test-ProbeApiToken -ProvidedToken $token)
        if (-not $okWrite) {
            return New-ProbeApiHttpResponse -Status 401 -Body @{ error = 'unauthorized'; hint = 'LAN veya Bearer token gerekli' } -Headers @{ 'WWW-Authenticate' = 'Bearer' }
        }
    } elseif ($isClientRegister) {
        # pending kayit: internetten istemci kaydolabilir
    } elseif (-not $anon) {
        if (-not (Test-ProbeApiToken -ProvidedToken $token)) {
            return New-ProbeApiHttpResponse -Status 401 -Body @{ error = 'unauthorized' } -Headers @{ 'WWW-Authenticate' = 'Bearer' }
        }
    }

    $server = $null
    if ($query -is [System.Collections.IDictionary] -and $query.Contains('server')) {
        $server = [string]$query['server']
    }
    if ([string]::IsNullOrWhiteSpace($server)) { $server = $env:COMPUTERNAME }

    switch ($pathNorm.ToLowerInvariant()) {
        '/'                     { return New-ProbeApiHttpResponse -Body (Get-ProbeCatalog) }
        '/health'               { return New-ProbeApiHttpResponse -Body (Get-ProbeHealth) }
        '/api/health'           { return New-ProbeApiHttpResponse -Body (Get-ProbeHealth) }
        '/probe/api/health'     { return New-ProbeApiHttpResponse -Body (Get-ProbeHealth) }
        '/probe/api/probe'      { return New-ProbeApiHttpResponse -Body (Invoke-ProbeApi -ServerName $server) }
        '/api/probe'            { return New-ProbeApiHttpResponse -Body (Invoke-ProbeApi -ServerName $server) }
        '/probe/api/manifest'   { return New-ProbeApiHttpResponse -Body (Get-LiveServerManifest) }
        '/api/manifest'         { return New-ProbeApiHttpResponse -Body (Get-LiveServerManifest) }
        '/probe/api/apps'       {
            $appsBody = New-Object System.Collections.Specialized.OrderedDictionary
            $appList = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @(Get-LocalRemoteAppEntries)) { [void]$appList.Add($entry) }
            $appsBody.Add('apps', $appList.ToArray())
            return New-ProbeApiHttpResponse -Body $appsBody
        }
        '/api/apps'             {
            if ($method -eq 'POST') {
                $raw = ''
                if ($Request.PSObject.Properties['Body']) { $raw = [string]$Request.Body }
                try {
                    $pub = Save-PublishedAppFromJson -JsonText $raw
                    return New-ProbeApiHttpResponse -Body $pub
                } catch {
                    return New-ProbeApiHttpResponse -Status 400 -Body @{ error = [string]$_.Exception.Message }
                }
            }
            $appsBody = New-Object System.Collections.Specialized.OrderedDictionary
            $appList = New-Object System.Collections.Generic.List[object]
            foreach ($entry in @(Get-LocalRemoteAppEntries)) { [void]$appList.Add($entry) }
            $appsBody.Add('apps', $appList.ToArray())
            return New-ProbeApiHttpResponse -Body $appsBody
        }
        '/api/browse'           {
            $bp = ''
            if ($query -is [System.Collections.IDictionary] -and $query['path']) { $bp = [string]$query['path'] }
            return New-ProbeApiHttpResponse -Body (Get-ServerBrowseListing -DirPath $bp)
        }
        '/api/file'             { return (Invoke-ExfinAccessRequest -Request $Request -Method $method -PathNorm '/api/file' -Query $query) }
        '/api/icon'             { return (Invoke-ExfinAccessRequest -Request $Request -Method $method -PathNorm '/api/icon' -Query $query) }
        '/api/totp'             { return (Invoke-ExfinAccessRequest -Request $Request -Method $method -PathNorm '/api/totp' -Query $query) }
        '/api/clients'          { return (Invoke-ExfinAccessRequest -Request $Request -Method $method -PathNorm '/api/clients' -Query $query) }
        '/probe/api/status'     { return New-ProbeApiHttpResponse -Body (Get-ProbeStatus) }
        '/api/status'           { return New-ProbeApiHttpResponse -Body (Get-ProbeStatus) }
        '/download'             {
            $dash = Get-DashboardStaticResponse -RequestPath '/download'
            if ($dash) { return $dash }
            return New-ProbeApiHttpResponse -Body (Get-RemoteAppDownloadHtml) -ContentType 'text/html; charset=utf-8'
        }
        '/app'                  {
            $dash = Get-DashboardStaticResponse -RequestPath '/app'
            if ($dash) { return $dash }
            return New-ProbeApiHttpResponse -Status 404 -Body @{ error = 'dashboard_missing' }
        }
        '/rdp'                  {
            $cid = $null
            if ($query['customer']) { $cid = [string]$query['customer'] }
            return New-ProbeApiHttpResponse -Body (Get-RemoteAppDownloadIndex -CustomerId $cid)
        }
        '/api/portal'           {
            if ($method -eq 'POST') {
                $raw = ''
                if ($Request.PSObject.Properties['Body']) { $raw = [string]$Request.Body }
                $saved = Save-CustomerPortalFromJson -JsonText $raw
                return New-ProbeApiHttpResponse -Body $saved
            }
            return New-ProbeApiHttpResponse -Body (Get-CustomerPortalConfig)
        }
        default {
            $low = $pathNorm.ToLowerInvariant()
            if ($low.StartsWith('/rdp/')) {
                $file = $pathNorm.Substring(5)
                $cid = $null
                $ovr = 0
                $clientKey = ''
                if ($query['customer']) { $cid = [string]$query['customer'] }
                if ($query['client']) { $clientKey = [string]$query['client'] }
                if ($query['rdpPort']) { [void][int]::TryParse([string]$query['rdpPort'], [ref]$ovr) }
                elseif ($query['port']) { [void][int]::TryParse([string]$query['port'], [ref]$ovr) }
                $remoteIp = ''
                if ($Request.PSObject.Properties['RemoteIp']) { $remoteIp = [string]$Request.RemoteIp }
                if (-not (Test-IsPrivateClientIp -Ip $remoteIp)) {
                    if (-not (Test-ExfinClientMayDownload -ClientId $clientKey)) {
                        return New-ProbeApiHttpResponse -Status 403 -Body @{ error = 'client_not_approved'; hint = 'Istemci kaydi sunucuda onaylanmali' }
                    }
                }
                $dl = Get-RemoteAppRdpDownload -FileName $file -CustomerId $cid -RdpPort $ovr
                if ($null -eq $dl) {
                    return New-ProbeApiHttpResponse -Status 404 -Body @{ error = 'not_found'; path = $pathNorm }
                }
                return New-ProbeApiHttpResponse -Body ([string]$dl.Content) -ContentType 'application/x-rdp' -Headers @{
                    'Content-Disposition' = ('attachment; filename="{0}"' -f $dl.FileName)
                }
            }
            $dash = Get-DashboardStaticResponse -RequestPath $pathNorm
            if ($dash) { return $dash }
            return New-ProbeApiHttpResponse -Status 404 -Body @{ error = 'not_found'; path = $pathNorm }
        }
    }
}

$script:ExfinAccessPath = Join-Path $PSScriptRoot 'ExfinAccess.ps1'
if (Test-Path -LiteralPath $script:ExfinAccessPath) {
    . $script:ExfinAccessPath
}

# ---------------------------------------------------------------------------
# Dot-source yardimcisi
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'Invoke-ProbeApi',
        'Invoke-ProbeApiRequest',
        'Test-ProbeApiToken',
        'Get-LocalServerProbeResult',
        'Get-ServerProbeResult',
        'Get-LiveServerManifest',
        'Get-ProbeHealth',
        'Get-ProbeStatus',
        'Get-ProbeCatalog',
        'Get-ProbeApiConfig',
        'Save-ProbeApiConfig',
        'New-ProbeApiToken',
        'ConvertTo-ProbeJson'
    )
}
