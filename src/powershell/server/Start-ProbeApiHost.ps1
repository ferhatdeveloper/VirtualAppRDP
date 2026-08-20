#requires -Version 5.1
<#
.SYNOPSIS
    Starts, installs or stops the Rdp Virtual Box App Probe REST API host.

.DESCRIPTION
    Extra runtime (IIS / Kestrel / .NET SDK) gerektirmez. System.Net.Sockets
    TcpListener ile HTTP/1.1 dinler ve ProbeApi.ps1 dispatcher'ina delege eder.

    Modlar:
      Listen    - on planda dinle (varsayilan)
      Install   - token + config + scheduled task + (opsiyonel) firewall, sonra baslat
      Uninstall - task ve process durdur
      Status    - dinleme / task durumu

.PARAMETER Mode
    Listen | Install | Uninstall | Status

.PARAMETER Port
    TCP port. Varsayilan 8444 (Guacamole 8443 ile carpismaz).

.PARAMETER Token
    Bearer token. Bos birakilirsa config / env / yeni uretilen token kullanilir.

.PARAMETER BindAddress
    Dinlenecek adres. Varsayilan 0.0.0.0

.EXAMPLE
    .\Start-ProbeApiHost.ps1 -Mode Install
    .\Start-ProbeApiHost.ps1 -Mode Listen -Port 8444
    .\Start-ProbeApiHost.ps1 -Mode Status

.NOTES
    Author  : Rdp Virtual Box App
    Version : 1.1.5
#>
[CmdletBinding()]
param(
    [ValidateSet('Listen', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Listen',

    [ValidateRange(1, 65535)]
    [int]$Port = 8444,

    [ValidateRange(1, 65535)]
    [int]$WebPort = 8001,

    [string]$Token,

    [string]$BindAddress = '0.0.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WindowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:TaskName    = 'RdpVirtualBoxApp-ProbeApi'
$script:PidFile     = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\probe-api.pid'
$script:LogFile     = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs\probe-api.log'
$script:StopFile    = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\probe-api.stop'

. (Join-Path $PSScriptRoot 'ProbeApi.ps1')

function Write-ProbeHostLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
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
    if ($Level -eq 'ERROR') {
        Write-Information -MessageData $line -InformationAction Continue
    }
}

function Test-ProbeHostIsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BindIpAddress {
    param([string]$Bind)
    if ([string]::IsNullOrWhiteSpace($Bind) -or $Bind -eq '0.0.0.0' -or $Bind -eq '*') {
        return [System.Net.IPAddress]::Any
    }
    if ($Bind -eq '127.0.0.1' -or $Bind -eq 'localhost') {
        return [System.Net.IPAddress]::Loopback
    }
    return [System.Net.IPAddress]::Parse($Bind)
}

function ConvertFrom-HttpRequestBuffer {
    param([byte[]]$Bytes, [int]$Length)

    $text = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $Length)
    $headerEnd = $text.IndexOf("`r`n`r`n")
    if ($headerEnd -lt 0) { $headerEnd = $text.IndexOf("`n`n") }
    if ($headerEnd -lt 0) { throw 'Incomplete HTTP headers' }

    $headerBlock = $text.Substring(0, $headerEnd)
    $lines = $headerBlock -split "`r?`n"
    if ($lines.Count -lt 1) { throw 'Empty request' }

    $parts = $lines[0] -split ' ', 3
    $method = $parts[0]
    $rawUrl = if ($parts.Count -gt 1) { $parts[1] } else { '/' }

    $headers = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $colon = $line.IndexOf(':')
        if ($colon -lt 1) { continue }
        $name  = $line.Substring(0, $colon).Trim()
        $value = $line.Substring($colon + 1).Trim()
        $headers[$name] = $value
    }

    $path = $rawUrl
    $query = @{}
    $qPos = $rawUrl.IndexOf('?')
    if ($qPos -ge 0) {
        $path  = $rawUrl.Substring(0, $qPos)
        $query = ConvertFrom-QueryString -RawQuery $rawUrl.Substring($qPos)
    }

    $sep = 4
    if ($text.IndexOf("`r`n`r`n") -lt 0) { $sep = 2 }
    $body = ''
    $bodyStart = $headerEnd + $sep
    if ($bodyStart -lt $Length) {
        $body = [System.Text.Encoding]::UTF8.GetString($Bytes, $bodyStart, $Length - $bodyStart)
    }

    return [pscustomobject]@{
        Method  = $method
        Path    = $path
        RawUrl  = $rawUrl
        Headers = $headers
        Query   = $query
        Body    = $body
    }
}

