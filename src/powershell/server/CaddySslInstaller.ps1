#requires -Version 5.1
<#
.SYNOPSIS
    Caddy HTTPS reverse proxy in front of Probe REST API (TCP 8445).

.DESCRIPTION
    Downloads Caddy, writes a Caddyfile, opens firewall port 8445, and
    starts a SYSTEM scheduled task. Without -Domain uses Caddy internal CA
    (tls internal). With -Domain uses Let's Encrypt on port 8445 (TLS-ALPN).
#>
[CmdletBinding()]
param(
    [string]$Domain = $env:RDPVB_CADDY_DOMAIN,
    [string]$Email  = $env:RDPVB_CADDY_EMAIL,
    [int]$HttpsPort = 8445,
    [int]$ProbePort = 8444,
    [string]$CaddyVersion = '2.11.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:InstallDir = Join-Path $env:ProgramFiles 'RdpVirtualBoxApp\Caddy'
$script:DataDir    = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Caddy'
$script:ConfigDir  = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
$script:LogFile    = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs\caddy-ssl.log'
$script:CaddyExe   = Join-Path $script:InstallDir 'caddy.exe'
$script:Caddyfile  = Join-Path $script:ConfigDir 'Caddyfile'
$script:TaskName   = 'RdpVirtualBoxApp-Caddy'

function Write-CaddyLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path $script:LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    } catch {}
    Write-Output $line
}

function Get-CaddySiteNames {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($n in @('localhost', '127.0.0.1', $env:COMPUTERNAME)) {
        if ($n) { [void]$names.Add($n) }
    }
    try {
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
            ForEach-Object { [void]$names.Add($_.IPAddress) }
    } catch {}
    $ep = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\client-endpoints.json'
    if (Test-Path -LiteralPath $ep) {
        try {
            $j = Get-Content -LiteralPath $ep -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in @('lan','public','vpn','client')) {
                $v = [string]$j.$prop
                if ($v -match '^\d{1,3}(\.\d{1,3}){3}$') { [void]$names.Add($v) }
            }
        } catch {}
    }
    return @($names | Select-Object -Unique)
}

function Get-CaddyfileContent {
    param([string]$HostName, [string]$AcmeEmail, [int]$TlsPort, [int]$BackendPort)
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        $sites = (Get-CaddySiteNames) -join ', '
        return @"
{
    admin off
    auto_https disable_redirects
    https_port $TlsPort
    http_port 8088
    storage file_system {
        root C:/ProgramData/RdpVirtualBoxApp/Caddy
    }
    servers {
        protocols h1 h2
    }
}

$sites {
    tls internal
    encode gzip
    reverse_proxy 127.0.0.1:$BackendPort
}
"@
    }

    $emailLine = if ($AcmeEmail) { "    email $AcmeEmail" } else { '' }
    return @"
{
    admin off
    auto_https disable_redirects
    http_port 80
    https_port $TlsPort
    storage file_system {
        root C:/ProgramData/RdpVirtualBoxApp/Caddy
    }
    servers {
        protocols h1 h2
    }
$emailLine
}

http://$HostName {
    redir https://{host}:$TlsPort{uri} permanent
}

https://$HostName`:$TlsPort {
    encode gzip
    reverse_proxy 127.0.0.1:$BackendPort
}
"@
}

function Install-CaddyBinary {
    param([string]$Version)
    if (-not (Test-Path $script:InstallDir)) { New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null }
    if (Test-Path -LiteralPath $script:CaddyExe) {
        Write-CaddyLog "caddy.exe already present"
        return
    }
    $zipName = "caddy_${Version}_windows_amd64.zip"
    $url = "https://github.com/caddyserver/caddy/releases/download/v$Version/$zipName"
    $tmp = Join-Path $env:TEMP $zipName
    Write-CaddyLog "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    $extract = Join-Path $env:TEMP "caddy-extract-$Version"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -LiteralPath $tmp -DestinationPath $extract -Force
    $found = Get-ChildItem -Path $extract -Filter 'caddy.exe' -Recurse | Select-Object -First 1
    if (-not $found) { throw "caddy.exe not found in $zipName" }
    Copy-Item -LiteralPath $found.FullName -Destination $script:CaddyExe -Force
    Write-CaddyLog "Installed $($script:CaddyExe)"
}

