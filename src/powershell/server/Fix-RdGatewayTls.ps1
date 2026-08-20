#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    RD Gateway 443 TLS: suresi dolmus WIN-FAB395IK1BM yerine gecerli CN=ARZ
    sertifikasini baglar, private key ACL verir, TSGateway'i yeniden baslatir.
#>
[CmdletBinding()]
param(
    [string]$Thumbprint = 'E33F3F68AEECA37A7B5E9F8913B62D86453AF107'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rd-gateway-tls-fix.log'
Start-Transcript -Path $log -Append -ErrorAction SilentlyContinue | Out-Null

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
    $uniq = @($paths | Select-Object -Unique)
    foreach ($file in $uniq) {
        foreach ($acct in $Accounts) {
            cmd /c ("icacls `"$file`" /grant `"${acct}:(R)`"") | Out-Host
        }
        Write-Output ('acl=' + $file)
    }
    if ($uniq.Count -lt 1) { Write-Output 'WARN: private key dosyasi bulunamadi; certutil -repairstore denenecek' }
}

try {
    $thumb = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
    if (-not $cert) { throw "Sertifika yok: $thumb" }
    if (-not $cert.HasPrivateKey) { throw 'Private key yok.' }
    if ($cert.NotAfter -lt (Get-Date)) { throw ('Sertifika suresi dolmus: ' + $cert.NotAfter) }
    Write-Output ('using ' + $cert.Subject + ' notAfter=' + $cert.NotAfter)

    Grant-MachineKeyRead -Cert $cert -Accounts @('NETWORK SERVICE', 'IIS_IUSRS', 'LOCAL SERVICE')
    certutil -repairstore My $thumb | Out-Host

    $guid = '{4dc3e181-e14b-4a21-b022-59fc669b0914}'
    $hash = $thumb.ToLowerInvariant()
    cmd /c 'netsh http delete sslcert ipport=0.0.0.0:443' | Out-Host
    cmd /c 'netsh http delete sslcert ipport=[::]:443' | Out-Host
    cmd /c ("netsh http add sslcert ipport=0.0.0.0:443 certhash={0} appid={1} certstorename=MY" -f $hash, $guid) | Out-Host
    cmd /c ("netsh http add sslcert ipport=[::]:443 certhash={0} appid={1} certstorename=MY" -f $hash, $guid) | Out-Host

    $bytes = New-Object byte[] ($thumb.Length / 2)
    for ($i = 0; $i -lt $thumb.Length; $i += 2) {
        $bytes[$i / 2] = [Convert]::ToByte($thumb.Substring($i, 2), 16)
    }
    $gw = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayServerSettings
    if ($gw) {
        $r = $gw.SetCertificate($bytes)
        Write-Output ('SetCertificate ReturnValue=' + $r.ReturnValue)
    } else {
        Write-Output 'WARN: Win32_TSGatewayServerSettings yok'
    }

    if (Get-Module -ListAvailable -Name RemoteDesktopServices) {
        Import-Module RemoteDesktopServices -ErrorAction SilentlyContinue
        if (Test-Path 'RDS:\GatewayServer') {
            try { Set-ItemProperty -LiteralPath 'RDS:\GatewayServer\SSLCertificate' -Name Thumbprint -Value $thumb -ErrorAction Stop } catch { }
            try { Set-ItemProperty -LiteralPath 'RDS:\GatewayServer\GatewayServer' -Name CertificateThumbprint -Value $thumb -ErrorAction Stop } catch { }
        }
    }

    Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
    Restart-Service TSGateway -Force -ErrorAction Stop
    Start-Sleep -Seconds 3

    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 8000; $tcp.SendTimeout = 8000
    $tcp.Connect('127.0.0.1', 443)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }))
    $ssl.AuthenticateAsClient('ARZ')
    $got = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
    Write-Output ('TLS_OK subject=' + $got.Subject + ' notAfter=' + $got.NotAfter + ' thumb=' + $got.Thumbprint)
    $ssl.Close(); $tcp.Close()

    $ev = Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-Gateway/Operational' -MaxEvents 5 -ErrorAction SilentlyContinue
    foreach ($e in $ev) { Write-Output ('evt ' + $e.Id + ' ' + $e.TimeCreated + ' ' + $e.LevelDisplayName) }
    Write-Output 'DONE'
    exit 0
}
catch {
    Write-Output ('FAIL: ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