function Send-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [hashtable]$Response
    )

    $status = [int]$Response.status
    if ($status -le 0) { $status = 200 }
    $reason = switch ($status) {
        200 { 'OK' }
        204 { 'No Content' }
        400 { 'Bad Request' }
        401 { 'Unauthorized' }
        403 { 'Forbidden' }
        404 { 'Not Found' }
        405 { 'Method Not Allowed' }
        500 { 'Internal Server Error' }
        default { 'OK' }
    }

    $bodyText = [string]$Response.body
    if ($null -eq $bodyText) { $bodyText = '' }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $status $reason`r`n")
    [void]$sb.Append("Server: RdpVirtualBoxApp-ProbeApi/$($Script:ProbeApiVersion)`r`n")
    [void]$sb.Append("Connection: close`r`n")
    [void]$sb.Append("Content-Length: $($bodyBytes.Length)`r`n")

    if ($Response.headers) {
        foreach ($k in $Response.headers.Keys) {
            if ($k -eq 'Content-Length') { continue }
            [void]$sb.Append(('{0}: {1}' -f $k, $Response.headers[$k]))
            [void]$sb.Append("`r`n")
        }
    } else {
        [void]$sb.Append("Content-Type: application/json; charset=utf-8`r`n")
    }
    [void]$sb.Append("`r`n")

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($bodyBytes.Length -gt 0 -and $status -ne 204) {
        $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
    $Stream.Flush()
}

function Invoke-ProbeClientSession {
    param([System.Net.Sockets.TcpClient]$Client)

    $stream = $null
    try {
        $stream = $Client.GetStream()
        $stream.ReadTimeout  = 15000
        $stream.WriteTimeout = 15000

        $buffer = New-Object byte[] 8192
        $ms = New-Object System.IO.MemoryStream
        do {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $ms.Write($buffer, 0, $read)
            $soFar = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
            if ($soFar.Contains("`r`n`r`n") -or $soFar.Contains("`n`n")) { break }
            if ($ms.Length -gt 65536) { throw 'Request headers too large' }
        } while ($stream.DataAvailable)

        if ($ms.Length -eq 0) { return }

        $req = ConvertFrom-HttpRequestBuffer -Bytes $ms.ToArray() -Length $ms.Length
        $need = 0
        try {
            $cl = Get-HeaderValue -Headers $req.Headers -Name 'Content-Length'
            if ($cl -match '^\d+$') { $need = [int]$cl }
        } catch {}
        if ($need -gt 0) {
            $headerEnd = ([System.Text.Encoding]::ASCII.GetString($ms.ToArray())).IndexOf("`r`n`r`n")
            $sep = 4
            if ($headerEnd -lt 0) { $headerEnd = ([System.Text.Encoding]::ASCII.GetString($ms.ToArray())).IndexOf("`n`n"); $sep = 2 }
            $have = $ms.Length - ($headerEnd + $sep)
            while ($have -lt $need -and $ms.Length -lt 262144) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $ms.Write($buffer, 0, $read)
                $have += $read
            }
            $req = ConvertFrom-HttpRequestBuffer -Bytes $ms.ToArray() -Length $ms.Length
        }
        try {
            $req | Add-Member -NotePropertyName RemoteIp -NotePropertyValue $Client.Client.RemoteEndPoint.Address.ToString() -Force
        } catch {}
        $resp = Invoke-ProbeApiRequest -Request $req
        Send-HttpResponse -Stream $stream -Response $resp
    }
    catch {
        Write-ProbeHostLog -Level ERROR -Message "Request failed: $($_.Exception.Message)"
        if ($stream -and $stream.CanWrite) {
            try {
                $err = New-ProbeApiHttpResponse -Status 500 -Body @{ error = 'internal_error'; message = $_.Exception.Message }
                Send-HttpResponse -Stream $stream -Response $err
            } catch { }
        }
    }
    finally {
        if ($stream) { try { $stream.Dispose() } catch { } }
        try { $Client.Close() } catch { }
    }
}

