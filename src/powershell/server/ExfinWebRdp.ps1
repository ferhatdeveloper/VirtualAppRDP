#requires -Version 5.1
# EXFIN RemoteAPP â€” Web RDP / RD Gateway durum ve genel kullanici portali.

function Get-ExfinCustText {
    param($Customer, [string]$Key)
    if ($null -eq $Customer -or [string]::IsNullOrWhiteSpace($Key)) { return '' }
    try {
        if ($Customer -is [System.Collections.IDictionary] -and $Customer.Contains($Key)) {
            return [string]$Customer[$Key]
        }
    } catch { }
    try {
        $prop = $Customer.PSObject.Properties[$Key]
        if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
    } catch { }
    return ''
}

function Test-ExfinTcpListen {
    param([int]$Port)
    if ($Port -lt 1) { return $false }
    try {
        $c = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        return ($c.Count -gt 0)
    } catch {
        return $false
    }
}

function Get-WebRdpStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$CustomerId)

    $entry = Get-CustomerPortalEntry -CustomerId $CustomerId
    $cust = $entry.Customer
    $publicIp = Get-ExfinCustText $cust 'publicIp'
    $lanIp = Get-ExfinCustText $cust 'lanIp'
    $vpnIp = Get-ExfinCustText $cust 'vpnIp'
    $connectMode = Get-ExfinCustText $cust 'connectMode'
    if ([string]::IsNullOrWhiteSpace($connectMode)) { $connectMode = 'direct' }
    $gwHost = Get-ExfinCustText $cust 'gatewayHost'
    if ([string]::IsNullOrWhiteSpace($gwHost)) { $gwHost = $publicIp }
    $gwPort = 443
    [void][int]::TryParse((Get-ExfinCustText $cust 'gatewayPort'), [ref]$gwPort)
    if ($gwPort -lt 1) { $gwPort = 443 }
    $webKind = Get-ExfinCustText $cust 'webKind'
    if ([string]::IsNullOrWhiteSpace($webKind)) { $webKind = 'auto' }
    $webUrl = Get-ExfinCustText $cust 'webUrl'

    $rdWebPages = Test-Path -LiteralPath 'C:\Windows\Web\RDWeb\Pages'
    $rdWebHtml5 = Test-Path -LiteralPath 'C:\Windows\Web\RDWeb\webclient'
    $guac = Test-ExfinTcpListen -Port 8443
    $gwSvc = $false
    try { $gwSvc = ((Get-Service -Name 'TSGateway' -ErrorAction SilentlyContinue).Status -eq 'Running') } catch {}
    $https443 = Test-ExfinTcpListen -Port 443

    $rdWebLan = $null
    $rdWebPublic = $null
    if ($rdWebPages) {
        if ($lanIp) { $rdWebLan = "http://$lanIp/RDWeb/Pages/en-US/Default.aspx" }
        if ($publicIp) { $rdWebPublic = "https://${publicIp}/RDWeb/Pages/en-US/Default.aspx" }
        if ($rdWebHtml5) {
            if ($lanIp) { $rdWebLan = "https://$lanIp/RDWeb/webclient/" }
            if ($publicIp) { $rdWebPublic = "https://${publicIp}/RDWeb/webclient/" }
        }
    }
    $guacLan = $null
    $guacPublic = $null
    if ($guac) {
        if ($lanIp) { $guacLan = "https://${lanIp}:8443/guacamole/" }
        if ($publicIp) { $guacPublic = "https://${publicIp}:8443/guacamole/" }
    }

    $resolvedKind = $webKind
    $launchLan = $webUrl
    $launchPublic = $webUrl
    if ($webKind -eq 'auto' -or [string]::IsNullOrWhiteSpace($webKind)) {
        if ($guac) { $resolvedKind = 'guacamole' }
        elseif ($rdWebHtml5) { $resolvedKind = 'rdweb-html5' }
        elseif ($rdWebPages) { $resolvedKind = 'rdweb' }
        else { $resolvedKind = 'none' }
    }
    if ($resolvedKind -eq 'guacamole') {
        if (-not $launchLan) { $launchLan = $guacLan }
        if (-not $launchPublic) { $launchPublic = $guacPublic }
    } elseif ($resolvedKind -eq 'rdweb-html5') {
        if (-not $launchLan) { $launchLan = $rdWebLan }
        if (-not $launchPublic) { $launchPublic = $rdWebPublic }
    } elseif ($resolvedKind -eq 'rdweb') {
        if (-not $launchLan) { $launchLan = $rdWebLan }
        if ($webKind -eq 'rdweb' -and -not $launchPublic) { $launchPublic = $rdWebPublic }
    }

    $hint = 'Direct: WAN RDP portu (NAT). Gateway: TCP 443. Web: tarayici HTML5 (RD Web Client veya Guacamole).'
    if ($resolvedKind -eq 'none') {
        $hint = 'HTML5 Web RDP yok: RDWeb/webclient klasoru yok ve Guacamole 8443 kapali. Klasik RD Web veya Gateway .rdp kullanin; HTML5 icin Guacamole (8443) veya Install-RDWebClientPackage gerekir.'
    } elseif ($resolvedKind -eq 'rdweb' -and -not $rdWebHtml5) {
        $hint = 'Klasik RD Web (Default.aspx) var; tarayici HTML5 (webclient) yok. Modern tarayicida tam RemoteApp icin Guacamole veya RD Web Client paketini kurun.'
    }

    return [ordered]@{
        connectMode     = $connectMode.ToLowerInvariant()
        gatewayHost     = $gwHost
        gatewayPort     = $gwPort
        gatewayRunning  = $gwSvc
        https443        = $https443
        webKind         = $webKind
        resolvedKind    = $resolvedKind
        webUrl          = $webUrl
        launchLan       = $launchLan
        launchPublic    = $launchPublic
        rdWebInstalled  = $rdWebPages
        rdWebHtml5      = $rdWebHtml5
        guacamole       = $guac
        rdWebLan        = $rdWebLan
        rdWebPublic     = $rdWebPublic
        guacamoleLan    = $guacLan
        guacamolePublic = $guacPublic
        publicIp        = $publicIp
        lanIp           = $lanIp
        vpnIp           = $vpnIp
        hint            = $hint
        portalWeb       = '/web'
    }
}

