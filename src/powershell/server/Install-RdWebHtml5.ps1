#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Microsoft RD Web Client (HTML5) kurar.
    Asama 1: NuGet + PowerShellGet guncellemesi
    Asama 2: yeni PowerShell oturumunda paket, broker cert, 443 TLS
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 2)]
    [int]$Phase = 1,
    [string]$BrokerThumbprint = 'E33F3F68AEECA37A7B5E9F8913B62D86453AF107'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ('rdweb-html5-install.phase{0}.log' -f $Phase)
Start-Transcript -Path $log -Append -ErrorAction SilentlyContinue | Out-Null

function Write-Step([string]$Message) {
    Write-Output ('[{0}] {1}' -f $Phase, $Message)
}

try {
    Write-Step ('host=' + $env:COMPUTERNAME + ' user=' + $env:USERNAME + ' time=' + (Get-Date -Format o))
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    if ($Phase -eq 1) {
        Write-Step 'onceki takili kurulum surecleri durduruluyor'
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like '*Install-RdWebHtml5.ps1*' -and $_.ProcessId -ne $PID } |
            ForEach-Object {
                Write-Step ('kill pid=' + $_.ProcessId)
                try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
            }
        Start-Sleep -Seconds 2
        Write-Step 'NuGet + PowerShellGet'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap | Out-Null
        try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } catch { }
        Install-Module -Name PackageManagement -Force -AllowClobber -Scope AllUsers -ErrorAction SilentlyContinue
        Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers
        Write-Step 'PowerShellGet kuruldu, asama 2 basliyor'
        $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Phase 2 -BrokerThumbprint {1}' -f $PSCommandPath, $BrokerThumbprint
        $p = Start-Process -FilePath $psExe -ArgumentList $arg -Wait -PassThru
        if ($null -eq $p) { throw 'Asama 2 baslatilamadi.' }
        Write-Step ('asama2 exit=' + $p.ExitCode)
        if ($p.ExitCode -ne 0) { exit [int]$p.ExitCode }
        Write-Step 'DONE'
        exit 0
    }

    Write-Step ('PowerShellGet=' + ((Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version))
    $localMod = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\psmodules\RDWebClientManagement\1.0.4\RDWebClientManagement.psd1'
    if (Test-Path -LiteralPath $localMod) {
        Write-Step 'local RDWebClientManagement 1.0.4'
        Import-Module $localMod -Force
    }
    else {
        if (-not (Get-Module -ListAvailable -Name RDWebClientManagement)) {
            Install-Module -Name RDWebClientManagement -Force -AllowClobber -Scope AllUsers -AcceptLicense
        }
        Import-Module RDWebClientManagement -Force
    }
    Write-Step 'Install-RDWebClientPackage'
    $zip = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\rdwebclient-latest.zip'
    if (Test-Path -LiteralPath $zip) {
        Write-Step ('source=' + $zip)
        Install-RDWebClientPackage -Source $zip -Confirm:$false
    }
    else {
        Install-RDWebClientPackage -Confirm:$false
    }

    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $BrokerThumbprint }
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\LocalMachine\My |
            Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) -and $_.Subject -like ('CN=' + $env:COMPUTERNAME + '*') } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
    }
    if (-not $cert) { throw 'Gecerli LocalMachine cert bulunamadi.' }

    $cerDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
    New-Item -ItemType Directory -Force -Path $cerDir | Out-Null
    $cerPath = Join-Path $cerDir 'rd-broker.cer'
    if (Test-Path -LiteralPath $cerPath) { Remove-Item -LiteralPath $cerPath -Force }
    Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null
    Write-Step ('Import-RDWebClientBrokerCert ' + $cert.Subject)
    Import-RDWebClientBrokerCert -Path $cerPath -Confirm:$false
    Write-Step 'IIS publish (vdir, no WebAdministration hang)'
    try { Reset-IISServerManager -Confirm:$false } catch { }
    Remove-Module IISAdministration -ErrorAction SilentlyContinue
    $clientsRoot = 'C:\Program Files\RemoteDesktopWeb\Clients'
    $content = @(Get-ChildItem -LiteralPath $clientsRoot -Directory -ErrorAction Stop |
            ForEach-Object { Join-Path $_.FullName 'content' } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ 'index.html') }) |
        Select-Object -Last 1
    if (-not $content) { throw 'HTML5 content klasoru bulunamadi (RemoteDesktopWeb\Clients).' }
    $configPath = 'C:\Program Files\RemoteDesktopWeb\Config'
    if (-not (Test-Path -LiteralPath $configPath)) { throw 'RemoteDesktopWeb\Config yok; broker cert import basarisiz olabilir.' }

    Import-Module IISAdministration -Force
    $mgr = Get-IISServerManager
    $rdWeb = $null
    $siteName = $null
    foreach ($site in Get-IISSite) {
        $app = $site.Applications | Where-Object { $_.Path -eq '/RDWeb' } | Select-Object -First 1
        if ($app) { $rdWeb = $app; $siteName = $site.Name; break }
    }
    if (-not $rdWeb) { throw 'IIS /RDWeb uygulamasi yok.' }
    $vdir = $rdWeb.VirtualDirectories | Where-Object { $_.Path -eq '/webclient' } | Select-Object -First 1
    if ($vdir) { $vdir.PhysicalPath = $content } else { [void]$rdWeb.VirtualDirectories.Add('/webclient', $content) }
    $cfgVdir = $rdWeb.VirtualDirectories | Where-Object { $_.Path -eq '/webclient/config' } | Select-Object -First 1
    if ($cfgVdir) { $cfgVdir.PhysicalPath = $configPath } else { [void]$rdWeb.VirtualDirectories.Add('/webclient/config', $configPath) }
    $mgr.CommitChanges()
    Write-Step ('vdir /webclient -> ' + $content)

    $appcmd = Join-Path $env:SystemRoot 'System32\inetsrv\appcmd.exe'
    if (Test-Path -LiteralPath $appcmd -and $siteName) {
        $psPath = '{0}/RDWeb' -f $siteName
        cmd /c "`"$appcmd`" set config `"$psPath`" -section:system.webServer/httpRedirect /enabled:false /commit:apphost" | Out-Host
        cmd /c "`"$appcmd`" set config `"$psPath`" -section:system.webServer/staticContent /+`"[fileExtension='.wasm',mimeType='application/wasm']`" /commit:apphost" | Out-Host
    }

    $webclient = 'C:\Windows\Web\RDWeb\webclient'
    if (-not (Test-Path -LiteralPath $webclient)) {
        throw 'Kurulum bitti ama C:\Windows\Web\RDWeb\webclient olusmadi.'
    }

    $sslText = (netsh http show sslcert ipport=0.0.0.0:443 | Out-String)
    Write-Step $sslText
    $expiredHash = '15e47d33eaffa3a8f4d6bda02a0f24613964070b'
    if ($sslText -match $expiredHash -or $sslText -notmatch $cert.Thumbprint) {
        Write-Step ('443 TLS -> ' + $cert.Thumbprint + ' ' + $cert.Subject)
        $guid = '{4dc3e181-e14b-4a21-b022-59fc669b0914}'
        $hash = $cert.Thumbprint.ToLowerInvariant()
        cmd /c "netsh http delete sslcert ipport=0.0.0.0:443" | Out-Host
        cmd /c ("netsh http add sslcert ipport=0.0.0.0:443 certhash={0} appid={1} certstorename=MY" -f $hash, $guid) | Out-Host
        try { Restart-Service W3SVC -Force -ErrorAction Stop } catch { Write-Step ('W3SVC: ' + $_.Exception.Message) }
        try { Restart-Service TSGateway -Force -ErrorAction SilentlyContinue } catch { }
    }

    Write-Step 'OK webclient installed'
    Write-Step ('broker=' + $cert.Subject + ' thumb=' + $cert.Thumbprint)
    Write-Step 'url-lan=https://192.168.5.100/RDWeb/webclient/'
    Write-Step ('url-host=https://' + $env:COMPUTERNAME + '/RDWeb/webclient/')
    Write-Step 'DONE'
    exit 0
}
catch {
    Write-Step ('FAIL: ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