function Start-ProbeApiListenLoop {
    param(
        [int]$ListenPort,
        [int]$PortalPort = 8001,
        [string]$Bind
    )

    $ip = Get-BindIpAddress -Bind $Bind
    $ports = New-Object System.Collections.Generic.List[int]
    [void]$ports.Add([int]$ListenPort)
    if ($PortalPort -ge 1 -and $PortalPort -ne $ListenPort) { [void]$ports.Add([int]$PortalPort) }

    $listeners = New-Object System.Collections.Generic.List[System.Net.Sockets.TcpListener]
    foreach ($p in $ports) {
        try {
            $listener = New-Object System.Net.Sockets.TcpListener $ip, $p
            $listener.Server.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
            $listener.Start()
            [void]$listeners.Add($listener)
            Write-ProbeHostLog -Message "Probe API listening on ${Bind}:${p} (pid=$PID)"
        } catch {
            Write-ProbeHostLog -Level WARN -Message "Port $p dinlenemedi: $($_.Exception.Message)"
        }
    }
    if ($listeners.Count -lt 1) {
        throw 'Hicbir HTTP portu acilamadi (8444 / web portu).'
    }

    $pidDir = Split-Path -Parent $script:PidFile
    if (-not (Test-Path -LiteralPath $pidDir)) {
        New-Item -ItemType Directory -Path $pidDir -Force | Out-Null
    }
    Set-Content -LiteralPath $script:PidFile -Value $PID -Encoding ASCII
    if (Test-Path -LiteralPath $script:StopFile) {
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
    }

    Write-Information -MessageData "Probe API dinleniyor: http://${Bind}:${ListenPort}/health  portal: http://${Bind}:${PortalPort}/download" -InformationAction Continue

    try {
        while ($true) {
            if (Test-Path -LiteralPath $script:StopFile) {
                Write-ProbeHostLog -Message 'Stop file detected, shutting down.'
                break
            }
            $accepted = $false
            foreach ($listener in $listeners) {
                if ($listener.Pending()) {
                    $client = $listener.AcceptTcpClient()
                    Invoke-ProbeClientSession -Client $client
                    $accepted = $true
                }
            }
            if (-not $accepted) { Start-Sleep -Milliseconds 80 }
        }
    }
    finally {
        foreach ($listener in $listeners) {
            try { $listener.Stop() } catch { }
        }
        Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        Write-ProbeHostLog -Message 'Probe API stopped.'
    }
}

function Initialize-ProbeApiRuntimeConfig {
    param(
        [int]$ListenPort,
        [int]$PortalPort = 8001,
        [string]$ProvidedToken
    )

    $cfg = Get-ProbeApiConfig
    $cfg.port = $ListenPort
    $cfg.webPort = $PortalPort
    $cfg.enabled = $true
    $cfg.bind = $BindAddress

    if (-not [string]::IsNullOrWhiteSpace($ProvidedToken)) {
        $cfg.token = $ProvidedToken
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$cfg.token)) {
        $cfg.token = New-ProbeApiToken
    }

    Save-ProbeApiConfig -Config $cfg
    $env:RDPVB_PROBE_TOKEN = [string]$cfg.token
    return $cfg
}

function Get-ProbeHostListenScriptPath {
    if ($PSCommandPath) { return $PSCommandPath }
    return $MyInvocation.MyCommand.Path
}

function Install-ProbeApiScheduledTask {
    param(
        [string]$HostScript,
        [int]$ListenPort,
        [int]$PortalPort = 8001
    )

    if (-not (Get-Command -Name 'Register-ScheduledTask' -ErrorAction SilentlyContinue)) {
        throw 'ScheduledTasks module is not available.'
    }

    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode Listen -Port {1} -WebPort {2}' -f $HostScript, $ListenPort, $PortalPort
    $action = New-ScheduledTaskAction -Execute $script:WindowsPowerShell -Argument $arg -WorkingDirectory (Split-Path -Parent $HostScript)
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

    $principal = $null
    if (Test-ProbeHostIsAdmin) {
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    }

    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-ProbeHostLog -Message "Scheduled task '$($script:TaskName)' registered."
}

function Start-ProbeApiBackgroundProcess {
    param(
        [string]$HostScript,
        [int]$ListenPort,
        [int]$PortalPort = 8001
    )

    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode Listen -Port {1} -WebPort {2}' -f $HostScript, $ListenPort, $PortalPort
    $p = Start-Process -FilePath $script:WindowsPowerShell -ArgumentList $arg -WorkingDirectory (Split-Path -Parent $HostScript) -WindowStyle Hidden -PassThru
    Write-ProbeHostLog -Message "Background host started pid=$($p.Id)"
    return $p
}

