#requires -Version 5.1
<#
.SYNOPSIS
    RdpBuilder.ps1 — Rdp Virtual Box App client-side .rdp dosyasi ureticisi.

.DESCRIPTION
    Uc taraftaki RDP dosyalarini uretmek icin sablon motoru saglar.
    Standart uzak-masaustu ozellikleri (RemoteApp, Gateway, Tailscale, ses, yonlendirme)
    tek bir parametre seti ile kontrol edilir. Ayni parametrelerle birden cok
    uygulama icin dongusel uretim desteklenir.

.NOTES
    Encoding : UTF-8 (BOM'suz)
    Author   : Rdp Virtual Box App - Ajan C2
    Version  : 1.0.0
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Dahili sablon motoru: degerler %PLACEHOLDER% seklinde aranir.
# ---------------------------------------------------------------------------
function Format-RdpTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter(Mandatory)]
        [hashtable]$Values
    )

    $result = $Template
    foreach ($key in $Values.Keys) {
        $token = '%{0}%' -f $key.ToUpperInvariant()
        $value = if ($null -eq $Values[$key]) { '' } else { [string]$Values[$key] }
        $result = $result.Replace($token, $value)
    }
    return $result
}

# ---------------------------------------------------------------------------
# Yardimci: tek bir .rdp satiri uretip bos olmayanlari birlestirir.
# ---------------------------------------------------------------------------
function Set-RdpParameter {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Type,    # 's' = string, 'i' = integer, 'b' = boolean

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ('{0}:{1}:{2}' -f $Key, $Type, $Value)
}

# ---------------------------------------------------------------------------
# rdp.template.txt dosyasinin tam yolunu cozer.
# ---------------------------------------------------------------------------
function Get-RdpTemplatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$TemplateRoot
    )

    if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $candidates = @(
            (Join-Path $scriptDir '..\..\config\client\rdp.template.txt'),
            (Join-Path $scriptDir '..\config\client\rdp.template.txt'),
            (Join-Path $PSScriptRoot '..\config\client\rdp.template.txt')
        )
        foreach ($c in $candidates) {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $c))
            if (Test-Path -LiteralPath $resolved) { return $resolved }
        }
        throw 'rdp.template.txt bulunamadi. -TemplateRoot ile manuel yol verin.'
    }
    return (Join-Path $TemplateRoot 'rdp.template.txt')
}

# ---------------------------------------------------------------------------
# Sablondan bos bir hashtable (varsayilan degerlerle) uretir.
# ---------------------------------------------------------------------------
function Get-RdpTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$TemplateRoot
    )

    $path = Get-RdpTemplatePath -TemplateRoot $TemplateRoot
    Write-Verbose ("RDP sablonu okunuyor: {0}" -f $path)
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8

    $values = [ordered]@{
        SERVER                    = ''
        PORT                      = '3389'
        USERNAME                  = ''
        APPNAME                   = ''
        APPALIAS                  = ''
        GATEWAY_HOST              = ''
        GATEWAY_DOMAIN            = ''
        GATEWAY_METHOD            = ''
        GATEWAY_CRED_SOURCE       = ''
        TAILSCALE_IP              = ''
        FULLSCREEN                = '1'
        MULTIMON                  = '0'
        AUTH_LEVEL                = '2'
        CREDSSP                   = '1'
        DRIVE_REDIRECT            = '0'
        PRINTER_REDIRECT          = '1'
        CLIPBOARD_REDIRECT        = '1'
        SMARTCARD_REDIRECT        = '1'
        AUDIO_MODE                = '2'
        ALTERNATE_ADDRESS         = ''
        RDWEB_URL                 = ''
        WIDTH                     = '1920'
        HEIGHT                    = '1080'
    }
    return $values
}

