#requires -Version 5.1
<#
.SYNOPSIS
    Sunucu tarafi SQL Bridge: yerel SQL Server'i Probe API CONNECT tuneli ile
    istemcilere "localhost" gibi sunar.

.DESCRIPTION
    SQL TCP portunu (varsayilan 1433) internete acmaz. Istemci
    CONNECT /sql-bridge HTTP istegi ile Probe API (8444) uzerinden tüneller;
    sunucu tarafinda trafik 127.0.0.1:<sqlPort>'a iletilir.

    Modlar:
      Status   - yapilandirma + SQL dinleme durumu (JSON)
      Install  - sql-bridge.json yazar, SQL TCP algilar, (opsiyonel) TCP etkinlestirir
      Enable   - enabled=true
      Disable  - enabled=false

.NOTES
    Author  : Rdp Virtual Box App
    Module  : server/SqlBridge.ps1
    Version : 1.1.6
#>
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install', 'Enable', 'Disable')]
    [string]$Mode = 'Status',

    [ValidateRange(1, 65535)]
    [int]$SqlPort = 0,

    [string]$SqlHost = '127.0.0.1',

    [switch]$EnableTcpIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SqlBridgeConfigName = 'sql-bridge.json'
$script:SqlBridgeLogFile    = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs\sql-bridge.log'

function Write-SqlBridgeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path -Parent $script:SqlBridgeLogFile
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:SqlBridgeLogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Verbose $line
}

function Get-SqlBridgeConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path $env:ProgramData "RdpVirtualBoxApp\Config\$($script:SqlBridgeConfigName)")
}

