#requires -Version 5.1
#requires -RunAsAdministrator
# HTML5 kopma: cert CN = public IP (WASM CN kontrolu), HTTP/2 kapali, brokercert guncel
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rdweb-html5-http2.log'
$done = Join-Path $logDir 'rdweb-html5-http2.done'
function Write-FixLog([string]$m) {
    $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $m
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
    Write-Output $line
}
function Grant-MachineKeyRead {
    param([Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert, [string[]]$Accounts)
    $paths = New-Object System.Collections.Generic.List[string]
    try {
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
        if ($rsa -and $rsa.Key -and $rsa.Key.UniqueName) {
            foreach ($dir in @(
                    (Join-Path $env:ProgramData 'Microsoft\Crypto\RSA\MachineKeys'),
                    (Join-Path $env:ProgramData 'Microsoft\Crypto\Keys')
                )) {
                $p = Join-Path $dir $rsa.Key.UniqueName
                if (Test-Path -LiteralPath $p) { [void]$paths.Add($p) }
            }
        }
    } catch { }
    foreach ($file in @($paths | Select-Object -Unique)) {
        foreach ($acct in $Accounts) { cmd /c ("icacls `"$file`" /grant `"${acct}:(R)`"") | Out-Null }
    }
}

try { Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue } catch { }
Write-FixLog 'START cert CN=185.86.15.238 + HTTP/2 off'

$san = '2.5.29.17={text}DNS=185.86.15.238&DNS=ARZ&DNS=ARZ.internal&DNS=localhost&IPAddress=185.86.15.238&IPAddress=192.168.5.100&IPAddress=26.59.208.76&IPAddress=127.0.0.1'
$eku = '2.5.29.37={text}1.3.6.1.5.5.7.3.1'
$cert = New-SelfSignedCertificate -Subject 'CN=185.86.15.238' `
    -TextExtension @($eku, $san) `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -KeyLength 2048 -KeyAlgorithm RSA -KeyExportPolicy Exportable `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -NotAfter (Get-Date).AddYears(5) `
    -FriendlyName 'EXFIN-RDG-IP'
$thumb = $cert.Thumbprint.ToUpperInvariant()
Write-FixLog ('new thumb=' + $thumb)
Grant-MachineKeyRead -Cert $cert -Accounts @('NETWORK SERVICE', 'IIS_IUSRS', 'LOCAL SERVICE')
certutil -repairstore My $thumb | Out-Null

$cerFile = Join-Path $logDir 'EXFIN-RD-Gateway.cer'
Export-Certificate -Cert $cert -FilePath $cerFile -Force | Out-Null
try {
    Import-Certificate -FilePath $cerFile -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    $desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'EXFIN-RD-Gateway.cer'
    Copy-Item $cerFile $desk -Force
    Copy-Item $cerFile 'C:\ProgramData\RdpVirtualBoxApp\Config\EXFIN-RD-Gateway.cer' -Force
    Write-FixLog 'exported + trusted locally'
} catch { Write-FixLog ("WARN export: {0}" -f $_.Exception.Message) }

$bytes = New-Object byte[] ($thumb.Length / 2)
for ($i = 0; $i -lt $thumb.Length; $i += 2) { $bytes[$i / 2] = [Convert]::ToByte($thumb.Substring($i, 2), 16) }
try {
    $gw = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayServerSettings
    if ($gw) { Write-FixLog ('SetCertificate ' + $gw.SetCertificate($bytes).ReturnValue) }
} catch { Write-FixLog ("WARN gw cert: {0}" -f $_.Exception.Message) }

$guid = '{4dc3e181-e14b-4a21-b022-59fc669b0914}'
$hash = $thumb.ToLowerInvariant()
cmd /c 'netsh http delete sslcert ipport=0.0.0.0:443' | Out-Null
cmd /c 'netsh http delete sslcert ipport=[::]:443' | Out-Null
cmd /c ("netsh http add sslcert ipport=0.0.0.0:443 certhash={0} appid={1} certstorename=MY disablehttp2=enable verifyclientcertrevocation=disable" -f $hash, $guid) | Out-Null
cmd /c ("netsh http add sslcert ipport=[::]:443 certhash={0} appid={1} certstorename=MY disablehttp2=enable verifyclientcertrevocation=disable" -f $hash, $guid) | Out-Null
Write-FixLog '443 rebound HTTP/2 off'

try {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters' -Name 'EnableHttp2Tls' -Value 0 -PropertyType DWord -Force | Out-Null
} catch { }

$brokerCer = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\rd-broker.cer'
Export-Certificate -Cert $cert -FilePath $brokerCer -Type CERT -Force | Out-Null
foreach ($d in @(
        'C:\Program Files\RemoteDesktopWeb\Config',
        'C:\Program Files\RemoteDesktopWeb\Internal\Config',
        'C:\ProgramData\RdpVirtualBoxApp\RdWebClient\content\Config',
        'C:\Windows\Web\RDWeb\webclient\config'
    )) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item $brokerCer (Join-Path $d 'brokercert.cer') -Force
    Write-FixLog ('brokercert ' + $d)
}

$rdpPath = 'C:\Windows\Web\RDWeb\Pages\exfin\Tiger3Ent.rdp'
$rdpLines = @(
    'full address:s:ARZ'
    'server port:i:3389'
    'username:s:ARZ\EXFIN1'
    'prompt for credentials:i:1'
    'promptcredentialonce:i:1'
    'authentication level:i:0'
    'enablecredsspsupport:i:1'
    'remoteapplicationmode:i:1'
    'remoteapplicationprogram:s:||Tiger3Ent'
    'remoteapplicationname:s:Tiger3 Enterprise'
    'disableremoteappcapscheck:i:1'
    'alternate shell:s:rdpinit.exe'
    'redirectclipboard:i:1'
    'enableudptransport:i:0'
    'gatewayhostname:s:185.86.15.238'
    'gatewayusagemethod:i:1'
    'gatewayprofileusagemethod:i:1'
    'gatewaycredentialssource:i:0'
)
$utf16 = New-Object System.Text.UnicodeEncoding $false, $true
$rdpText = ($rdpLines -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllBytes($rdpPath, $utf16.GetPreamble() + $utf16.GetBytes($rdpText))
$feedPath = 'C:\Windows\Web\RDWeb\Pages\App_Data\exfin-webfeed.xml'
if (Test-Path $feedPath) {
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($rdpPath))
    $xml = [regex]::Replace([System.IO.File]::ReadAllText($feedPath), '<Content>[^<]*</Content>', '<Content>' + $b64 + '</Content>')
    [System.IO.File]::WriteAllText($feedPath, $xml, [System.Text.UTF8Encoding]::new($false))
}

Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
Restart-Service TSGateway -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
Write-FixLog ('THUMBPRINT=' + $thumb)
'ok' | Set-Content $done -Encoding ASCII
Write-FixLog 'DONE'
exit 0
