#requires -Version 5.1
<#
.SYNOPSIS
    Rdp Virtual Box App - Probe REST API (macOS / non-Windows clients).

.DESCRIPTION
    Windows istemcisi ServerProbe.ps1'i WinRM uzerinden cagirir. macOS
    istemcisinde WinRM olmadigi icin sunucuda bir HTTP/HTTPS endpoint'i
    barindirilir. Bu script iki sekilde kullanilir:

    A) IIS altinda barindirilan ASP.NET handler olarak
       (web.config + HttpModule; sade bu script logigidir)

    B) Bagimsiz Kestrel uzerinden kosan minimal API olarak
       (dotnet-hosted; bu durumda Invoke-ProbeApi.ps1 ile cagirilir)

    Endpoint formati:
        GET https://<server>:8443/probe/api/probe
        Authorization: Bearer <token>   (opsiyonel)

    JSON semasi, mevcut ServerProbe.ps1 ciktisiyla bire bir uyumludur.
    Bu sayede macOS Native Client (SwiftUI) JSON sema uyumu saglar.

.NOTES
    Author  : Rdp Virtual Box App - Server Agent S3
    Version : 1.0.0
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Sabitler
# ---------------------------------------------------------------------------

$Script:ProbeApiVersion  = '1.0.0'
$Script:DefaultProbePath = '/probe/api/probe'

# ---------------------------------------------------------------------------
# Token validation - macOS istemcisi Bearer token ile authenticate olur.
# Token environment variable ya da appsettings.json'dan okunur.
# ---------------------------------------------------------------------------
function Test-ProbeApiToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProvidedToken,

        [string]$ConfiguredToken = $env:RDPVB_PROBE_TOKEN
    )

    if ([string]::IsNullOrWhiteSpace($ConfiguredToken)) {
        # Token tanimlanmamis; auth devre disi (gelistirme kolayligi)
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($ProvidedToken)) { return $false }
    return -not [string]::Compare($ProvidedToken, $ConfiguredToken, [bool]$true) # case-insensitive
}

# ---------------------------------------------------------------------------
# ServerProbe.ps1'in "calistir ve JSON uret" kisminin sarmalayicisi.
# macOS istemcisi icin kullanilan ortak JSON semasi.
# ---------------------------------------------------------------------------
function Invoke-ProbeApi {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,

        [int]$ProbePort = 8443
    )

    try {
        # ServerProbe.ps1'in mevcut Get-ServerProbeResult fonksiyonunu cagir.
        # Bu fonksiyon Windows Server'da calisir ve WinRM/WMI ile tarama yapar.
        if (Get-Command -Name 'Get-ServerProbeResult' -ErrorAction SilentlyContinue) {
            $probe = Get-ServerProbeResult -ServerName $ServerName
        } else {
            # ServerProbe.ps1 dot-source edilmemis; fallback olarak inline tarama yap.
            $probe = @{
                server            = $ServerName
                components        = @{}
                webEndpoint       = @{ rdWebAvailable = $false; guacamoleAvailable = $false }
                existingRemoteApps = @()
                recommendations   = @()
                generatedAt       = (Get-Date).ToUniversalTime().ToString('o')
                _note             = 'ServerProbe.ps1 yuklenmedi; fallback JSON.'
            }
        }

        # JSON sema uyumu (macOS Swift model ile ayni):
        # - status: ok | warning | error | unknown
        # - components: hashtable<string, {status, value, details[]}>
        return $probe
    }
    catch {
        Write-Error -ErrorRecord $_
        return @{
            server = $ServerName
            components = @{
                _error = @{
                    status = 'error'
                    value  = $_.Exception.Message
                    details = @()
                }
            }
            webEndpoint = @{ rdWebAvailable = $false; guacamoleAvailable = $false }
            existingRemoteApps = @()
            recommendations = @("Probe API hatasi: $($_.Exception.Message)")
            generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

# ---------------------------------------------------------------------------
# IIS / HttpModule entegrasyonu icin minimal handler.
# IIS altinda C# HttpModule yazildiginda bu fonksiyon cagirilir; bagimsiz
# Kestrel hostu icin de Invoke-ProbeApiHttp.ps1 tarafindan sarmalanir.
#
# Parametre $Request bir PSObject olup su alanlari icermelidir:
#   Headers   : hashtable (Authorization vs.)
#   Query     : hashtable (server vs.)
#   Method    : string ('GET' beklenir)
#
# Cikti: $Response hashtable'i { status, headers, body }
# ---------------------------------------------------------------------------
function Invoke-ProbeApiRequest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Request
    )

    $method = $Request.Method
    if ($method -ne 'GET') {
        return @{
            status = 405
            headers = @{ 'Allow' = 'GET' }
            body    = '{"error":"method_not_allowed"}'
        }
    }

    # Bearer token kontrolu
    $authHeader = $Request.Headers['Authorization']
    $token = $null
    if ($authHeader -and $authHeader -like 'Bearer *') {
        $token = $authHeader.Substring(7)
    }

    if (-not (Test-ProbeApiToken -ProvidedToken $token)) {
        return @{
            status = 401
            headers = @{ 'WWW-Authenticate' = 'Bearer' }
            body    = '{"error":"unauthorized"}'
        }
    }

    # Server parametresi (query string veya header)
    $server = $Request.Query['server']
    if ([string]::IsNullOrWhiteSpace($server)) { $server = $env:COMPUTERNAME }

    $probe = Invoke-ProbeApi -ServerName $server

    return @{
        status = 200
        headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Cache-Control' = 'no-store'
        }
        body = ($probe | ConvertTo-Json -Depth 8)
    }
}

# ---------------------------------------------------------------------------
# Dot-source yardimcisi - bu script bir module olarak yuklendiginde
# fonksiyonlar disari acilir.
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'Invoke-ProbeApi',
        'Invoke-ProbeApiRequest',
        'Test-ProbeApiToken'
    )
}