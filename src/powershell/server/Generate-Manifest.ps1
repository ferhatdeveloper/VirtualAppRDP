#requires -Version 5.1
<#
.SYNOPSIS
    Generates a server manifest JSON file consumed by the client-side
    SetupUI.ps1 wizard to populate the application list and connection
    settings without re-running remote discovery.

.DESCRIPTION
    The manifest is the data bridge between the server-side setup and the
    client-side installation. After the server has been configured with
    RDS roles, RemoteApps, certificates and (optionally) Apache
    Guacamole / Tailscale / Cloudflare tunnel, this script inspects the
    current state and writes a single JSON document to ProgramData.

    The client installer downloads / reads the manifest and uses it to
    populate the multi-app selection grid, the web URL shortcut and the
    credential manager target.

    Schema (manifestVersion 1.0.0):

        {
          "manifestVersion": "1.0.0",
          "generatedAt":     "2026-08-19T16:00:00Z",
          "server": {
            "fqdn":  "server.domain.local",
            "ip":    "192.168.0.106",
            "domain":"jber.local",
            "os":    "Windows Server 2019 Datacenter"
          },
          "connectionStrategies": {
            "direct":     { "enabled": true,  "port": 3389, "url": "192.168.0.106:3389" },
            "gateway":    { "enabled": false, "port": 443,  "url": null },
            "guacamole":  { "enabled": true,  "port": 8443, "url": "https://server:8443/guacamole" },
            "tailscale":  { "enabled": false, "url": null },
            "cloudflare": { "enabled": false, "url": null }
          },
          "webEndpoint": {
            "type": "Guacamole",
            "url":  "https://server:8443/guacamole"
          },
          "remoteApps": [
            {
              "alias":     "AppName",
              "name":      "App Display",
              "path":      "C:\Program Files\app.exe",
              "publisher": "Acme",
              "icon":      "C:\Program Files\app.exe"
            }
          ],
          "certificate": {
            "thumbprint": "ABC123...",
            "type":       "SelfSigned"
          }
        }

.PARAMETER OutputPath
    Destination path of the manifest file. Defaults to
    "$env:ProgramData\RdpVirtualBoxApp\Manifest\server-manifest.json".

.PARAMETER CollectionName
    Name of the RDS Session Collection that owns the RemoteApps.

.PARAMETER IncludeApps
    When set, the script queries Get-RDRemoteApp and includes every
    published RemoteApp in the manifest. Disabled by default so the
    script can also be exercised on hosts that do not host the RDS
    Session Host role (e.g. license servers).

.PARAMETER IncludeStrategies
    List of connection strategies to publish. Defaults to all five:
    Direct, Gateway, Guacamole, Tailscale, Cloudflare.

.PARAMETER IncludeWebEndpoint
    When set, the script probes RD Web Access and Apache Guacamole to
    decide which one is the active HTML5 endpoint and embeds the result
    in the "webEndpoint" object.

.PARAMETER ManifestVersion
    Override the manifest schema version. Defaults to "1.0.0".

.PARAMETER ServerIp
    Override the auto-detected server IP. Useful when the server has
    multiple NICs and the operator wants to pin a specific address.

.PARAMETER ServerFqdn
    Override the auto-detected FQDN.

.PARAMETER Domain
    Override the auto-detected AD domain.

.PARAMETER DirectPort
    Override the default RDP port (3389) used in the "direct" strategy.

.PARAMETER GatewayPort
    Override the default RD Gateway port (443) used in the "gateway"
    strategy.

.PARAMETER GuacamolePort
    Override the default Guacamole HTTPS port (8443) used in the
    "guacamole" strategy.

.PARAMETER GuacamolePath
    Override the default Guacamole URL path ("/guacamole").

.PARAMETER TailscaleHostname
    Optional FQDN assigned by Tailscale. When supplied, the "tailscale"
    strategy is marked as enabled and the URL is set to
    "https://<hostname>:3389".

.PARAMETER CloudflareHostname
    Optional public hostname routed through the Cloudflare Tunnel.
    When supplied, the "cloudflare" strategy is marked as enabled and
    the URL is set to "https://<hostname>".

.PARAMETER PassThru
    When set, the generated manifest object is written to the pipeline
    in addition to the file.

.EXAMPLE
    PS> .\Generate-Manifest.ps1 -IncludeApps -IncludeWebEndpoint

    Generates the manifest with RemoteApps and the web endpoint.