function Get-SqlBridgeDefaultConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return [ordered]@{
        version         = '1.0'
        enabled         = $false
        sqlHost         = '127.0.0.1'
        sqlPort         = 1433
        requireBearer   = $true
        allowDirectLan  = $false
        preferPublicIp  = $true
        probePort       = 8444
        description     = 'Probe API CONNECT /sql-bridge -> yerel SQL. Public IP uzerinden 8444; SQL 1433 internete acilmaz.'
        updatedAt       = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-SqlBridgeEndpointIps {
    <#
    .SYNOPSIS
        Sunucu adi (hostname/FQDN) + public / LAN IP'lerini okur.
        Istemci tüneli icin bunlardan HERHANGI BIRI yazilabilir.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $publicIp = ''
    $lanIp = ''
    $vpnIp = ''
    $serverName = $env:COMPUTERNAME
    $fqdn = ''
    $probePort = 8444

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.DNSHostName) { $serverName = [string]$cs.DNSHostName }
        if ($cs.Domain -and $cs.Domain -ne 'WORKGROUP' -and $serverName -notlike "*.*") {
            $fqdn = '{0}.{1}' -f $serverName, $cs.Domain
        } elseif ($serverName -like '*.*') {
            $fqdn = $serverName
        }
    } catch {
        try {
            $fqdn = [System.Net.Dns]::GetHostEntry('localhost').HostName
        } catch { }
    }

    $cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
    foreach ($name in @('customers.json', 'client-endpoints.json', 'probe-api.json')) {
        $path = Join-Path $cfgDir $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { continue }

        if ($name -eq 'customers.json') {
            $list = @()
            if ($obj.PSObject.Properties['customers'] -and $obj.customers) { $list = @($obj.customers) }
            $pick = $list | Where-Object {
                $id = if ($_.PSObject.Properties['id']) { [string]$_.id } else { '' }
                $id -eq 'default' -or $id -eq 'varsayilan'
            } | Select-Object -First 1
            if (-not $pick -and $list.Count -gt 0) { $pick = $list[0] }
            if ($pick) {
                if ($pick.PSObject.Properties['publicIp'] -and $pick.publicIp) { $publicIp = [string]$pick.publicIp }
                if ($pick.PSObject.Properties['lanIp'] -and $pick.lanIp) { $lanIp = [string]$pick.lanIp }
                if ($pick.PSObject.Properties['vpnIp'] -and $pick.vpnIp) { $vpnIp = [string]$pick.vpnIp }
                if ($pick.PSObject.Properties['hostname'] -and $pick.hostname) { $serverName = [string]$pick.hostname }
                if ($pick.PSObject.Properties['fqdn'] -and $pick.fqdn) { $fqdn = [string]$pick.fqdn }
            }
        }
        elseif ($name -eq 'client-endpoints.json') {
            if (-not $publicIp -and $obj.PSObject.Properties['public'] -and $obj.public) { $publicIp = [string]$obj.public }
            if (-not $lanIp -and $obj.PSObject.Properties['lan'] -and $obj.lan) { $lanIp = [string]$obj.lan }
            if (-not $vpnIp -and $obj.PSObject.Properties['vpn'] -and $obj.vpn) { $vpnIp = [string]$obj.vpn }
            if ($obj.PSObject.Properties['hostname'] -and $obj.hostname) { $serverName = [string]$obj.hostname }
            if ($obj.PSObject.Properties['fqdn'] -and $obj.fqdn) { $fqdn = [string]$obj.fqdn }
            if ($obj.PSObject.Properties['probe'] -and $obj.probe) {
                try { $probePort = [int]$obj.probe } catch { }
            }
        }
        elseif ($name -eq 'probe-api.json') {
            if ($obj.PSObject.Properties['port'] -and $obj.port) {
                try { $probePort = [int]$obj.port } catch { }
            }
        }
    }

    # Canli tespit (Get-PublicIpv4 ProbeApi'den gelmis olabilir)
    if ([string]::IsNullOrWhiteSpace($publicIp) -and (Get-Command -Name 'Get-PublicIpv4' -ErrorAction SilentlyContinue)) {
        try {
            $detected = Get-PublicIpv4
            if ($detected) { $publicIp = [string]$detected }
        } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($lanIp) -and (Get-Command -Name 'Get-LocalPrimaryIpv4' -ErrorAction SilentlyContinue)) {
        try {
            $lan = Get-LocalPrimaryIpv4
            if ($lan) { $lanIp = [string]$lan }
        } catch { }
    }

    # Istemci bunlardan herhangi birini yazabilir
    $acceptHosts = New-Object System.Collections.Generic.List[string]
    foreach ($h in @($serverName, $fqdn, $publicIp, $lanIp, $vpnIp)) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        $t = $h.Trim()
        if (-not $acceptHosts.Contains($t)) { [void]$acceptHosts.Add($t) }
    }

    $preferred = ''
    if (-not [string]::IsNullOrWhiteSpace($publicIp)) { $preferred = $publicIp }
    elseif (-not [string]::IsNullOrWhiteSpace($fqdn)) { $preferred = $fqdn }
    elseif (-not [string]::IsNullOrWhiteSpace($serverName)) { $preferred = $serverName }
    elseif (-not [string]::IsNullOrWhiteSpace($lanIp)) { $preferred = $lanIp }
    elseif (-not [string]::IsNullOrWhiteSpace($vpnIp)) { $preferred = $vpnIp }

    return [ordered]@{
        serverName    = $serverName
        fqdn          = $fqdn
        publicIp      = $publicIp
        lanIp         = $lanIp
        vpnIp         = $vpnIp
        acceptHosts   = @($acceptHosts.ToArray())
        preferredHost = $preferred
        probePort     = $probePort
        hasPublicIp   = (-not [string]::IsNullOrWhiteSpace($publicIp))
        hasServerName = (-not [string]::IsNullOrWhiteSpace($serverName))
    }
}

function Get-SqlBridgeConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $path = Get-SqlBridgeConfigPath
    $cfg = Get-SqlBridgeDefaultConfig
    if (-not (Test-Path -LiteralPath $path)) { return $cfg }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) {
            $cfg[$p.Name] = $p.Value
        }
    } catch {
        Write-SqlBridgeLog -Level WARN -Message "Config okunamadi, varsayilan kullaniliyor: $($_.Exception.Message)"
    }
    return $cfg
}

