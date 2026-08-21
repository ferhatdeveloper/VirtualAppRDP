#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workgroup'ta bos RD Connection Broker feed'ini atlar.
    HTML5 (/RDWeb/webclient) ve klasik Pages ayni TSWF XML'i kullanir.
#>
[CmdletBinding()]
param(
    [string]$Alias = 'Tiger3Ent',
    [string]$DisplayName = 'Tiger3 Enterprise',
    [string]$ExePath = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe',
    [string]$SessionHost = 'ARZ',
    [int]$RdpPort = 3389,
    [string]$GatewayHost = '185.86.15.238',
    [string]$UserName = 'ARZ\EXFIN1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ConfirmPreference = 'None'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rdweb-static-feed.log'
$done = Join-Path $logDir 'rdweb-static-feed.done'
function Write-FeedLog([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
    Write-Output $line
}
try { Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue } catch { }
Write-FeedLog 'START static RD Web feed'

$pagesRoot = 'C:\Windows\Web\RDWeb\Pages'
$exfinDir = Join-Path $pagesRoot 'exfin'
$appData = Join-Path $pagesRoot 'App_Data'
New-Item -ItemType Directory -Force -Path $exfinDir, $appData | Out-Null

$rdpLines = @(
    "full address:s:$SessionHost"
    "server port:i:$RdpPort"
    "username:s:$UserName"
    'prompt for credentials:i:1'
    'promptcredentialonce:i:1'
    'authentication level:i:0'
    'enablecredsspsupport:i:1'
    'negotiate security layer:i:1'
    'remoteapplicationmode:i:1'
    "remoteapplicationprogram:s:||$Alias"
    "remoteapplicationname:s:$DisplayName"
    'disableremoteappcapscheck:i:1'
    'alternate shell:s:rdpinit.exe'
    'screen mode id:i:2'
    'use multimon:i:0'
    'audiomode:i:0'
    'redirectclipboard:i:1'
    'redirectprinters:i:0'
    'autoreconnection enabled:i:1'
    "gatewayhostname:s:$GatewayHost"
    'gatewayusagemethod:i:1'
    'gatewayprofileusagemethod:i:1'
    'gatewaycredentialssource:i:0'
)
$rdpText = ($rdpLines -join "`r`n") + "`r`n"
$rdpPath = Join-Path $exfinDir "$Alias.rdp"
$utf16 = New-Object System.Text.UnicodeEncoding $false, $true
[System.IO.File]::WriteAllBytes($rdpPath, $utf16.GetPreamble() + $utf16.GetBytes($rdpText))
$rdpB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($rdpPath))
Write-FeedLog ("Wrote $rdpPath bytes=" + (Get-Item $rdpPath).Length)

$iconUrl = ''
$pngPath = Join-Path $exfinDir "$Alias.png"
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    if (Test-Path -LiteralPath $ExePath) {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($ExePath)
        $bmp = $ico.ToBitmap()
        $thumb = New-Object System.Drawing.Bitmap 32, 32
        $g = [System.Drawing.Graphics]::FromImage($thumb)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($bmp, 0, 0, 32, 32)
        $thumb.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $thumb.Dispose(); $bmp.Dispose(); $ico.Dispose()
        $iconUrl = "/RDWeb/Pages/exfin/$Alias.png"
        Write-FeedLog "Wrote icon $pngPath"
    }
} catch {
    Write-FeedLog ("WARN icon: {0}" -f $_.Exception.Message)
}

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$rdpUrl = "/RDWeb/Pages/exfin/$Alias.rdp"
$iconsXml = ''
if ($iconUrl) {
    $iconsXml = @"
        <Icons>
          <IconRaw FileType="Png" FileURL="$iconUrl" />
          <Icon32 Dimensions="32x32" FileType="Png" FileURL="$iconUrl" />
        </Icons>
"@
}

$feed = @"
<ResourceCollection PubDate="$now" SchemaVersion="2.1" xmlns="http://schemas.microsoft.com/ts/2007/05/tswf">
  <Publisher LastUpdated="$now" Name="EXFIN RemoteAPP" ID="$SessionHost" Description="EXFIN RemoteAPP">
    <Resources>
      <Resource ID="$Alias" Alias="$Alias" Title="$DisplayName" Type="RemoteApp" ShowByDefault="true" ExecutableName="Tiger3Enterprise.exe">
$iconsXml
        <HostingTerminalServers>
          <HostingTerminalServer>
            <ResourceFile FileExtension=".rdp" URL="$rdpUrl">
              <Content>$rdpB64</Content>
            </ResourceFile>
            <TerminalServerRef Ref="$SessionHost" />
          </HostingTerminalServer>
        </HostingTerminalServers>
      </Resource>
    </Resources>
    <TerminalServers>
      <TerminalServer ID="$SessionHost" Name="$SessionHost" LastUpdated="$now" />
    </TerminalServers>
  </Publisher>
</ResourceCollection>
"@
$feedPath = Join-Path $appData 'exfin-webfeed.xml'
[System.IO.File]::WriteAllText($feedPath, $feed, [System.Text.UTF8Encoding]::new($false))
Write-FeedLog "Wrote $feedPath"

$exfinWebConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.web>
    <authorization>
      <allow users="*" />
    </authorization>
  </system.web>
  <system.webServer>
    <handlers>
      <clear />
      <add name="StaticFile" path="*" verb="*" modules="StaticFileModule" resourceType="Either" requireAccess="Read" />
    </handlers>
    <staticContent>
      <remove fileExtension=".rdp" />
      <mimeMap fileExtension=".rdp" mimeType="application/x-rdp" />
      <remove fileExtension=".png" />
      <mimeMap fileExtension=".png" mimeType="image/png" />
    </staticContent>
  </system.webServer>