.EXAMPLE
    PS> .\Generate-Manifest.ps1 -OutputPath C:\share\server-manifest.json `
                               -TailscaleHostname server.tail-net.ts.net `
                               -CloudflareHostname rdp.example.com

    Enables Tailscale and Cloudflare strategies in the manifest, writes
    the file to a custom SMB share.

.NOTES
    Author : Rdp Virtual Box App - Build & Manifest agent
    Module  : src/powershell/server/Generate-Manifest.ps1
    Run on : Windows Server 2016/2019/2022 with elevated PowerShell 5.1+
             (PowerShell 7+ recommended for consistent JSON encoding).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $OutputPath = (Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Manifest\server-manifest.json'),

    [Parameter()]
    [string] $CollectionName = 'RdpVirtualBoxApp',

    [Parameter()]
    [switch] $IncludeApps,

    [Parameter()]
    [ValidateSet('Direct', 'Gateway', 'Guacamole', 'Tailscale', 'Cloudflare')]
    [string[]] $IncludeStrategies = @('Direct', 'Gateway', 'Guacamole', 'Tailscale', 'Cloudflare'),

    [Parameter()]
    [switch] $IncludeWebEndpoint,

    [Parameter()]
    [string] $ManifestVersion = '1.0.0',

    [Parameter()]
    [string] $ServerIp,

    [Parameter()]
    [string] $ServerFqdn,

    [Parameter()]
    [string] $Domain,

    [Parameter()]
    [int] $DirectPort = 3389,

    [Parameter()]
    [int] $GatewayPort = 443,

    [Parameter()]
    [int] $GuacamolePort = 8443,

    [Parameter()]
    [string] $GuacamolePath = '/guacamole',

    [Parameter()]
    [string] $TailscaleHostname,

    [Parameter()]
    [string] $CloudflareHostname,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$script:ManifestLogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\generate-manifest.log'

function Set-ManifestLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

# Backwards-compatible alias for PSScriptAnalyzer PSUseApprovedVerbs compliance
Set-Alias -Name Initialize-ManifestLog -Value Set-ManifestLog -Scope Global -Force

function Write-ManifestLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')] [string] $Level,
        [Parameter(Mandatory)] [string] $Message
    )

    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
        $line = "[$timestamp] [$Level] $Message"
        if ($script:ManifestLogPath -and (Test-Path -LiteralPath (Split-Path -Parent $script:ManifestLogPath))) {
            Add-Content -LiteralPath $script:ManifestLogPath -Value $line -Encoding UTF8
        }
    } catch {
        # Logging is best-effort.
    }

    switch ($Level) {
        'INFO'  { Write-Verbose $Message }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error   $Message }
        'DEBUG' { Write-Debug   $Message }
    }
}

Set-ManifestLog -Path $script:ManifestLogPath

# ---------------------------------------------------------------------------
# Server detection helpers
# ---------------------------------------------------------------------------
function Get-ServerDetection {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $result = [pscustomobject]@{
        Fqdn   = ''
        Ip     = ''
        Domain = ''
        Os     = ''
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os) {
            $caption = $os.Caption
            if ([string]::IsNullOrWhiteSpace($caption)) { $caption = $os.Name }
            $result.Os = ($caption -replace '\s+', ' ').Trim()
        }
    } catch {
        Write-ManifestLog -Level WARN -Message "Failed to read Win32_OperatingSystem: $($_.Exception.Message)"
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs) {
            $result.Fqdn = [string]$cs.DNSHostName
            if ([string]::IsNullOrWhiteSpace($result.Fqdn)) {
                $result.Fqdn = [string]$cs.Name
            }
            $result.Domain = [string]$cs.Domain
        }
    } catch {
        Write-ManifestLog -Level WARN -Message "Failed to read Win32_ComputerSystem: $($_.Exception.Message)"
    }

    if (-not $result.Fqdn) {
        try {
            $result.Fqdn = [System.Net.Dns]::GetHostEntry('').HostName
        } catch {
            Write-ManifestLog -Level WARN -Message "GetHostEntry failed: $($_.Exception.Message)"
        }
    }

    if (-not $result.Ip) {
        try {
            $hostEntry = [System.Net.Dns]::GetHostEntry($result.Fqdn)
            $ip = $hostEntry.AddressList |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not $_.IsIPv6LinkLocal } |
                Select-Object -First 1
            if ($ip) { $result.Ip = $ip.IPAddressToString }
        } catch {
            Write-ManifestLog -Level WARN -Message "Failed to resolve IP: $($_.Exception.Message)"
        }
    }

    if (-not $result.Ip) {
        try {
            $adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                Select-Object -First 1
            if ($adapter) { $result.Ip = $adapter.IPAddress }
        } catch {
            Write-ManifestLog -Level WARN -Message "Get-NetIPAddress failed: $($_.Exception.Message)"
        }
    }

    return $result
}