function Install-CaddyScheduledTask {
    $launcher = Join-Path $script:InstallDir 'Start-Caddy.cmd'
    $cmd = @"
@echo off
set HOME=$($script:DataDir)
set CADDY_DATA_DIR=$($script:DataDir)
set XDG_DATA_HOME=$(Split-Path $script:DataDir -Parent)
"$($script:CaddyExe)" run --config "$($script:Caddyfile)" --adapter caddyfile >> "$($script:LogFile.Replace('caddy-ssl.log','caddy-run.log'))" 2>&1
"@
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($launcher, $cmd, $utf8)
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $action = New-ScheduledTaskAction -Execute $script:CaddyExe -Argument "run --config `"$($script:Caddyfile)`" --adapter caddyfile" -WorkingDirectory $script:InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    Write-CaddyLog "Scheduled task $($script:TaskName) registered"
}

function Import-CaddyInternalCa {
    $root = Join-Path $script:DataDir 'pki\authorities\local\root.crt'
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Path -LiteralPath $root) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path -LiteralPath $root) {
        try {
            Import-Certificate -FilePath $root -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
            Write-CaddyLog "Trusted Caddy internal CA: $root"
        } catch {
            Write-CaddyLog "WARN trust CA: $($_.Exception.Message)" 'WARN'
        }
    } else {
        Write-CaddyLog "Caddy CA not ready yet (will be trusted on next start)" 'WARN'
    }
}

function Install-CaddySsl {
    [CmdletBinding()]
    param(
        [string]$Domain = $env:RDPVB_CADDY_DOMAIN,
        [string]$Email  = $env:RDPVB_CADDY_EMAIL,
        [int]$HttpsPort = 8445,
        [int]$ProbePort = 8444,
        [string]$CaddyVersion = '2.11.4'
    )

    foreach ($d in @($script:InstallDir, $script:DataDir, $script:ConfigDir, (Split-Path $script:LogFile -Parent))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    $env:XDG_DATA_HOME = Split-Path $script:DataDir -Parent
    $env:CADDY_DATA_DIR = $script:DataDir

    Install-CaddyBinary -Version $CaddyVersion
    $content = Get-CaddyfileContent -HostName $Domain -AcmeEmail $Email -TlsPort $HttpsPort -BackendPort $ProbePort
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:Caddyfile, $content, $utf8)
    Write-CaddyLog "Wrote $($script:Caddyfile)"

    $ports = @($HttpsPort)
    if ($Domain) { $ports += 80 }
    foreach ($p in $ports) {
        $name = if ($p -eq 80) { 'RdpVirtualBoxApp - Caddy ACME HTTP 80' } else { 'RdpVirtualBoxApp - Caddy HTTPS 8445' }
        $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -Profile Any -Enabled True -ErrorAction Stop | Out-Null
                Write-CaddyLog "Firewall TCP/$p opened"
            } catch {
                Write-CaddyLog "WARN firewall TCP/${p}: $($_.Exception.Message)" 'WARN'
            }
        } else {
            Write-CaddyLog "Firewall rule already present: $name"
        }
    }

    Get-CimInstance Win32_Process -Filter "Name='caddy.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $env:HOME = $script:DataDir
    Install-CaddyScheduledTask
    Start-Sleep -Seconds 6
    if (-not $Domain) { Import-CaddyInternalCa }

    $mode = if ($Domain) { "Let's Encrypt ($Domain)" } else { 'tls internal (Caddy CA)' }
    Write-CaddyLog "Caddy HTTPS listening on 0.0.0.0:$HttpsPort mode=$mode backend=127.0.0.1:$ProbePort"
    return [pscustomobject]@{
        Success   = $true
        HttpsUrl  = "https://127.0.0.1:$HttpsPort/health"
        Domain    = $Domain
        Caddyfile = $script:Caddyfile
        Mode      = $mode
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-CaddySsl -Domain $Domain -Email $Email -HttpsPort $HttpsPort -ProbePort $ProbePort -CaddyVersion $CaddyVersion
}
