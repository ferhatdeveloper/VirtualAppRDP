#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workgroup RD Gateway CAP/RAP (local kullanicilar), NPS, IIS Rpc,
    ve HTML5 webclient vdir. Sifre reddi + web calismama icin.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rd-gateway-access-fix.log'
Start-Transcript -Path $log -Append | Out-Null
Write-Output ('start ' + (Get-Date -Format o) + ' user=' + $env:USERNAME)

function Write-Step([string]$m) { Write-Output ('>> ' + $m) }

try {
    Import-Module RemoteDesktopServices -ErrorAction SilentlyContinue
    Import-Module IISAdministration -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    Write-Step 'NPS/IAS'
    $ias = Get-Service IAS -ErrorAction SilentlyContinue
    if ($ias -and $ias.Status -ne 'Running') { Start-Service IAS }

    Write-Step 'Mevcut CAP/RAP'
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('CAP name=' + $_.Name + ' enabled=' + $_.Enabled + ' groups=' + $_.UserGroupNames + ' auth=' + $_.AuthMethod) }
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayResourceAuthorizationPolicy -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('RAP name=' + $_.Name + ' enabled=' + $_.Enabled + ' groups=' + $_.UserGroupNames + ' cgType=' + $_.ComputerGroupType + ' ports=' + $_.PortNumbers + ' computers=' + $_.ComputerGroupNames) }

    $groups = 'BUILTIN\Remote Desktop Users;BUILTIN\Administrators'
    $capName = 'Exfin-CAP'
    $rapName = 'Exfin-RAP'

    $existingCap = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy -Filter "Name='$capName'" -ErrorAction SilentlyContinue
    if (-not $existingCap) {
        $cls = [wmiclass]'root\CIMV2\TerminalServices:Win32_TSGatewayConnectionAuthorizationPolicy'
        Write-Step 'CAP Create metod imzasi'
        $cls.Methods['Create'].InParameters.Properties | ForEach-Object { Write-Output ('  in ' + $_.Name + ' ' + $_.CIMType) }
        try {
            $r = $cls.Create($capName, $groups, 0, $true, 120, $true, 480, 0, $false, $false, $false, $false, $false, $false)
            Write-Output ('CAP Create ReturnValue=' + $r.ReturnValue + ' Policy=' + $r.PolicyName)
        } catch {
            Write-Output ('CAP Create v1 fail: ' + $_.Exception.Message)
            try {
                $r = $cls.Create($capName, $groups, 0, $false, 0, 15, 600, $false, $true)
                Write-Output ('CAP Create v2 ReturnValue=' + $r.ReturnValue)
            } catch {
                Write-Output ('CAP Create v2 fail: ' + $_.Exception.Message)
            }
        }
    } else {
        Write-Step 'CAP zaten var, gruplari guncelle'
        try { $existingCap.UserGroupNames = $groups; $existingCap.AuthMethod = 0; $existingCap.Enabled = $true; $null = $existingCap.Put() } catch { Write-Output $_.Exception.Message }
    }

    $existingRap = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayResourceAuthorizationPolicy -Filter "Name='$rapName'" -ErrorAction SilentlyContinue
    if (-not $existingRap) {
        $rcls = [wmiclass]'root\CIMV2\TerminalServices:Win32_TSGatewayResourceAuthorizationPolicy'
        Write-Step 'RAP Create metod imzasi'
        $rcls.Methods['Create'].InParameters.Properties | ForEach-Object { Write-Output ('  in ' + $_.Name + ' ' + $_.CIMType) }
        try {
            # ComputerGroupType 2 = all network resources
            $r = $rcls.Create($rapName, $groups, '', 2, '3389', $true)
            Write-Output ('RAP Create ReturnValue=' + $r.ReturnValue + ' Policy=' + $r.PolicyName)
        } catch {
            Write-Output ('RAP Create fail: ' + $_.Exception.Message)
        }
    } else {
        Write-Step 'RAP zaten var'
        try {
            $existingRap.UserGroupNames = $groups
            $existingRap.ComputerGroupType = 2
            $existingRap.PortNumbers = '3389'
            $existingRap.Enabled = $true
            $null = $existingRap.Put()
        } catch { Write-Output $_.Exception.Message }
    }

    # RDS: drive fallback
    if (Test-Path 'RDS:\GatewayServer\CAP') {
        Get-ChildItem 'RDS:\GatewayServer\CAP' | ForEach-Object { Write-Output ('RDS CAP ' + $_.Name) }
        Get-ChildItem 'RDS:\GatewayServer\RAP' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('RDS RAP ' + $_.Name) }
    }

    Write-Step 'IIS uygulamalari'
    try {
        Get-IISSite | ForEach-Object {
            Write-Output ('site=' + $_.Name + ' state=' + $_.State)
            $_.Applications | ForEach-Object { Write-Output ('  app=' + $_.Path) }
        }
    } catch { Write-Output ('Get-IISSite: ' + $_.Exception.Message) }

    $appcmd = Join-Path $env:SystemRoot 'System32\inetsrv\appcmd.exe'
    if (Test-Path $appcmd) {
        & $appcmd list app | Out-Host
        & $appcmd list vdir | Out-Host
    }

    Write-Step 'HTML5 paket'
    $zip = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\rdwebclient-latest.zip'
    $stage = Join-Path $env:ProgramData 'RdpVirtualBoxApp\RdWebClient'
    $content = $null
    if (Test-Path $zip) {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
        $idx = Get-ChildItem $stage -Recurse -Filter 'index.html' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($idx) { $content = $idx.DirectoryName }
        Write-Output ('html5 content=' + $content)
    }
    $clientsRoot = 'C:\Program Files\RemoteDesktopWeb\Clients'
    if (-not $content -and (Test-Path $clientsRoot)) {
        $idx = Get-ChildItem $clientsRoot -Recurse -Filter 'index.html' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($idx) { $content = $idx.DirectoryName }
    }

    $rdWebApp = $null
    $siteName = $null
    try {
        foreach ($site in Get-IISSite) {
            $app = $site.Applications | Where-Object { $_.Path -eq '/RDWeb' } | Select-Object -First 1
            if ($app) { $rdWebApp = $app; $siteName = $site.Name; break }
        }
    } catch {}

    if ($content -and $rdWebApp) {
        Write-Step ('webclient vdir -> ' + $content)
        $mgr = Get-IISServerManager
        $vdir = $rdWebApp.VirtualDirectories | Where-Object { $_.Path -eq '/webclient' } | Select-Object -First 1
        if ($vdir) { $vdir.PhysicalPath = $content } else { [void]$rdWebApp.VirtualDirectories.Add('/webclient', $content) }
        $mgr.CommitChanges()
        if ($siteName -and (Test-Path $appcmd)) {
            $psPath = '{0}/RDWeb' -f $siteName
            cmd /c "`"$appcmd`" set config `"$psPath`" -section:system.webServer/httpRedirect /enabled:false /commit:apphost" | Out-Host
            cmd /c "`"$appcmd`" set config `"$psPath`" -section:system.webServer/staticContent /+`"[fileExtension='.wasm',mimeType='application/wasm']`" /commit:apphost" | Out-Host
        }
        Write-Output ('webclient exists=' + (Test-Path (Join-Path $content 'index.html')))
    } else {
        Write-Output ('HTML5 skip content=' + [bool]$content + ' rdweb=' + [bool]$rdWebApp)
    }

    Write-Step 'son CAP/RAP'
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('CAP name=' + $_.Name + ' enabled=' + $_.Enabled + ' groups=' + $_.UserGroupNames + ' auth=' + $_.AuthMethod) }
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayResourceAuthorizationPolicy -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('RAP name=' + $_.Name + ' enabled=' + $_.Enabled + ' groups=' + $_.UserGroupNames + ' cgType=' + $_.ComputerGroupType + ' ports=' + $_.PortNumbers) }

    Restart-Service IAS -Force -ErrorAction SilentlyContinue
    Restart-Service TSGateway -Force
    Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Output ('TSGateway=' + (Get-Service TSGateway).Status + ' IAS=' + (Get-Service IAS).Status)
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