# ---------------------------------------------------------------------------
# RemoteApps discovery
# ---------------------------------------------------------------------------
function Get-RemoteAppEntries {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string] $Collection
    )

    if (-not (Get-Module -ListAvailable -Name RemoteDesktop)) {
        Write-ManifestLog -Level WARN -Message "RemoteDesktop module not available; skipping RemoteApp enumeration."
        return @()
    }

    try {
        Import-Module RemoteDesktop -ErrorAction Stop
    } catch {
        Write-ManifestLog -Level WARN -Message "Import-Module RemoteDesktop failed: $($_.Exception.Message)"
        return @()
    }

    try {
        $entries = Get-RDRemoteApp -CollectionName $Collection -ErrorAction Stop
    } catch {
        Write-ManifestLog -Level WARN -Message "Get-RDRemoteApp failed: $($_.Exception.Message)"
        return @()
    }

    if (-not $entries) { return @() }

    $result = foreach ($entry in $entries) {
        $path = ''
        $icon = $null
        $publisher = ''

        try {
            $path = [string]$entry.FilePath
        } catch { $path = '' }
        try {
            $icon = [string]$entry.IconPath
        } catch { $icon = $null }
        try {
            $publisher = [string]$entry.PublisherName
        } catch { $publisher = '' }

        if ([string]::IsNullOrWhiteSpace($icon) -and -not [string]::IsNullOrWhiteSpace($path)) {
            $icon = $path
        }

        [pscustomobject]@{
            alias     = if ($entry.PSObject.Properties.Match('Alias').Count) { [string]$entry.Alias } else { '' }
            name      = if ($entry.PSObject.Properties.Match('DisplayName').Count -and $entry.DisplayName) { [string]$entry.DisplayName } `
                        elseif ($entry.PSObject.Properties.Match('FriendlyName').Count) { [string]$entry.FriendlyName } `
                        else { '' }
            path      = $path
            publisher = $publisher
            icon      = $icon
        }
    }

    return @($result)
}

# ---------------------------------------------------------------------------
# Certificate discovery
# ---------------------------------------------------------------------------
function Get-ManifestCertificate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $empty = [pscustomobject]@{ thumbprint = $null; type = $null }

    $candidates = @()

    # Look for the cert currently bound to RDP-Tcp.
    try {
        $ts = Get-CimInstance -Namespace 'root\cimv2\TerminalServices' -ClassName 'Win32_TSGeneralSetting' -ErrorAction Stop
        foreach ($instance in $ts) {
            $hash = $instance.SSLCertificateSHA1Hash
            if ($hash) {
                $candidates += [pscustomobject]@{
                    Thumbprint = ($hash -replace '\s', '').ToUpper()
                    Source     = 'RDP-Tcp'
                }
            }
        }
    } catch {
        Write-ManifestLog -Level DEBUG -Message "Win32_TSGeneralSetting unavailable: $($_.Exception.Message)"
    }

    # Fallback: look at the Remote Desktop certificate store.
    if (-not $candidates -or $candidates.Count -eq 0) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Remote Desktop', 'LocalMachine')
            $store.Open('ReadOnly')
            $certs = $store.Certificates
            $store.Close()
            foreach ($c in $certs) {
                $candidates += [pscustomobject]@{
                    Thumbprint = $c.Thumbprint
                    Source     = 'RemoteDesktop-Store'
                }
            }
        } catch {
            Write-ManifestLog -Level DEBUG -Message "Remote Desktop store unavailable: $($_.Exception.Message)"
        }
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        return $empty
    }

    $first = $candidates[0]
    $type = 'CA'
    try {
        $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($first.Thumbprint)" -ErrorAction Stop
        if ($cert.Subject -eq $cert.Issuer) {
            $type = 'SelfSigned'
        }
    } catch {
        $type = 'Unknown'
    }

    return [pscustomobject]@{
        thumbprint = $first.Thumbprint
        type       = $type
    }
}

