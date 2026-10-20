#requires -Version 5.1
<#
.SYNOPSIS
    Istemci SQL Bridge: 127.0.0.1:<localPort> dinler, Probe API CONNECT
    /sql-bridge tüneli ile sunucu SQL'ine iletir.

.DESCRIPTION
    SSMS, Excel, yerel ERP istemcileri Server=127.0.0.1,1433 ile baglanir;
    trafik sunucuya RemoteApp olmadan gider.

    Modlar:
      Listen    - on planda dinle
      Install   - config + logon scheduled task + baglanti dizesi dosyasi
      Uninstall - task durdur / sil
      Status    - durum JSON

.PARAMETER Server
    Probe API sunucu IP / hostname.

.PARAMETER ProbePort
    Probe API portu (varsayilan 8444).

.PARAMETER Token
    Bearer token (probe-api.json ile ayni).

.PARAMETER LocalPort
    Yerel dinleme portu (varsayilan 1433).

.NOTES
    Author  : Rdp Virtual Box App
    Module  : client/SqlBridgeClient.ps1
    Version : 1.1.6
#>
[CmdletBinding()]
param(
    [ValidateSet('Listen', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Status',

    [string]$Server,

    [ValidateRange(1, 65535)]
    [int]$ProbePort = 8444,

    [string]$Token,

    [ValidateRange(1, 65535)]
    [int]$LocalPort = 1433,

    [string]$LocalBind = '127.0.0.1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TaskName   = 'RdpVirtualBoxApp-SqlBridge'
$script:ConfigDir  = Join-Path $env:LOCALAPPDATA 'RdpVirtualBoxApp\Config'
$script:ConfigFile = Join-Path $script:ConfigDir 'sql-bridge-client.json'
$script:LogFile    = Join-Path $env:LOCALAPPDATA 'RdpVirtualBoxApp\Logs\sql-bridge-client.log'
$script:PidFile    = Join-Path $script:ConfigDir 'sql-bridge-client.pid'
$script:StopFile   = Join-Path $script:ConfigDir 'sql-bridge-client.stop'
$script:ConnFile   = Join-Path $env:LOCALAPPDATA 'RdpVirtualBoxApp\sql-bridge-connection.txt'
$script:WindowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-SqlBridgeClientLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Verbose $line
}

function Get-SqlBridgeClientConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $cfg = [ordered]@{
        server    = ''
        probePort = 8444
        token     = ''
        localPort = 1433
        localBind = '127.0.0.1'
        enabled   = $false
        updatedAt = ''
    }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) { return $cfg }
    try {
        $obj = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    } catch {
        Write-SqlBridgeClientLog -Level WARN -Message "Config okunamadi: $($_.Exception.Message)"
    }
    return $cfg
}

function Save-SqlBridgeClientConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)

    if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    }
    $Config['updatedAt'] = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -LiteralPath $script:ConfigFile -Value ($Config | ConvertTo-Json -Depth 5) -Encoding UTF8
}

function Write-SqlBridgeConnectionHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$ServerHost
    )

    $text = @"
EXFIN RemoteAPP - SQL Bridge
============================
Sunucu SQL'i bu PC'de yerel gibi kullanilir.

SSMS / baglanti dizesi (HER ZAMAN localhost):
  Server=127.0.0.1,$Port
  Data Source=127.0.0.1,$Port

Ornek:
  Server=127.0.0.1,$Port;Database=YourDb;User Id=...;Password=...;Encrypt=False;

Tünel ucu (sunucu adi VEYA public IP — Probe API):
  $ServerHost  (CONNECT /sql-bridge)
  Ornek: SUNUCU01  |  rdp.firma.local  |  203.0.113.50
  SQL TCP 1433 internete ACILMAZ; yalnizca Probe portu kullanilir.
  Sertifika: kurulum /sql-bridge.cer indirip otomatik guvenir.

Durum:  powershell -File SqlBridgeClient.ps1 -Mode Status
Durdur: powershell -File SqlBridgeClient.ps1 -Mode Uninstall
"@
    $dir = Split-Path -Parent $script:ConnFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $script:ConnFile -Value $text -Encoding UTF8
    return $script:ConnFile
}