function Save-SqlBridgeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Config
    )

    $path = Get-SqlBridgeConfigPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Config['updatedAt'] = (Get-Date).ToUniversalTime().ToString('o')
    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    Write-SqlBridgeLog -Message "Config yazildi: $path"
}

function Test-LocalTcpPortListening {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [int]$TimeoutMs = 800
    )

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch { } }
    }
}

function Find-SqlServerTcpPort {
    <#
    .SYNOPSIS
        Yerel SQL Server TCP portunu tahmin eder (registry + 1433 dinleme).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $candidates = New-Object System.Collections.Generic.List[int]
    [void]$candidates.Add(1433)

    $instanceRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    )

    foreach ($root in $instanceRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $root -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match '^PS') { continue }
                $instanceId = [string]$p.Value
                if ([string]::IsNullOrWhiteSpace($instanceId)) { continue }
                $tcpKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
                if (-not (Test-Path -LiteralPath $tcpKey)) {
                    $tcpKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
                }
                if (-not (Test-Path -LiteralPath $tcpKey)) { continue }
                $tcp = Get-ItemProperty -LiteralPath $tcpKey -ErrorAction SilentlyContinue
                foreach ($name in @('TcpPort', 'TcpDynamicPorts')) {
                    $val = [string]$tcp.$name
                    if ($val -match '^\d+$') {
                        $n = [int]$val
                        if ($n -ge 1 -and $n -le 65535 -and -not $candidates.Contains($n)) {
                            [void]$candidates.Add($n)
                        }
                    } elseif ($val -match ',') {
                        foreach ($part in ($val -split ',')) {
                            if ($part -match '^\d+$') {
                                $n = [int]$part
                                if ($n -ge 1 -and $n -le 65535 -and -not $candidates.Contains($n)) {
                                    [void]$candidates.Add($n)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            Write-SqlBridgeLog -Level DEBUG -Message "Instance registry okunamadi: $($_.Exception.Message)"
        }
    }

    $listening = New-Object System.Collections.Generic.List[int]
    foreach ($p in $candidates) {
        if (Test-LocalTcpPortListening -HostName '127.0.0.1' -Port $p) {
            [void]$listening.Add($p)
        }
    }

    $chosen = if ($listening.Count -gt 0) { [int]$listening[0] } else { 1433 }
    return [ordered]@{
        candidates = @($candidates.ToArray())
        listening  = @($listening.ToArray())
        port       = $chosen
        reachable  = ($listening.Count -gt 0)
    }
}

function Get-SqlBridgeStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $cfg = Get-SqlBridgeConfig
    $hostName = [string]$cfg.sqlHost
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = '127.0.0.1' }
    $port = 1433
    try { $port = [int]$cfg.sqlPort } catch { $port = 1433 }
    if ($port -lt 1 -or $port -gt 65535) { $port = 1433 }

    $sqlOk = Test-LocalTcpPortListening -HostName $hostName -Port $port
    $discovery = Find-SqlServerTcpPort
    $eps = Get-SqlBridgeEndpointIps

    $probePort = 8444
    try {
        if ($cfg.probePort) { $probePort = [int]$cfg.probePort }
        elseif ($eps.probePort) { $probePort = [int]$eps.probePort }
    } catch { $probePort = 8444 }

    $preferPublic = $true
    if ($cfg.Contains('preferPublicIp')) { $preferPublic = [bool]$cfg.preferPublicIp }
    $clientProbeHost = ''
    if ($preferPublic -and $eps.hasPublicIp) { $clientProbeHost = [string]$eps.publicIp }
    elseif ($eps.preferredHost) { $clientProbeHost = [string]$eps.preferredHost }

    return [ordered]@{
        enabled          = [bool]$cfg.enabled
        sqlHost          = $hostName
        sqlPort          = $port
        sqlReachable     = [bool]$sqlOk
        requireBearer    = [bool]$cfg.requireBearer
        allowDirectLan   = [bool]$cfg.allowDirectLan
        preferPublicIp   = $preferPublic
        tunnelPath       = '/sql-bridge'
        tunnelMethod     = 'CONNECT'
        # Istemci SSMS tarafi her zaman localhost; tünel ucu public/LAN Probe API
        clientHint       = '127.0.0.1,{0}' -f $port
        connectionString = 'Server=127.0.0.1,{0};Trusted_Connection=False;Encrypt=False;' -f $port
        probe = [ordered]@{
            port          = $probePort
            serverName    = [string]$eps.serverName
            fqdn          = [string]$eps.fqdn
            publicHost    = [string]$eps.publicIp
            lanHost       = [string]$eps.lanIp
            vpnHost       = [string]$eps.vpnIp
            acceptHosts   = @($eps.acceptHosts)
            preferredHost = $clientProbeHost
            hasPublicIp   = [bool]$eps.hasPublicIp
            hasServerName = [bool]$eps.hasServerName
            connectHint   = 'Istemci sihirbazina sunucu adi VEYA public IP yazin; CONNECT /sql-bridge ayni Probe portuna gider.'
            examples      = @(
                $(if ($eps.serverName) { "{0}:{1}" -f $eps.serverName, $probePort } else { $null })
                $(if ($eps.fqdn) { "{0}:{1}" -f $eps.fqdn, $probePort } else { $null })
                $(if ($eps.publicIp) { "{0}:{1}" -f $eps.publicIp, $probePort } else { $null })
            ) | Where-Object { $_ }
        }
        discovery        = $discovery
        configPath       = (Get-SqlBridgeConfigPath)
        updatedAt        = [string]$cfg.updatedAt
        note             = 'SQL TCP (1433) internete acilmaz. Public IP yalnizca Probe API (8444) tüneli icindir.'
    }
}