function Stop-ProbeApiHostProcesses {
    try {
        New-Item -ItemType File -Path $script:StopFile -Force | Out-Null
        Start-Sleep -Milliseconds 400
    } catch { }

    if (Test-Path -LiteralPath $script:PidFile) {
        $oldPid = 0
        try { $oldPid = [int](Get-Content -LiteralPath $script:PidFile -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { }
        if ($oldPid -gt 0) {
            try { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue } catch { }
        }
        Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*Start-ProbeApiHost.ps1*' -and $_.ProcessId -ne $PID } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }

    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($task) {
        try { Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue } catch { }
    }
}

function Get-ProbeApiHostStatus {
    $listening = Test-LocalTcpPortOpen -Port $Port
    $cfg = Get-ProbeApiConfig
    $pidVal = $null
    if (Test-Path -LiteralPath $script:PidFile) {
        try {
            $rawPid = Get-Content -LiteralPath $script:PidFile -TotalCount 1 -ErrorAction SilentlyContinue
            if ($rawPid) { $pidVal = [string]$rawPid }
        } catch { }
    }
    $taskState = 'Missing'
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($task) { $taskState = [string]$task.State }
    } catch { }

    return [pscustomobject]@{
        listening       = [bool]$listening
        port            = [int]$Port
        pid             = $pidVal
        taskName        = [string]$script:TaskName
        taskState       = $taskState
        configPath      = [string](Get-ProbeApiConfigPath)
        tokenConfigured = [bool](-not [string]::IsNullOrWhiteSpace([string]$cfg.token))
        healthUrl       = "http://127.0.0.1:${Port}/health"
        probeUrl        = "http://127.0.0.1:${Port}/probe/api/probe"
        isAdmin         = [bool](Test-ProbeHostIsAdmin)
    }
}

function Install-ProbeApiHost {
    param([int]$ListenPort, [int]$PortalPort = 8001, [string]$ProvidedToken)

    $cfg = Initialize-ProbeApiRuntimeConfig -ListenPort $ListenPort -PortalPort $PortalPort -ProvidedToken $ProvidedToken
    $hostScript = Get-ProbeHostListenScriptPath

    Stop-ProbeApiHostProcesses
    $waited = 0
    while ((Test-LocalTcpPortOpen -Port $ListenPort) -and $waited -lt 20) {
        Start-Sleep -Milliseconds 250
        $waited++
    }

    $fwOk = $false
    try {
        foreach ($p in @($ListenPort, $PortalPort) | Select-Object -Unique) {
            $ruleName = "RdpVirtualBoxApp - Probe API $p"
            $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                $null = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -Profile Any -Enabled True -Description 'Rdp Virtual Box App Probe / download portal'
            }
        }
        $fwOk = $true
    } catch {
        Write-ProbeHostLog -Level WARN -Message "Firewall kurali eklenemedi (yonetici gerekebilir): $($_.Exception.Message)"
    }

    try {
        $manifest = Get-LiveServerManifest
        $manifestPath = Get-ProbeManifestPath
        $manifestDir = Split-Path -Parent $manifestPath
        if (-not (Test-Path -LiteralPath $manifestDir)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($manifestPath, (ConvertTo-ProbeJson -InputObject $manifest), $utf8)
        Write-ProbeHostLog -Message "Manifest yazildi: $manifestPath"
    } catch {
        Write-ProbeHostLog -Level WARN -Message "Manifest yazilamadi: $($_.Exception.Message)"
    }

    $taskOk = $false
    try {
        Install-ProbeApiScheduledTask -HostScript $hostScript -ListenPort $ListenPort -PortalPort $PortalPort
        $taskOk = $true
        try { Start-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop } catch {
            Write-ProbeHostLog -Level WARN -Message "Scheduled task start failed: $($_.Exception.Message)"
        }
    } catch {
        Write-ProbeHostLog -Level WARN -Message "Scheduled task kaydedilemedi: $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds 400
    if (-not (Test-LocalTcpPortOpen -Port $ListenPort)) {
        $null = Start-ProbeApiBackgroundProcess -HostScript $hostScript -ListenPort $ListenPort -PortalPort $PortalPort
        Start-Sleep -Milliseconds 1500
    }

    $status = Get-ProbeApiHostStatus
    return [pscustomobject]@{
        installed     = $true
        listening     = [bool]$status.listening
        port          = $ListenPort
        webPort       = $PortalPort
        downloadUrl   = "http://127.0.0.1:${PortalPort}/download"
        firewall      = $fwOk
        scheduledTask = $taskOk
        token         = [string]$cfg.token
        healthUrl     = $status.healthUrl
        probeUrl      = $status.probeUrl
        manifestUrl   = "http://127.0.0.1:${ListenPort}/api/manifest"
        configPath    = $status.configPath
        isAdmin       = $status.isAdmin
    }
}

function Uninstall-ProbeApiHost {
    Stop-ProbeApiHostProcesses
    try { Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    Write-ProbeHostLog -Message 'Probe API uninstalled (process + task).'
    return [pscustomobject]@{ uninstalled = $true }
}

switch ($Mode) {
    'Install' {
        $result = Install-ProbeApiHost -ListenPort $Port -PortalPort $WebPort -ProvidedToken $Token
        $result | ConvertTo-Json -Depth 6
    }
    'Uninstall' {
        $result = Uninstall-ProbeApiHost
        $result | ConvertTo-Json -Depth 4
    }
    'Status' {
        $result = Get-ProbeApiHostStatus
        $result | ConvertTo-Json -Depth 6
    }
    default {
        $cfg = Initialize-ProbeApiRuntimeConfig -ListenPort $Port -PortalPort $WebPort -ProvidedToken $Token
        Start-ProbeApiListenLoop -ListenPort $Port -PortalPort $WebPort -Bind $BindAddress
    }
}