function Start-SqlBridgeClientListen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerHost,
        [Parameter(Mandatory)][int]$ProbeApiPort,
        [string]$BearerToken,
        [Parameter(Mandatory)][int]$ListenPort,
        [string]$Bind = '127.0.0.1'
    )

    $ip = [System.Net.IPAddress]::Parse($Bind)
    $listener = New-Object System.Net.Sockets.TcpListener $ip, $ListenPort
    $listener.Server.SetSocketOption(
        [System.Net.Sockets.SocketOptionLevel]::Socket,
        [System.Net.Sockets.SocketOptionName]::ReuseAddress,
        $true
    )
    $listener.Start()

    if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    }
    Set-Content -LiteralPath $script:PidFile -Value $PID -Encoding ASCII
    if (Test-Path -LiteralPath $script:StopFile) {
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
    }

    Write-SqlBridgeClientLog -Message "SQL Bridge dinleniyor ${Bind}:${ListenPort} -> ${ServerHost}:${ProbeApiPort}/sql-bridge"
    Write-Information -MessageData "SQL Bridge: localhost:$ListenPort -> $ServerHost (Probe CONNECT)" -InformationAction Continue

    try {
        while ($true) {
            if (Test-Path -LiteralPath $script:StopFile) {
                Write-SqlBridgeClientLog -Message 'Stop file; cikis.'
                break
            }
            if (-not $listener.Pending()) {
                Start-Sleep -Milliseconds 80
                continue
            }

            $localClient = $listener.AcceptTcpClient()
            $localClient.NoDelay = $true
            Write-SqlBridgeClientLog -Message "Yerel baglanti: $($localClient.Client.RemoteEndPoint)"

            $pool = [runspacefactory]::CreateRunspace()
            $pool.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $pool
            [void]$ps.AddScript({
                param($local, $serverHost, $probePort, $token, $logFn)
                try {
                    $localStream = $local.GetStream()
                    $tunnel = $null
                    $remoteClient = New-Object System.Net.Sockets.TcpClient
                    $remoteClient.NoDelay = $true
                    $remoteClient.Connect($serverHost, $probePort)
                    $tunnel = $remoteClient.GetStream()
                    $authLine = ''
                    if ($token) { $authLine = "Authorization: Bearer $token`r`n" }
                    $req = "CONNECT /sql-bridge HTTP/1.1`r`nHost: ${serverHost}:${probePort}`r`n${authLine}Connection: keep-alive`r`n`r`n"
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes($req)
                    $tunnel.Write($bytes, 0, $bytes.Length)
                    $tunnel.Flush()

                    $ms = New-Object System.IO.MemoryStream
                    $buf = New-Object byte[] 4096
                    $deadline = [datetime]::UtcNow.AddSeconds(20)
                    $headerText = ''
                    while ([datetime]::UtcNow -lt $deadline) {
                        $n = $tunnel.Read($buf, 0, $buf.Length)
                        if ($n -le 0) { break }
                        $ms.Write($buf, 0, $n)
                        $headerText = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
                        if ($headerText.Contains("`r`n`r`n") -or $headerText.Contains("`n`n")) { break }
                    }
                    if ($headerText -notmatch 'HTTP/1\.[01]\s+200') {
                        throw "Tunnel rejected: $headerText"
                    }

                    # leftover body after headers (rare) — SQL TDS starts after CRLFCRLF
                    $sep = $headerText.IndexOf("`r`n`r`n")
                    $sepLen = 4
                    if ($sep -lt 0) { $sep = $headerText.IndexOf("`n`n"); $sepLen = 2 }
                    $all = $ms.ToArray()
                    $bodyStart = $sep + $sepLen
                    if ($bodyStart -lt $all.Length) {
                        $localStream.Write($all, $bodyStart, $all.Length - $bodyStart)
                    }

                    $copyScript = {
                        param($src, $dst)
                        try {
                            $b = New-Object byte[] 16384
                            while ($true) {
                                $r = $src.Read($b, 0, $b.Length)
                                if ($r -le 0) { break }
                                $dst.Write($b, 0, $r)
                                $dst.Flush()
                            }
                        } catch { }
                    }
                    $rs1 = [powershell]::Create().AddScript($copyScript).AddArgument($localStream).AddArgument($tunnel)
                    $rs2 = [powershell]::Create().AddScript($copyScript).AddArgument($tunnel).AddArgument($localStream)
                    $h1 = $rs1.BeginInvoke()
                    $h2 = $rs2.BeginInvoke()
                    [void][System.Threading.WaitHandle]::WaitAny(@($h1.AsyncWaitHandle, $h2.AsyncWaitHandle))
                    try { $rs1.EndInvoke($h1) } catch { }
                    try { $rs2.EndInvoke($h2) } catch { }
                    $rs1.Dispose(); $rs2.Dispose()
                    try { $tunnel.Close() } catch { }
                    try { $remoteClient.Close() } catch { }
                } catch {
                    # swallow per-connection errors
                } finally {
                    try { $local.Close() } catch { }
                }
            }).AddArgument($localClient).AddArgument($ServerHost).AddArgument($ProbeApiPort).AddArgument($BearerToken).AddArgument($null)

            # Fire and forget — keep accepting
            [void]$ps.BeginInvoke()
        }
    }
    finally {
        try { $listener.Stop() } catch { }
        Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        Write-SqlBridgeClientLog -Message 'SQL Bridge durdu.'
    }
}