function Install-SqlBridge {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateRange(1, 65535)]
        [int]$SqlPort = 0,
        [string]$SqlHost = '127.0.0.1',
        [switch]$EnableTcpIfNeeded
    )

    Write-SqlBridgeLog -Message 'SQL Bridge kurulumu basliyor.'
    $cfg = Get-SqlBridgeConfig
    $discovery = Find-SqlServerTcpPort

    if ($SqlPort -ge 1) {
        $cfg.sqlPort = $SqlPort
    } elseif ($discovery.reachable) {
        $cfg.sqlPort = [int]$discovery.port
    } else {
        $cfg.sqlPort = 1433
    }

    if (-not [string]::IsNullOrWhiteSpace($SqlHost)) {
        $cfg.sqlHost = $SqlHost
    }

    $cfg.enabled = $true
    $cfg.requireBearer = $true
    $cfg.allowDirectLan = $false
    $cfg.preferPublicIp = $true

    $eps = Get-SqlBridgeEndpointIps
    if ($eps.probePort -ge 1) { $cfg.probePort = [int]$eps.probePort }
    if ($eps.hasPublicIp) {
        Write-SqlBridgeLog -Message ("Public IP bulundu; istemci tüneli bu adrese yonlendirilecek: {0}:{1}" -f $eps.publicIp, $cfg.probePort)
    } else {
        Write-SqlBridgeLog -Level WARN -Message 'Public IP kaydi yok (customers.json / client-endpoints.json). Istemci sihirbazindaki sunucu IP kullanilir.'
    }

    # SQL TCP etkinlestirme (opsiyonel): yalnizca registry bayragi; SQL restart istemezsek
    # sadece mevcut dinleyen portu kullaniriz. EnableTcpIfNeeded ile TCP/IP Enabled=1 yazilir.
    if ($EnableTcpIfNeeded) {
        try {
            $roots = @(
                'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server'
            )
            foreach ($root in $roots) {
                if (-not (Test-Path -LiteralPath $root)) { continue }
                Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                    $tcpPath = Join-Path $_.PSPath 'MSSQLServer\SuperSocketNetLib\Tcp'
                    if (Test-Path -LiteralPath $tcpPath) {
                        Set-ItemProperty -LiteralPath $tcpPath -Name Enabled -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        Write-SqlBridgeLog -Message "TCP Enabled=1 yazildi: $tcpPath"
                    }
                }
            }
        } catch {
            Write-SqlBridgeLog -Level WARN -Message "SQL TCP etkinlestirme atladi: $($_.Exception.Message)"
        }
    }

    Save-SqlBridgeConfig -Config $cfg
    $status = Get-SqlBridgeStatus
    Write-SqlBridgeLog -Message ("Kurulum bitti. enabled={0} sql={1}:{2} reachable={3}" -f $status.enabled, $status.sqlHost, $status.sqlPort, $status.sqlReachable)
    return $status
}