# ---------------------------------------------------------------------------
# Web endpoint detection
# ---------------------------------------------------------------------------
function Resolve-WebEndpoint {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $ServerHost,
        [Parameter(Mandatory)] [int]    $GuacamolePort,
        [Parameter(Mandatory)] [string] $GuacamolePath
    )

    # Probe RD Web Access first because it requires a CAL.
    $rdWebUrl = "https://$ServerHost/RDWeb/webclient"
    $rdWebAvailable = Test-ManifestUrl -Url $rdWebUrl

    if ($rdWebAvailable) {
        return [pscustomobject]@{
            type = 'RDWeb'
            url  = $rdWebUrl
        }
    }

    $guacUrl = "https://$ServerHost`:$GuacamolePort$GuacamolePath"
    $guacAvailable = Test-ManifestUrl -Url $guacUrl

    if ($guacAvailable) {
        return [pscustomobject]@{
            type = 'Guacamole'
            url  = $guacUrl
        }
    }

    return [pscustomobject]@{
        type = $null
        url  = $null
    }
}

function Test-ManifestUrl {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Url)

    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $request.Timeout = 3000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = 'RdpVirtualBoxApp/Generate-Manifest'
        # Self-signed certs are tolerated by the server probe; ignore them.
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        $response = $request.GetResponse()
        $code = [int]$response.StatusCode
        $response.Close()
        return ($code -lt 500)
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Strategy construction
# ---------------------------------------------------------------------------
function New-StrategyEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [bool]   $Enabled,
        [Parameter()]           [int]   $Port,
        [Parameter()]           [string]$Url
    )

    $entry = [ordered]@{
        enabled = $Enabled
        port    = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { $null }
        url     = if ($Url) { $Url } else { $null }
    }
    return [pscustomobject]$entry
}

function Resolve-ConnectionStrategies {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $ServerIp,
        [Parameter(Mandatory)] [string] $ServerFqdn,
        [Parameter(Mandatory)] [int]    $DirectPort,
        [Parameter(Mandatory)] [int]    $GatewayPort,
        [Parameter(Mandatory)] [int]    $GuacamolePort,
        [Parameter(Mandatory)] [string] $GuacamolePath,
        [Parameter()]           [string] $TailscaleHostname,
        [Parameter()]           [string] $CloudflareHostname,
        [Parameter(Mandatory)] [string[]] $IncludeStrategies
    )

    $include = @{ Direct = $false; Gateway = $false; Guacamole = $false; Tailscale = $false; Cloudflare = $false }
    foreach ($s in $IncludeStrategies) { $include[$s] = $true }

    $strategies = [ordered]@{}

    $strategies['direct'] = New-StrategyEntry -Enabled $true -Port $DirectPort -Url "$ServerIp`:$DirectPort"
    if (-not $include['Direct']) {
        $strategies['direct'].enabled = $false
    }

    $gatewayUrl = $null
    if ($ServerFqdn) {
        $gatewayUrl = "https://$ServerFqdn`:$GatewayPort"
    } elseif ($ServerIp) {
        $gatewayUrl = "https://$ServerIp`:$GatewayPort"
    }
    $strategies['gateway'] = New-StrategyEntry -Enabled $include['Gateway'] -Port $GatewayPort -Url $gatewayUrl

    $guacUrl = $null
    if ($ServerFqdn) {
        $guacUrl = "https://$ServerFqdn`:$GuacamolePort$GuacamolePath"
    } elseif ($ServerIp) {
        $guacUrl = "https://$ServerIp`:$GuacamolePort$GuacamolePath"
    }
    $strategies['guacamole'] = New-StrategyEntry -Enabled $include['Guacamole'] -Port $GuacamolePort -Url $guacUrl

    $tailscaleEnabled = $include['Tailscale'] -and -not [string]::IsNullOrWhiteSpace($TailscaleHostname)
    $tailscaleUrl = if ($tailscaleEnabled) { "https://$TailscaleHostname`:$DirectPort" } else { $null }
    $strategies['tailscale'] = New-StrategyEntry -Enabled $tailscaleEnabled -Url $tailscaleUrl

    $cloudflareEnabled = $include['Cloudflare'] -and -not [string]::IsNullOrWhiteSpace($CloudflareHostname)
    $cloudflareUrl = if ($cloudflareEnabled) { "https://$CloudflareHostname" } else { $null }
    $strategies['cloudflare'] = New-StrategyEntry -Enabled $cloudflareEnabled -Url $cloudflareUrl

    return [pscustomobject]$strategies
}