function Install-SqlBridgeClientCertificate {
    <#
    .SYNOPSIS
        Sunucudan /sql-bridge.cer (veya /gateway.cer) indirir ve CurrentUser\Root'a guvenir.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$ServerHost,
        [int]$ProbeApiPort = 8444
    )

    $cerDir = Join-Path $env:LOCALAPPDATA 'RdpVirtualBoxApp\Config'
    if (-not (Test-Path -LiteralPath $cerDir)) {
        New-Item -ItemType Directory -Path $cerDir -Force | Out-Null
    }
    $cerFile = Join-Path $cerDir 'EXFIN-SqlBridge.cer'
    $ok = $false
    $err = ''
    foreach ($path in @('/sql-bridge.cer', '/gateway.cer')) {
        $uri = 'http://{0}:{1}{2}' -f $ServerHost, $ProbeApiPort, $path
        try {
            Write-SqlBridgeClientLog -Message "Sertifika indiriliyor: $uri"
            Invoke-WebRequest -Uri $uri -OutFile $cerFile -UseBasicParsing -TimeoutSec 15
            if ((Test-Path -LiteralPath $cerFile) -and ((Get-Item -LiteralPath $cerFile).Length -gt 32)) {
                Import-Certificate -FilePath $cerFile -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction Stop | Out-Null
                Write-SqlBridgeClientLog -Message "Sertifika CurrentUser\Root'a eklendi: $cerFile"
                $ok = $true
                break
            }
        } catch {
            $err = $_.Exception.Message
            Write-SqlBridgeClientLog -Level WARN -Message ("Sertifika {0} basarisiz: {1}" -f $path, $err)
        }
    }
    return [ordered]@{ success = $ok; cerPath = $cerFile; error = $err }
}