function Set-SqlBridgeEnabled {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][bool]$Enabled)

    $cfg = Get-SqlBridgeConfig
    $cfg.enabled = [bool]$Enabled
    Save-SqlBridgeConfig -Config $cfg
    return (Get-SqlBridgeStatus)
}

function Test-SqlBridgeConnectAllowed {
    <#
    .SYNOPSIS
        CONNECT /sql-bridge isteginin kabul edilip edilmeyecegini dogrular.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ProvidedToken
    )

    $status = Get-SqlBridgeStatus
    if (-not $status.enabled) {
        return [ordered]@{ ok = $false; status = 403; error = 'sql_bridge_disabled'; detail = $status }
    }
    if (-not $status.sqlReachable) {
        return [ordered]@{ ok = $false; status = 503; error = 'sql_not_reachable'; detail = $status }
    }

    if ($status.requireBearer) {
        $probeCfgPath = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\probe-api.json'
        $expected = ''
        if ($env:RDPVB_PROBE_TOKEN) { $expected = [string]$env:RDPVB_PROBE_TOKEN }
        elseif (Test-Path -LiteralPath $probeCfgPath) {
            try {
                $pc = Get-Content -LiteralPath $probeCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($pc.token) { $expected = [string]$pc.token }
            } catch { }
        }
        if (-not [string]::IsNullOrWhiteSpace($expected)) {
            if ([string]::IsNullOrWhiteSpace($ProvidedToken) -or
                -not [string]::Equals($ProvidedToken, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [ordered]@{ ok = $false; status = 401; error = 'unauthorized'; detail = $status }
            }
        }
    }

    return [ordered]@{
        ok       = $true
        status   = 200
        sqlHost  = [string]$status.sqlHost
        sqlPort  = [int]$status.sqlPort
        detail   = $status
    }
}

# ---------------------------------------------------------------------------
# CLI entry (script dogrudan calistirildiginda)
# ---------------------------------------------------------------------------
$isDirect = $MyInvocation.InvocationName -ne '.' -and
            $MyInvocation.Line -notmatch '^\s*\.\s+' -and
            $PSCommandPath -and
            $MyInvocation.MyCommand.Path -and
            ($MyInvocation.MyCommand.Path -eq $PSCommandPath)

if ($isDirect -and $Host.Name -eq 'ConsoleHost') {
    try {
        switch ($Mode) {
            'Status' {
                $s = Get-SqlBridgeStatus
                $s | ConvertTo-Json -Depth 6
            }
            'Install' {
                $argsHash = @{ }
                if ($SqlPort -ge 1) { $argsHash.SqlPort = $SqlPort }
                if ($SqlHost) { $argsHash.SqlHost = $SqlHost }
                if ($EnableTcpIfNeeded) { $argsHash.EnableTcpIfNeeded = $true }
                $s = Install-SqlBridge @argsHash
                $s | ConvertTo-Json -Depth 6
            }
            'Enable' {
                (Set-SqlBridgeEnabled -Enabled $true) | ConvertTo-Json -Depth 6
            }
            'Disable' {
                (Set-SqlBridgeEnabled -Enabled $false) | ConvertTo-Json -Depth 6
            }
        }
    } catch {
        Write-Error -ErrorRecord $_
        exit 1
    }
}