function Test-ExfinPortalClientIsWan {
    param($Request, [string]$PublicIp)
    $hostOnly = ''
    try {
        if ($Request -and $Request.PSObject.Properties['Headers']) {
            $h = Get-HeaderValue -Headers $Request.Headers -Name 'Host'
            if (-not $h) { $h = Get-HeaderValue -Headers $Request.Headers -Name 'X-Forwarded-Host' }
            if ($h) { $hostOnly = (($h -split ',')[0].Trim() -split ':')[0].Trim() }
        }
    } catch { }
    if ($PublicIp -and $hostOnly -and ([string]::Equals($hostOnly, $PublicIp, [StringComparison]::OrdinalIgnoreCase))) {
        return $true
    }
    $rip = ''
    if ($Request -and $Request.PSObject.Properties['RemoteIp']) { $rip = [string]$Request.RemoteIp }
    if ($rip -and -not (Test-IsPrivateClientIp -Ip $rip)) { return $true }
    return $false
}

function Get-ExfinGatewayCerPem {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $files = @(
        'C:\ProgramData\RdpVirtualBoxApp\Config\EXFIN-RD-Gateway.cer'
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'EXFIN-RD-Gateway.cer')
    )
    foreach ($f in $files) {
        if ($f -and (Test-Path -LiteralPath $f)) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($f)
                if ($bytes.Length -lt 32) { continue }
                $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
                if ($ascii.Contains('BEGIN CERTIFICATE')) { return $ascii }
                $b64 = [Convert]::ToBase64String($bytes, [System.Base64FormattingOptions]::InsertLineBreaks)
                return ('-----BEGIN CERTIFICATE-----' + [Environment]::NewLine + $b64 + [Environment]::NewLine + '-----END CERTIFICATE-----' + [Environment]::NewLine)
            } catch { }
        }
    }
    $thumb = 'A829CE7E757BACD74F6EDF152814999F782A950B'
    try {
        $c = Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
        if ($c) {
            $raw = $c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            $b64 = [Convert]::ToBase64String($raw, [System.Base64FormattingOptions]::InsertLineBreaks)
            return ('-----BEGIN CERTIFICATE-----' + [Environment]::NewLine + $b64 + [Environment]::NewLine + '-----END CERTIFICATE-----' + [Environment]::NewLine)
        }
    } catch { }
    return $null
}

