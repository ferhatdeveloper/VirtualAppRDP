#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    HTML5 RD Web Client "connection lost" duzeltmesi.
    Neden: wss://185.86.15.238/remoteDesktopGateway  (HTTPERR Request_Cancelled)
    Sertifika sadece CN=ARZ; IP ile NTLM/WebSocket kopuyor.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ConfirmPreference = 'None'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rdweb-html5-connect.log'
$done = Join-Path $logDir 'rdweb-html5-connect.done'
function Write-FixLog([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
    Write-Output $line
}
try { Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue } catch { }
Write-FixLog 'START HTML5 gateway connect fix'

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
    try {
        if ($Cert.PrivateKey -and $Cert.PrivateKey.CspKeyContainerInfo) {
            $n = $Cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
            $p = Join-Path $env:ProgramData "Microsoft\Crypto\RSA\MachineKeys\$n"
            if (Test-Path -LiteralPath $p) { [void]$paths.Add($p) }
        }
    } catch { }
    foreach ($file in @($paths | Select-Object -Unique)) {
        foreach ($acct in $Accounts) {
            cmd /c ("icacls `"$file`" /grant `"${acct}:(R)`"") | Out-Null
        }
        Write-FixLog ('acl=' + $file)
    }
}

# NTLM channel binding + self-signed often cancels HTML5 gateway auth
try {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'SuppressExtendedProtection' -Value 2 -PropertyType DWord -Force | Out-Null
    Write-FixLog 'LSA SuppressExtendedProtection=2'
} catch {
    Write-FixLog ("WARN LSA: {0}" -f $_.Exception.Message)
}

$dns = @('ARZ', 'ARZ.internal', 'localhost')
$ips = @('127.0.0.1', '192.168.5.100', '185.86.15.238', '26.59.208.76')
$sanParts = New-Object System.Collections.Generic.List[string]
foreach ($d in $dns) { [void]$sanParts.Add('DNS=' + $d) }
foreach ($i in $ips) { [void]$sanParts.Add('IPAddress=' + $i) }
$san = '2.5.29.17={text}' + ($sanParts -join '&')
$eku = '2.5.29.37={text}1.3.6.1.5.5.7.3.1'
Write-FixLog ("SAN " + $san)

$cert = New-SelfSignedCertificate -Subject 'CN=ARZ' `
    -TextExtension @($eku, $san) `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -KeyLength 2048 -KeyAlgorithm RSA `
    -KeyExportPolicy Exportable `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -NotAfter (Get-Date).AddYears(5) `
    -FriendlyName 'EXFIN-RDG-SAN'
$thumb = $cert.Thumbprint.ToUpperInvariant()
Write-FixLog ("new cert thumb=" + $thumb + ' notAfter=' + $cert.NotAfter)

Grant-MachineKeyRead -Cert $cert -Accounts @('NETWORK SERVICE', 'IIS_IUSRS', 'LOCAL SERVICE', 'W3SVC')
certutil -repairstore My $thumb | Out-Null

# Trust locally so same-box tests work
try {
    $cerFile = Join-Path $logDir 'exfin-rdg-san.cer'
    Export-Certificate -Cert $cert -FilePath $cerFile -Force | Out-Null
    Import-Certificate -FilePath $cerFile -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-FixLog 'Imported to LocalMachine\Root'
} catch {
    Write-FixLog ("WARN root import: {0}" -f $_.Exception.Message)
}

$guid = '{4dc3e181-e14b-4a21-b022-59fc669b0914}'
$hash = $thumb.ToLowerInvariant()
cmd /c 'netsh http delete sslcert ipport=0.0.0.0:443' | Out-Null
cmd /c 'netsh http delete sslcert ipport=[::]:443' | Out-Null
cmd /c ("netsh http add sslcert ipport=0.0.0.0:443 certhash={0} appid={1} certstorename=MY" -f $hash, $guid) | Out-Null
cmd /c ("netsh http add sslcert ipport=[::]:443 certhash={0} appid={1} certstorename=MY" -f $hash, $guid) | Out-Null
Write-FixLog 'HTTP.sys 443 rebound'

$bytes = New-Object byte[] ($thumb.Length / 2)
for ($i = 0; $i -lt $thumb.Length; $i += 2) {
    $bytes[$i / 2] = [Convert]::ToByte($thumb.Substring($i, 2), 16)
}
try {
    $gw = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayServerSettings
    if ($gw) {
        $r = $gw.SetCertificate($bytes)
        Write-FixLog ('SetCertificate ReturnValue=' + $r.ReturnValue)
    }
} catch {
    Write-FixLog ("WARN SetCertificate: {0}" -f $_.Exception.Message)
}

# RD Web Client broker cert (WASM validates this)
$mod = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\psmodules\RDWebClientManagement\1.0.4\RDWebClientManagement.psd1'
try {
    if (Test-Path -LiteralPath $mod) { Import-Module $mod -Force }
    elseif (Get-Module -ListAvailable -Name RDWebClientManagement) { Import-Module RDWebClientManagement -Force }
    if (Get-Command Install-RDWebClientBrokerCert -ErrorAction SilentlyContinue) {
        Install-RDWebClientBrokerCert -Thumbprint $thumb -ErrorAction Stop
        Write-FixLog 'Install-RDWebClientBrokerCert OK'
    } else {
        Write-FixLog 'WARN Install-RDWebClientBrokerCert missing'
    }
} catch {
    Write-FixLog ("WARN broker cert cmd: {0}" -f $_.Exception.Message)
}

foreach ($dir in @(
        'C:\Program Files\RemoteDesktopWeb\Internal\Config',
        'C:\ProgramData\RdpVirtualBoxApp\RdWebClient\content\Config',
        'C:\Windows\Web\RDWeb\webclient\config'
    )) {
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $dest = Join-Path $dir 'brokercert.cer'
        Export-Certificate -Cert $cert -FilePath $dest -Force | Out-Null
        Write-FixLog ("wrote " + $dest)
    } catch {
        Write-FixLog ("WARN brokercert {0}: {1}" -f $dir, $_.Exception.Message)
    }
}

# RDP: gateway = current web host (HTML5 already uses page host). Keep ARZ as session host.
$rdpPath = 'C:\Windows\Web\RDWeb\Pages\exfin\Tiger3Ent.rdp'
$appDataFeed = 'C:\Windows\Web\RDWeb\Pages\App_Data\exfin-webfeed.xml'
$rdpLines = @(
    'full address:s:ARZ'
    'server port:i:3389'
    'username:s:ARZ\EXFIN1'
    'prompt for credentials:i:1'
    'promptcredentialonce:i:1'
    'authentication level:i:0'
    'enablecredsspsupport:i:1'
    'negotiate security layer:i:1'
    'remoteapplicationmode:i:1'
    'remoteapplicationprogram:s:||Tiger3Ent'
    'remoteapplicationname:s:Tiger3 Enterprise'
    'disableremoteappcapscheck:i:1'
    'alternate shell:s:rdpinit.exe'
    'screen mode id:i:2'
    'redirectclipboard:i:1'
    'autoreconnection enabled:i:1'
    'gatewayusagemethod:i:1'
    'gatewayprofileusagemethod:i:1'
    'gatewaycredentialssource:i:0'
    'gatewayhostname:s:185.86.15.238'
)
# Keep public IP as gateway default for WAN HTML5; SAN now includes that IP.
$rdpText = ($rdpLines -join "`r`n") + "`r`n"
if (Test-Path -LiteralPath (Split-Path $rdpPath)) {
    $utf16 = New-Object System.Text.UnicodeEncoding $false, $true
    [System.IO.File]::WriteAllBytes($rdpPath, $utf16.GetPreamble() + $utf16.GetBytes($rdpText))
    Write-FixLog 'Updated Tiger3Ent.rdp'
}

# Refresh feed XML content base64
if (Test-Path -LiteralPath $appDataFeed) {
    try {
        $rdpB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($rdpPath))
        $xml = [System.IO.File]::ReadAllText($appDataFeed)
        $xml2 = [regex]::Replace($xml, '<Content>[^<]*</Content>', '<Content>' + $rdpB64 + '</Content>')
        [System.IO.File]::WriteAllText($appDataFeed, $xml2, [System.Text.UTF8Encoding]::new($false))
        Write-FixLog 'Updated exfin-webfeed.xml Content'
    } catch {
        Write-FixLog ("WARN feed rewrite: {0}" -f $_.Exception.Message)
    }
}

Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
Restart-Service TSGateway -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 8000; $tcp.SendTimeout = 8000
    $tcp.Connect('127.0.0.1', 443)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }))
    $ssl.AuthenticateAsClient('185.86.15.238')
    $got = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
    Write-FixLog ('TLS_IP subject=' + $got.Subject + ' thumb=' + $got.Thumbprint)
    $ssl.Close(); $tcp.Close()
} catch {
    Write-FixLog ("WARN TLS_IP: {0}" -f $_.Exception.Message)
}

Write-FixLog ('THUMBPRINT=' + $thumb)
'ok' | Set-Content -LiteralPath $done -Encoding ASCII
Write-FixLog 'DONE'
exit 0