function Install-SqlBridgeClient {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$ServerHost,
        [int]$ProbeApiPort = 8444,
        [string]$BearerToken,
        [int]$ListenPort = 1433,
        [string]$Bind = '127.0.0.1'
    )

    $cfg = [ordered]@{
        server    = $ServerHost
        probePort = $ProbeApiPort
        token     = $BearerToken
        localPort = $ListenPort
        localBind = $Bind
        enabled   = $true
    }
    Save-SqlBridgeClientConfig -Config $cfg
    $hint = Write-SqlBridgeConnectionHint -Port $ListenPort -ServerHost $ServerHost

    $certResult = $null
    try {
        $certResult = Install-SqlBridgeClientCertificate -ServerHost $ServerHost -ProbeApiPort $ProbeApiPort
    } catch {
        Write-SqlBridgeClientLog -Level WARN -Message "Sertifika kurulumu atladi: $($_.Exception.Message)"
        $certResult = [ordered]@{ success = $false; error = $_.Exception.Message }
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    $arg = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$scriptPath`" -Mode Listen"
    $action = New-ScheduledTaskAction -Execute $script:WindowsPowerShell -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    try {
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch { }

    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

    # Start immediately in background
    try {
        Start-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    } catch {
        Start-Process -FilePath $script:WindowsPowerShell -ArgumentList $arg -WindowStyle Hidden
    }

    Write-SqlBridgeClientLog -Message "Install tamam: task=$script:TaskName hint=$hint"
    return [ordered]@{
        success          = $true
        taskName         = $script:TaskName
        localEndpoint    = "${Bind}:${ListenPort}"
        connectionFile   = $hint
        connectionString = "Server=127.0.0.1,$ListenPort;Encrypt=False;"
        server           = $ServerHost
        probePort        = $ProbeApiPort
        certificate      = $certResult
    }
}

function Uninstall-SqlBridgeClient {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
        Set-Content -LiteralPath $script:StopFile -Value '1' -Encoding ASCII
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
        $cfg = Get-SqlBridgeClientConfig
        $cfg.enabled = $false
        Save-SqlBridgeClientConfig -Config $cfg
        Write-SqlBridgeClientLog -Message 'Uninstall tamam.'
        return [ordered]@{ success = $true; taskName = $script:TaskName }
    } catch {
        return [ordered]@{ success = $false; error = $_.Exception.Message }
    }
}

function Get-SqlBridgeClientStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $cfg = Get-SqlBridgeClientConfig
    $listening = $false
    $port = 1433
    try { $port = [int]$cfg.localPort } catch { }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(400, $false)) {
            $c.EndConnect($iar)
            $listening = $true
        }
        $c.Close()
    } catch { $listening = $false }

    $task = $null
    try { $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue } catch { }

    return [ordered]@{
        enabled       = [bool]$cfg.enabled
        server        = [string]$cfg.server
        probePort     = [int]$cfg.probePort
        localPort     = $port
        localBind     = [string]$cfg.localBind
        listening     = $listening
        taskExists    = [bool]$task
        taskState     = if ($task) { [string]$task.State } else { 'Missing' }
        connectionFile = $script:ConnFile
        configPath    = $script:ConfigFile
    }
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
$isDirect = $MyInvocation.InvocationName -ne '.' -and
            $MyInvocation.Line -notmatch '^\s*\.\s+' -and
            $PSCommandPath -and
            $MyInvocation.MyCommand.Path -and
            ($MyInvocation.MyCommand.Path -eq $PSCommandPath)

if ($isDirect) {
    try {
        switch ($Mode) {
            'Status' {
                Get-SqlBridgeClientStatus | ConvertTo-Json -Depth 5
            }
            'Uninstall' {
                Uninstall-SqlBridgeClient | ConvertTo-Json -Depth 5
            }
            'Install' {
                if ([string]::IsNullOrWhiteSpace($Server)) { throw '-Server zorunlu (Install).' }
                $result = Install-SqlBridgeClient -ServerHost $Server -ProbeApiPort $ProbePort -BearerToken $Token -ListenPort $LocalPort -Bind $LocalBind
                $result | ConvertTo-Json -Depth 5
            }
            'Listen' {
                $cfg = Get-SqlBridgeClientConfig
                $hostName = if ($Server) { $Server } else { [string]$cfg.server }
                $pPort = if ($PSBoundParameters.ContainsKey('ProbePort')) { $ProbePort } else { [int]$cfg.probePort }
                $tok = if ($Token) { $Token } else { [string]$cfg.token }
                $lPort = if ($PSBoundParameters.ContainsKey('LocalPort')) { $LocalPort } else { [int]$cfg.localPort }
                $bind = if ($PSBoundParameters.ContainsKey('LocalBind')) { $LocalBind } else { [string]$cfg.localBind }
                if ([string]::IsNullOrWhiteSpace($hostName)) { throw 'Listen icin server adresi yok (Install once).' }
                if ($lPort -lt 1) { $lPort = 1433 }
                if ($pPort -lt 1) { $pPort = 8444 }
                if ([string]::IsNullOrWhiteSpace($bind)) { $bind = '127.0.0.1' }
                Start-SqlBridgeClientListen -ServerHost $hostName -ProbeApiPort $pPort -BearerToken $tok -ListenPort $lPort -Bind $bind
            }
        }
    } catch {
        Write-SqlBridgeClientLog -Level ERROR -Message $_.Exception.Message
        Write-Error -ErrorRecord $_
        exit 1
    }
}