function Get-WebRdpLaunchHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$CustomerId, [string]$Alias, $Request)
    $st = Get-WebRdpStatus -CustomerId $CustomerId
    $cid = $CustomerId
    if ([string]::IsNullOrWhiteSpace($cid)) { $cid = 'default' }
    $q = 'customer=' + [Uri]::EscapeDataString($cid)
    $apps = @()
    try { $apps = @(Get-LocalRemoteAppEntries) } catch { $apps = @() }
    if ($apps.Count -eq 0) {
        $apps = @([ordered]@{ alias = 'Tiger3Ent'; name = 'Tiger3 Enterprise' })
    }
    $opt = New-Object System.Text.StringBuilder
    foreach ($a in $apps) {
        $al = [string]$a.alias; if (-not $al) { $al = [string]$a['alias'] }
        $nm = [string]$a.name; if (-not $nm) { $nm = [string]$a['name'] }
        if ([string]::IsNullOrWhiteSpace($al)) { continue }
        $sel = ''
        if ($Alias -and ($al -eq $Alias)) { $sel = ' selected' }
        [void]$opt.AppendFormat('<option value="{0}"{2}>{1}</option>', [System.Net.WebUtility]::HtmlEncode($al), [System.Net.WebUtility]::HtmlEncode($(if ($nm) { $nm } else { $al })), $sel)
    }
    $isWan = Test-ExfinPortalClientIsWan -Request $Request -PublicIp ([string]$st.publicIp)
    $webPub = [string]$st.launchPublic
    $webLan = [string]$st.launchLan
    if ($isWan) { $webLan = '' }
    $ariaDis = 'true'
    $webHref = '#'
    if ($webPub) { $ariaDis = 'false'; $webHref = [System.Net.WebUtility]::HtmlEncode($webPub) }
    elseif (-not $isWan -and $webLan) { $ariaDis = 'false'; $webHref = [System.Net.WebUtility]::HtmlEncode($webLan) }
    $htmlKind = [string]$st.resolvedKind
    $hint = [string]$st.hint
    if ($isWan) {
        $hint = 'Dis agdan acildi; LAN IP kullanilmaz. Gateway .rdp (TCP 443) veya Direct Public .rdp indirin. Tarayicida HTML5 yoksa Web butonu kapali kalir.'
    }
    $hint = [System.Net.WebUtility]::HtmlEncode($hint)
    $gwHost = [System.Net.WebUtility]::HtmlEncode([string]$st.gatewayHost)
    $gwPort = [int]$st.gatewayPort
    $firstAlias = 'Tiger3Ent'
    try {
        $fa = [string]$apps[0].alias
        if (-not $fa) { $fa = [string]$apps[0]['alias'] }
        if ($fa) { $firstAlias = $fa }
    } catch {}
    if ($Alias) { $firstAlias = $Alias }
    $escAlias = [Uri]::EscapeDataString($firstAlias)
    $wanPill = ''
    if ($isWan) { $wanPill = '<span class="pill">Ag: WAN (public)</span>' } else { $wanPill = '<span class="pill">Ag: LAN</span>' }

    return @"
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EXFIN RemoteAPP - Web giris</title>
<style>
body{font-family:Segoe UI,system-ui,sans-serif;margin:0;background:#0b1220;color:#e8eef8}
.wrap{max-width:720px;margin:28px auto;padding:0 16px}
.card{background:#121a2b;border:1px solid #243049;border-radius:14px;padding:22px;margin-bottom:14px}
h1{margin:0 0 6px;font-size:22px}
.muted{color:#93a0b8;font-size:14px;line-height:1.45}
label{display:block;margin:12px 0 4px;color:#93a0b8;font-size:13px}
select,input{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #243049;background:#0b1220;color:#e8eef8}
.row{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
a.btn,button{display:inline-block;padding:10px 14px;border-radius:8px;border:0;background:#3b9eff;color:#0b1220;font-weight:700;text-decoration:none;cursor:pointer}
a.btn.sec,button.sec{background:#172033;color:#e8eef8}
a.btn[aria-disabled="true"]{opacity:.45;pointer-events:none}
.pill{display:inline-block;padding:3px 8px;border-radius:999px;background:#172033;color:#93a0b8;font-size:12px;margin-right:6px}
.ok{color:#34d399}.warn{color:#fbbf24}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <h1>EXFIN RemoteAPP</h1>
    <p class="muted">Tarayicidan giris veya .rdp indirme. Windows kullanici adi / parola RDP veya RD Web ekraninda sorulur.</p>
    <p>
      <span class="pill">Mod: $htmlKind</span>
      <span class="pill">Gateway: ${gwHost}:$gwPort</span>
      $wanPill
    </p>
    <label>Uygulama</label>
    <select id="app">$opt</select>
    <div class="row">
      <a class="btn" id="btnGw" href="/rdp/$escAlias-gateway.rdp?$q">Gateway .rdp (443)</a>
      <a class="btn sec" id="btnPub" href="/rdp/$escAlias-public.rdp?$q">Direct Public .rdp</a>
      <a class="btn sec" id="btnWeb" href="$webHref" target="_blank" rel="noopener" aria-disabled="$ariaDis">Web ile ac (tarayici)</a>
      <a class="btn sec" href="/gateway.cer">Gateway sertifikasi (.cer)</a>
    </div>
    <p class="muted" style="margin-top:14px">$hint</p>
    <p class="muted">Gateway .rdp: sertifikayi <b>Guvenilen Kok</b>e kurun. HTML5 web: IP ile acmayin. Istemcide hosts satiri <code>185.86.15.238 ARZ</code> ekleyip <a href="https://ARZ/RDWeb/webclient/" style="color:#3b9eff">https://ARZ/RDWeb/webclient/</a> kullanin.</p>
  </div>
  <div class="card">
    <p class="muted">Disaridan Gateway icin modemde <b>TCP 443</b> bu sunucuya yonlensin. Direct Public icin WAN RDP portu (ornegin 55812) gerekir. Yonetim paneli: <a href="/download" style="color:#3b9eff">/download</a></p>
  </div>
</div>
<script>
const q = '$q';
const webPub = $(if ($webPub) { "'" + ($webPub -replace "'","\\'") + "'" } else { 'null' });
const webLan = $(if ($webLan) { "'" + ($webLan -replace "'","\\'") + "'" } else { 'null' });
const sel = document.getElementById('app');
function sync() {
  const a = encodeURIComponent(sel.value || 'app');
  document.getElementById('btnGw').href = '/rdp/' + a.toLowerCase() + '-gateway.rdp?' + q;
  document.getElementById('btnPub').href = '/rdp/' + a.toLowerCase() + '-public.rdp?' + q;
  const web = document.getElementById('btnWeb');
  const href = webPub || webLan;
  if (href) { web.href = href; web.setAttribute('aria-disabled','false'); }
  else { web.href = '#'; web.setAttribute('aria-disabled','true'); }
}
sel.addEventListener('change', sync);
sync();
</script>
</body>
</html>
"@
}
