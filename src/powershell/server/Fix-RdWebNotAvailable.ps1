#requires -Version 5.1
#requires -RunAsAdministrator
# HTML5 "Not available": UTF-8 RDP feed, .cer MIME, masaustu kaynagi, launch in browser
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rdweb-available.log'
$done = Join-Path $logDir 'rdweb-available.done'
function Write-FixLog([string]$m) {
    $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $m
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch {}
    Write-Output $line
}
try { Remove-Item $done -Force -ErrorAction SilentlyContinue } catch {}
Write-FixLog 'START'

$exfin = 'C:\Windows\Web\RDWeb\Pages\exfin'
$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-RdpFile([string]$Path, [string[]]$Lines) {
    $text = ($Lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $text, $utf8)
}

$gw = '185.86.15.238'
$common = @(
    'full address:s:ARZ'
    'server port:i:3389'
    'username:s:ARZ\EXFIN1'
    'prompt for credentials:i:1'
    'promptcredentialonce:i:1'
    'authentication level:i:0'
    'enablecredsspsupport:i:1'
    'negotiate security layer:i:1'
    'redirectclipboard:i:1'
    'enableudptransport:i:0'
    "gatewayhostname:s:$gw"
    'gatewayusagemethod:i:1'
    'gatewayprofileusagemethod:i:1'
    'gatewaycredentialssource:i:0'
    'autoreconnection enabled:i:1'
)
$appLines = $common + @(
    'remoteapplicationmode:i:1'
    'remoteapplicationprogram:s:||Tiger3Ent'
    'remoteapplicationname:s:Tiger3 Enterprise'
    'disableremoteappcapscheck:i:1'
    'alternate shell:s:rdpinit.exe'
)
$deskLines = $common + @(
    'remoteapplicationmode:i:0'
    'screen mode id:i:2'
    'session bpp:i:32'
    'compression:i:1'
)
Write-RdpFile (Join-Path $exfin 'Tiger3Ent.rdp') $appLines
Write-RdpFile (Join-Path $exfin 'Desktop.rdp') $deskLines
$appB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $exfin 'Tiger3Ent.rdp')))
$deskB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $exfin 'Desktop.rdp')))
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$feed = @"
<ResourceCollection PubDate="$now" SchemaVersion="1.1" xmlns="http://schemas.microsoft.com/ts/2007/05/tswf">
  <Publisher LastUpdated="$now" Name="EXFIN RemoteAPP" ID="ARZ" Description="EXFIN RemoteAPP">
    <Resources>
      <Resource ID="Tiger3Ent" Alias="Tiger3Ent" Title="Tiger3 Enterprise" Type="RemoteApp" ShowByDefault="true">
        <Icons>
          <IconRaw FileType="Png" FileURL="/RDWeb/Pages/exfin/Tiger3Ent.png" />
          <Icon32 Dimensions="32x32" FileType="Png" FileURL="/RDWeb/Pages/exfin/Tiger3Ent.png" />
        </Icons>
        <HostingTerminalServers>
          <HostingTerminalServer>
            <ResourceFile FileExtension=".rdp" URL="/RDWeb/Pages/exfin/Tiger3Ent.rdp"><Content>$appB64</Content></ResourceFile>
            <TerminalServerRef Ref="ARZ" />
          </HostingTerminalServer>
        </HostingTerminalServers>
      </Resource>
      <Resource ID="ARZDesktop" Alias="ARZDesktop" Title="ARZ Masaustu" Type="Desktop" ShowByDefault="true">
        <HostingTerminalServers>
          <HostingTerminalServer>
            <ResourceFile FileExtension=".rdp" URL="/RDWeb/Pages/exfin/Desktop.rdp"><Content>$deskB64</Content></ResourceFile>
            <TerminalServerRef Ref="ARZ" />
          </HostingTerminalServer>
        </HostingTerminalServers>
      </Resource>
    </Resources>
    <TerminalServers>
      <TerminalServer ID="ARZ" Name="ARZ" LastUpdated="$now" />
    </TerminalServers>
  </Publisher>
</ResourceCollection>
"@
[System.IO.File]::WriteAllText('C:\Windows\Web\RDWeb\Pages\App_Data\exfin-webfeed.xml', $feed, $utf8)
Write-FixLog 'UTF-8 feed + desktop resource'

$wc = 'C:\ProgramData\RdpVirtualBoxApp\RdWebClient\content\web.config'
if (Test-Path $wc) {
    [xml]$x = Get-Content -LiteralPath $wc -Encoding UTF8
    $sc = $x.SelectSingleNode('/configuration/system.webServer/staticContent')
    if ($sc) {
        foreach ($n in @($sc.SelectNodes("mimeMap[@fileExtension='.cer']"))) { [void]$sc.RemoveChild($n) }
        foreach ($n in @($sc.SelectNodes("remove[@fileExtension='.cer']"))) { [void]$sc.RemoveChild($n) }
        $rm = $x.CreateElement('remove'); [void]$rm.SetAttribute('fileExtension', '.cer'); [void]$sc.PrependChild($rm)
        $add = $x.CreateElement('mimeMap')
        [void]$add.SetAttribute('fileExtension', '.cer')
        [void]$add.SetAttribute('mimeType', 'application/pkix-cert')
        [void]$sc.AppendChild($add)
        $x.Save($wc)
        Write-FixLog 'web.config .cer mime fixed'
    }
}

$ds = @'
var DeploymentSettings={deploymentType:"rdWeb",launchResourceInBrowser:true,suppressTelemetry:true};
'@
foreach ($p in @(
        'C:\ProgramData\RdpVirtualBoxApp\RdWebClient\content\Config\deploymentsettings.js',
        'C:\Program Files\RemoteDesktopWeb\Internal\Config\deploymentSettings.js',
        'C:\Program Files\RemoteDesktopWeb\Config\deploymentSettings.js',
        'C:\Windows\Web\RDWeb\webclient\Config\deploymentsettings.js'
    )) {
    try {
        $d = Split-Path $p
        if (Test-Path $d) { [System.IO.File]::WriteAllText($p, $ds, $utf8); Write-FixLog "ds $p" }
    } catch { }
}

try { iisreset /noforce | Out-Null } catch { }
Start-Sleep -Seconds 3
$ct = & curl.exe -k --http1.1 -sS -D - -o NUL --max-time 12 'https://ARZ/RDWeb/webclient/config/brokercert.cer' 2>$null
Write-FixLog ($ct | Select-String 'Content-Type' | Out-String)
'ok' | Set-Content $done -Encoding ASCII
Write-FixLog 'DONE'
exit 0