</configuration>
'@
[System.IO.File]::WriteAllText((Join-Path $exfinDir 'web.config'), $exfinWebConfig, [System.Text.UTF8Encoding]::new($false))

$webFeedAspx = @'
<%@ Page Language="C#" %>
<script runat="server">
void Page_Load(object sender, EventArgs e)
{
    if (Request.PathInfo != null && Request.PathInfo.Length != 0)
    {
        Response.StatusCode = 404;
        Response.End();
        return;
    }
    string path = Server.MapPath("App_Data/exfin-webfeed.xml");
    Response.Clear();
    Response.ContentType = "text/xml; charset=utf-8";
    Response.ContentEncoding = System.Text.Encoding.UTF8;
    Response.Cache.SetCacheability(HttpCacheability.NoCache);
    Response.WriteFile(path);
    Response.End();
}
</script>
'@
$webFeedPath = Join-Path $pagesRoot 'WebFeed.aspx'
if (Test-Path -LiteralPath $webFeedPath) {
    Copy-Item -LiteralPath $webFeedPath -Destination ($webFeedPath + '.exfin.bak') -Force -ErrorAction SilentlyContinue
}
[System.IO.File]::WriteAllText($webFeedPath, $webFeedAspx, [System.Text.UTF8Encoding]::new($false))
Write-FeedLog 'Wrote Pages/WebFeed.aspx'

$pagesCfg = Join-Path $pagesRoot 'web.config'
$pbak = $pagesCfg + '.exfin.handler.bak'
if (-not (Test-Path -LiteralPath $pbak)) { Copy-Item -LiteralPath $pagesCfg -Destination $pbak -Force }
[xml]$pXml = Get-Content -LiteralPath $pagesCfg -Encoding UTF8
$handlers = $pXml.SelectSingleNode('/configuration/system.webServer/handlers')
if ($null -ne $handlers) {
    $existing = @($handlers.SelectNodes("add[@name='PagesWebFeedHandler']"))
    foreach ($n in $existing) { [void]$handlers.RemoveChild($n) }
    $rm = $pXml.CreateElement('remove')
    [void]$rm.SetAttribute('name', 'PagesWebFeedHandler')
    [void]$handlers.PrependChild($rm)
}
$pXml.Save($pagesCfg)
Write-FeedLog 'Removed PagesWebFeedHandler'

# Inject feed into classic/HTML5 Default.aspx AppFeed
$defPath = Join-Path $pagesRoot 'en-US\Default.aspx'
if (Test-Path -LiteralPath $defPath) {
    $dbak = $defPath + '.exfin.bak'
    if (-not (Test-Path -LiteralPath $dbak)) { Copy-Item -LiteralPath $defPath -Destination $dbak -Force }
    $def = [System.IO.File]::ReadAllText($defPath)
    $needle = '            strAppFeed = retValues.Item1;'
    $inject = @'
            strAppFeed = retValues.Item1;
            if (String.IsNullOrEmpty(strAppFeed) || strAppFeed.IndexOf("<Resource", StringComparison.OrdinalIgnoreCase) < 0)
            {
                string exfinFeedPath = Server.MapPath("../App_Data/exfin-webfeed.xml");
                if (System.IO.File.Exists(exfinFeedPath))
                {
                    strAppFeed = System.IO.File.ReadAllText(exfinFeedPath);
                    strWorkspaceName = "EXFIN RemoteAPP";
                }
            }
'@
    if ($def.Contains('exfin-webfeed.xml')) {
        Write-FeedLog 'Default.aspx already patched'
    } elseif ($def.Contains($needle)) {
        $def2 = $def.Replace($needle, $inject)
        [System.IO.File]::WriteAllText($defPath, $def2, [System.Text.UTF8Encoding]::new($true))
        Write-FeedLog 'Patched en-US/Default.aspx AppFeed fallback'
    } else {
        Write-FeedLog 'WARN Default.aspx needle not found'
    }
}

try {
    icacls $exfinDir /grant 'IIS_IUSRS:(OI)(CI)R' /T | Out-Null
    icacls $feedPath /grant 'IIS_IUSRS:R' | Out-Null
} catch { }

try { iisreset /noforce | Out-Null } catch { Write-FeedLog ("WARN iisreset: {0}" -f $_.Exception.Message) }
Start-Sleep -Seconds 4

# Anonymous feed check (may 302 to login — still proves handler is gone)
try {
    $out = Join-Path $env:TEMP 'exfin-webfeed-http.xml'
    & curl.exe -k --http1.1 -sS -D - "https://ARZ/RDWeb/Pages/WebFeed.aspx" --max-time 20 -o $out | Select-Object -First 16 | ForEach-Object { Write-FeedLog $_ }
    if (Test-Path $out) {
        $body = Get-Content $out -Raw -ErrorAction SilentlyContinue
        if ($body -match 'Tiger3Ent') { Write-FeedLog 'VERIFY WebFeed contains Tiger3Ent' }
        else { Write-FeedLog ('VERIFY WebFeed len=' + $body.Length + ' preview=' + $body.Substring(0, [Math]::Min(180, $body.Length))) }
    }
} catch {
    Write-FeedLog ("WARN curl: {0}" -f $_.Exception.Message)
}

'ok' | Set-Content -LiteralPath $done -Encoding ASCII
Write-FeedLog 'DONE'
exit 0