# ---------------------------------------------------------------------------
# Parametreleri sablona yazip .rdp icerigi uretir.
# ---------------------------------------------------------------------------
function New-RdpFile {
    [CmdletBinding(DefaultParameterSetName = 'Direct')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [ValidateRange(1, 65535)]
        [int]$Port = 3389,

        [Parameter(Mandatory)]
        [string]$AppAlias,

        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$Username,

        [switch]$UseGateway,
        [string]$GatewayHost,
        [string]$GatewayDomain,

        [switch]$UseTailscale,
        [string]$TailscaleIP,

        [bool]$FullScreen = $true,

        [switch]$RedirectDrives,
        [bool]$RedirectPrinters = $true,
        [bool]$RedirectClipboard = $true,
        [switch]$RedirectSmartCards,

        [ValidateSet(0, 1, 2)]
        [int]$AudioMode = 2,

        [string]$AlternateAddress,
        [string]$RdWebUrl,

        [int]$Width = 1920,
        [int]$Height = 1080,

        [string]$TemplateRoot
    )

    try {
        # Sunucu hedef adresi: Tailscale tercih ediliyorsa onu kullan.
        $primaryAddress = if ($UseTailscale -and -not [string]::IsNullOrWhiteSpace($TailscaleIP)) {
            $TailscaleIP
        } else {
            $Server
        }

        $fullAddress = '{0}:{1}' -f $primaryAddress, $Port
        $screenModeId = if ($FullScreen) { '2' } else { '1' }
        $multiMon = if ($FullScreen) { '1' } else { '0' }

        $gatewayUsage = ''
        $gatewayHostOut = ''
        $gatewayDomainOut = ''
        $gatewayCredSource = ''
        if ($UseGateway -and -not [string]::IsNullOrWhiteSpace($GatewayHost)) {
            $gatewayUsage = '1'
            $gatewayHostOut = $GatewayHost
            $gatewayDomainOut = if ([string]::IsNullOrWhiteSpace($GatewayDomain)) { '' } else { $GatewayDomain }
            $gatewayCredSource = '0'
        }

        $values = Get-RdpTemplate -TemplateRoot $TemplateRoot
        $values.SERVER             = $fullAddress
        $values.PORT               = $Port
        $values.USERNAME           = $Username
        $values.APPNAME            = $AppName
        $values.APPALIAS           = ('||{0}' -f $AppAlias)
        $values.GATEWAY_HOST       = $gatewayHostOut
        $values.GATEWAY_DOMAIN     = $gatewayDomainOut
        $values.GATEWAY_METHOD     = $gatewayUsage
        $values.GATEWAY_CRED_SOURCE = $gatewayCredSource
        $values.TAILSCALE_IP       = $TailscaleIP
        $values.FULLSCREEN         = $screenModeId
        $values.MULTIMON           = $multiMon
        $values.AUTH_LEVEL         = '2'
        $values.CREDSSP            = '1'
        $values.DRIVE_REDIRECT     = if ($RedirectDrives) { '1' } else { '0' }
        $values.PRINTER_REDIRECT   = if ($RedirectPrinters) { '1' } else { '0' }
        $values.CLIPBOARD_REDIRECT = if ($RedirectClipboard) { '1' } else { '0' }
        $values.SMARTCARD_REDIRECT = if ($RedirectSmartCards) { '1' } else { '0' }
        $values.AUDIO_MODE         = $AudioMode
        $values.ALTERNATE_ADDRESS  = $AlternateAddress
        $values.RDWEB_URL          = $RdWebUrl
        $values.WIDTH              = $Width
        $values.HEIGHT             = $Height

        # Alternatif adres bos ise primary ile ayni olur
        if ([string]::IsNullOrWhiteSpace($values.ALTERNATE_ADDRESS)) {
            $values.ALTERNATE_ADDRESS = $fullAddress
        }

        $templatePath = Get-RdpTemplatePath -TemplateRoot $TemplateRoot
        $raw = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
        return (Format-RdpTemplate -Template $raw -Values $values)
    }
    catch {
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Uretilen dosyayi yazip disk uzerinde dogrular.
# ---------------------------------------------------------------------------
function Test-RdpFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning ('RDP dosyasi bulunamadi: {0}' -f $Path)
        return $false
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $required = @('full address:s:', 'remoteapplicationmode:i:', 'remoteapplicationname:s:', 'remoteapplicationprogram:s:')
    foreach ($needle in $required) {
        if ($content -notmatch [regex]::Escape($needle)) {
            Write-Warning ("RDP dogrulamasi basarisiz: '{0}' beklenen satir bulunamadi." -f $needle)
            return $false
        }
    }
    Write-Verbose ("RDP dosyasi gecti: {0} ({1} satir)" -f $Path, ($content -split "`r?`n").Count)
    return $true
}

# ---------------------------------------------------------------------------
# Birden cok uygulama icin dongusel uretim.
# ---------------------------------------------------------------------------
function New-RdpFileForApps {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[string]])]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Port = 3389,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [hashtable[]]$Apps,

        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp'),

        [switch]$UseGateway,
        [string]$GatewayHost,
        [string]$GatewayDomain,

        [switch]$UseTailscale,
        [string]$TailscaleIP,

        [bool]$FullScreen = $true,
        [switch]$RedirectDrives,
        [bool]$RedirectPrinters = $true,
        [bool]$RedirectClipboard = $true,
        [switch]$RedirectSmartCards,

        [ValidateSet(0, 1, 2)]
        [int]$AudioMode = 2,

        [string]$TemplateRoot
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $produced = New-Object System.Collections.Generic.List[string]
        foreach ($app in $Apps) {
            if ([string]::IsNullOrWhiteSpace($app.Alias)) {
                Write-Warning ("App.Alias bos, atlanıyor: {0}" -f ($app.Name))
                continue
            }

            $content = New-RdpFile @PSBoundParameters -AppAlias $app.Alias -AppName $app.Name
            $safeName = ($app.Name -replace '[\\/:*?"<>|]', '_')
            $filePath = Join-Path $OutputPath ('{0}.rdp' -f $safeName)
            Set-Content -LiteralPath $filePath -Value $content -Encoding UTF8

            if (Test-RdpFile -Path $filePath) {
                $produced.Add($filePath)
            }
        }
        return $produced
    }
    catch {
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Uretilen .rdp dosyasini mstsc ile ac.
# ---------------------------------------------------------------------------
function Invoke-RdpConnection {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ('RDP dosyasi bulunamadi: {0}' -f $Path)
    }

    Write-Verbose ("RDP baglantisi baslatiliyor: {0}" -f $Path)
    Start-Process -FilePath 'mstsc.exe' -ArgumentList ('"{0}"' -f $Path) -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Modulun disariya acilan isimleri.
# ---------------------------------------------------------------------------
Export-ModuleMember -Function `
    'New-RdpFile',
    'New-RdpFileForApps',
    'Get-RdpTemplate',
    'Set-RdpParameter',
    'Test-RdpFile',
    'Invoke-RdpConnection',
    'Get-RdpTemplatePath',
    'Format-RdpTemplate'