# ---------------------------------------------------------------------------
# Manifest persistence
# ---------------------------------------------------------------------------
function ConvertTo-ManifestJson {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Manifest)

    # ConvertTo-Json -Depth large enough to cover nested deployment descriptors.
    return $Manifest | ConvertTo-Json -Depth 10
}

function Write-ManifestToDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Json
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Json, $utf8)

    Write-ManifestLog -Level INFO -Message "Manifest written to $Path ($((Get-Item -LiteralPath $Path).Length) bytes)."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Write-ManifestLog -Level INFO -Message "Generate-Manifest started. OutputPath=$OutputPath"

    if (-not $OutputPath) {
        throw "OutputPath is required."
    }

    # Server identity
    $detection = Get-ServerDetection
    $fqdn   = if ($ServerFqdn) { $ServerFqdn } else { $detection.Fqdn }
    $ip     = if ($ServerIp)   { $ServerIp }   else { $detection.Ip }
    $domain = if ($Domain)     { $Domain }     else { $detection.Domain }
    $os     = $detection.Os

    if ([string]::IsNullOrWhiteSpace($ip) -and [string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Could not determine server identity. Pass -ServerIp / -ServerFqdn explicitly."
    }

    $serverBlock = [ordered]@{
        fqdn   = if ($fqdn) { $fqdn } else { $null }
        ip     = if ($ip)   { $ip }   else { $null }
        domain = if ($domain) { $domain } else { $null }
        os     = if ($os)   { $os }   else { $null }
    }

    # Connection strategies
    $strategies = Resolve-ConnectionStrategies `
        -ServerIp           $ip `
        -ServerFqdn         $fqdn `
        -DirectPort         $DirectPort `
        -GatewayPort        $GatewayPort `
        -GuacamolePort      $GuacamolePort `
        -GuacamolePath      $GuacamolePath `
        -TailscaleHostname  $TailscaleHostname `
        -CloudflareHostname $CloudflareHostname `
        -IncludeStrategies  $IncludeStrategies

    # Web endpoint
    $webEndpoint = $null
    if ($IncludeWebEndpoint) {
        $probeHost = if ($fqdn) { $fqdn } else { $ip }
        $webEndpoint = Resolve-WebEndpoint -ServerHost $probeHost -GuacamolePort $GuacamolePort -GuacamolePath $GuacamolePath
    } else {
        $webEndpoint = [pscustomobject]@{
            type = $null
            url  = $null
        }
    }

    # RemoteApps
    $remoteApps = @()
    if ($IncludeApps) {
        $remoteApps = Get-RemoteAppEntries -Collection $CollectionName
    }

    # Certificate
    $certificate = Get-ManifestCertificate

    # Build the manifest as an ordered PSCustomObject so the JSON keys are
    # ordered deterministically (helpful for diffing across regenerations).
    $manifest = [pscustomobject]([ordered]@{
        manifestVersion = $ManifestVersion
        generatedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        server          = [pscustomobject]$serverBlock
        connectionStrategies = $strategies
        webEndpoint     = $webEndpoint
        remoteApps      = $remoteApps
        certificate     = $certificate
    })

    $json = ConvertTo-ManifestJson -Manifest $manifest
    Write-ManifestToDisk -Path $OutputPath -Json $json

    Write-ManifestLog -Level INFO -Message "Generate-Manifest completed successfully."

    if ($PassThru) {
        return $manifest
    }
    return $manifest
}
catch {
    $message = "Generate-Manifest failed: $($_.Exception.Message)"
    Write-ManifestLog -Level ERROR -Message $message
    Write-Error $message
    throw
}

Export-ModuleMember -Function @(
    'Get-ServerDetection'
    'Get-RemoteAppEntries'
    'Get-ManifestCertificate'
    'Resolve-WebEndpoint'
    'Resolve-ConnectionStrategies'
    'ConvertTo-ManifestJson'
    'Write-ManifestToDisk'
)
