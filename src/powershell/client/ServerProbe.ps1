<#
.SYNOPSIS
    ServerProbe - WinRM uzerinden uzak Windows Server'i tarayan ve lisans /
    HTML5 endpoint durumunu raporlayan istemci tarafi PowerShell modulu.

.DESCRIPTION
    "Rdp Virtual Box App" istemci kurulumunun 2. adiminda calisir.
    -Sunucu WinRM / WMI ile kontrol edilir
    - RDS rolleri, RD Gateway / Web Access / Session Host, RemoteApp listesi
      RDP / HTTPS / Guacamole portlari, RDP sertifikasi, OS, domain, lisans
      durumu tek tek sorgulanir
    - HTML5 endpoint tipi (RD Web veya Apache Guacamole) tespit edilir
    - Baglanti stratejileri (Direct / Gateway / Guacamole / Tailscale /
      Cloudflare) icin kullanilabilirlik haritasi uretilir
    - Sonuclar JSON formatinda dondurulur

    Modul olarak (.psm1) de kullanilabilir, ancak istemci setup'i tarafindan
    "nokta kaynak" (dot-source) olarak da cagrilabilir.

.NOTES
    Version : 1.0.0
    Author  : Rdp Virtual Box App - Agent C1
    PSScriptAnalyzer uyumlu.
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Sabitler
# ---------------------------------------------------------------------------

$Script:DefaultWinRMPort   = 5985
$Script:DefaultHttpsPort   = 443
$Script:SecureWinRMPort    = 5986
$Script:RdpPort            = 3389
$Script:GuacamolePort      = 8443

# Status sabitleri (JSON-cikti uyumu icin kucuk harf)
$Script:StatusOk      = 'ok'
$Script:StatusWarn    = 'warning'
$Script:StatusError   = 'error'
$Script:StatusUnknown = 'unknown'

# ---------------------------------------------------------------------------
# Dahili yardimci fonksiyonlar
# ---------------------------------------------------------------------------

function Get-ComponentStatus {
<#
.SYNOPSIS
    Tek bir bilesenin durum kaydini uretir (ok / warning / error / unknown).

.PARAMETER Name
    Bilesen adi (ornek: "RDS_Role", "RDP_Port").

.PARAMETER Status
    Durum: ok | warning | error | unknown. Buyuk/kucuk harf duyarsiz.

.PARAMETER Value
    Eklenen aciklayici deger (ornek: "Installed", "3389 open").

.PARAMETER Details
    Opsiyonel ayrintili mesaj listesi (sorun tespiti icin).

.EXAMPLE
    Get-ComponentStatus -Name 'RDP_Port' -Status 'ok' -Value '3389 open'
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('ok','warning','error','unknown')]
        [string] $Status,

        [string] $Value = '',

        [string[]] $Details = @()
    )

    $normalizedStatus = switch ($Status.ToLowerInvariant()) {
        'ok'      { 'ok' }
        'warning' { 'warning' }
        'error'   { 'error' }
        default   { 'unknown' }
    }

    return [ordered]@{
        name    = $Name
        status  = $normalizedStatus
        value   = $Value
        details = $Details
    }
}

function Test-RemotePort {
<#
.SYNOPSIS
    Uzak sunucuda belirli bir TCP portunun erisilebilir olup olmadigini test eder.

.PARAMETER ComputerName
    Hedef sunucu (IP veya FQDN).

.PARAMETER Port
    Test edilecek TCP port numarasi.

.PARAMETER TimeoutSec
    Baglanti zaman asimi (saniye). Default 5.

.EXAMPLE
    Test-RemotePort -ComputerName '192.168.0.106' -Port 3389
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $Port,

        [ValidateRange(1, 120)]
        [int] $TimeoutSec = 5
    )

    $result = $false
    try {
        $tnc = Test-NetConnection -ComputerName $ComputerName -Port $Port `
                                  -InformationLevel Quiet `
                                  -WarningAction SilentlyContinue `
                                  -ErrorAction Stop
        $result = [bool] $tnc
    } catch {
        Write-Verbose "Test-RemotePort: $ComputerName:$Port baglanti testi basarisiz -> $($_.Exception.Message)"
        $result = $false
    }
    return $result
}

function Get-CertificateStatus {
<#
.SYNOPSIS
    Uzak sunucudaki RDP baglanti sertifikasini sorgular ve durumunu raporlar.

.PARAMETER Server
    Hedef sunucu (IP veya FQDN).

.PARAMETER Credential
    Uzak sunucu icin PSCredential.

.EXAMPLE
    Get-CertificateStatus -Server '192.168.0.106' -Credential $cred
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Server,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential] $Credential
    )

    $empty = [ordered]@{
        status  = 'unknown'
        value   = 'Unknown'
        details = @()
    }

    try {
        $remoteResult = Invoke-Command -ComputerName $Server `
                                       -Credential $Credential `
                                       -ErrorAction Stop `
                                       -ScriptBlock {
            $stores = @('Cert:\LocalMachine\My', 'Cert:\LocalMachine\Remote Desktop')
            $all = @()
            foreach ($store in $stores) {
                if (Test-Path $store) {
                    try {
                        $certs = Get-ChildItem -Path $store -ErrorAction SilentlyContinue
                        if ($certs) { $all += $certs }
                    } catch { }
                }
            }

            $match = $null
            foreach ($c in $all) {
                try {
                    if ($c.Subject -match 'Remote Desktop' -or
                        $c.Subject -match 'RD' -or
                        $c.Extensions -match 'Remote Desktop Authentication') {
                        $match = $c
                        break
                    }
                } catch { }
            }
            if (-not $match -and $all.Count -gt 0) {
                $match = $all | Sort-Object NotAfter -Descending | Select-Object -First 1
            }

            if ($match) {
                [pscustomobject]@{
                    Found      = $true
                    Subject    = $match.Subject
                    Issuer     = $match.Issuer
                    Thumbprint = $match.Thumbprint
                    NotAfter   = $match.NotAfter.ToString('o')
                    IsSelfSigned = $match.Subject -eq $match.Issuer
                    HasPrivateKey = $match.HasPrivateKey
                }
            } else {
                [pscustomobject]@{ Found = $false }
            }
        }

        if (-not $remoteResult.Found) {
            return [ordered]@{
                status  = 'error'
                value   = 'Missing'
                details = @('RDP sertifikasi bulunamadi (Cert:\LocalMachine\My ve Remote Desktop store tarandi).')
            }
        }

        $detailList = @(
            "Subject: $($remoteResult.Subject)",
            "Issuer: $($remoteResult.Issuer)",
            "Thumbprint: $($remoteResult.Thumbprint)",
            "NotAfter: $($remoteResult.NotAfter)",
            "PrivateKey: $($remoteResult.HasPrivateKey)"
        )

        if ($remoteResult.IsSelfSigned) {
            return [ordered]@{
                status  = 'warning'
                value   = 'Self-signed'
                details = $detailList
            }
        }
        return [ordered]@{
            status  = 'ok'
            value   = 'CA-signed'
            details = $detailList
        }
    } catch {
        Write-Verbose "Get-CertificateStatus: sorgu basarisiz -> $($_.Exception.Message)"
        return [ordered]@{
            status  = 'warning'
            value   = 'Unknown'
            details = @("Sertifika sorgusu basarisiz: $($_.Exception.Message)")
        }
    }
}

function Format-ProbeResult {
<#
.SYNOPSIS
    ProbeResult (hashtable) icin konsol dostu ozet tablo olusturur.

.PARAMETER ProbeResult
    Invoke-ServerProbe cikti hashtable.

.EXAMPLE
    $probe = Invoke-ServerProbe -Server '192.168.0.106' -Credential $cred
    Format-ProbeResult -ProbeResult $probe
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ProbeResult
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== ServerProbe Sonucu ===')
    [void]$sb.AppendLine(("Sunucu       : {0}" -f $ProbeResult.server))
    [void]$sb.AppendLine(("Erisilebilir : {0}" -f $ProbeResult.reachable))
    [void]$sb.AppendLine(("OS           : {0}" -f $ProbeResult.os))
    [void]$sb.AppendLine(("Domain       : {0}" -f $ProbeResult.domain))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Bilesenler ---')
    $sortedKeys = $ProbeResult.components.Keys | Sort-Object
    foreach ($k in $sortedKeys) {
        $c = $ProbeResult.components[$k]
        [void]$sb.AppendLine(("  {0,-18} : [{1,-7}] {2}" -f $k, $c.status, $c.value))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Web Endpoint ---')
    $w = $ProbeResult.webEndpoint
    [void]$sb.AppendLine(("  Tip    : {0}" -f $w.type))
    [void]$sb.AppendLine(("  URL    : {0}" -f $w.url))
    [void]$sb.AppendLine(("  RD Web : {0}" -f $w.rdWebAvailable))
    [void]$sb.AppendLine(("  Guac.  : {0}" -f $w.guacamoleAvailable))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Baglanti Stratejileri ---')
    foreach ($sKey in $ProbeResult.connectionStrategies.Keys) {
        $s = $ProbeResult.connectionStrategies[$sKey]
        $line = "  $sKey : "
        $values = ($s.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        [void]$sb.AppendLine($line + $values)
    }
    if ($ProbeResult.existingRemoteApps.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('--- Mevcut RemoteApp ---')
        foreach ($a in $ProbeResult.existingRemoteApps) {
            [void]$sb.AppendLine(("  {0,-30} -> {1}" -f $a.alias, $a.name))
        }
    }
    if ($ProbeResult.recommendations.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('--- Oneriler ---')
        foreach ($r in $ProbeResult.recommendations) {
            [void]$sb.AppendLine("  - $r")
        }
    }
    return $sb.ToString()
}

function Get-ProbeFallbackApps {
<#
.SYNOPSIS
    apps.template.json icindeki fallback uygulama listesini okur.

.PARAMETER TemplatePath
    Sablon dosya yolu. Default: ServerProbe.ps1 ile ayni dizindeki
    "/config/client/apps.template.json" yolu.

.EXAMPLE
    $fallback = Get-ProbeFallbackApps
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string] $TemplatePath
    )

    if (-not $TemplatePath) {
        $moduleDir = $PSScriptRoot
        if (-not $moduleDir -and $MyInvocation.MyCommand.Path) {
            $moduleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        # Eger modul betik olarak yuklendiyse $moduleDir bos kalabilir
        if (-not $moduleDir) {
            $moduleDir = (Get-Location).Path
        }
        $candidate = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $moduleDir)) `
                               -ChildPath 'config/client/apps.template.json'
        $TemplatePath = $candidate
    }

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        Write-Verbose "Fallback sablon bulunamadi: $TemplatePath"
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -and $parsed.apps) {
            return @($parsed.apps)
        }
        return @()
    } catch {
        Write-Verbose "Fallback sablon okunamadi: $($_.Exception.Message)"
        return @()
    }
}

# ---------------------------------------------------------------------------
# Ana fonksiyonlar
# ---------------------------------------------------------------------------

function Get-RemoteOs {
<#
.SYNOPSIS
    Uzak sunucudan Win32_OperatingSystem bilgisini WinRM veya WMI ile alir.

.PARAMETER Server
    Hedef sunucu.

.PARAMETER Credential
    PSCredential.

.PARAMETER UseWmiFallback
    true ise WinRM yerine dogrudan WMI kullanilir.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential,
        [bool] $UseWmiFallback = $false
    )

    if ($UseWmiFallback) {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Server `
                            -Credential $Credential -ErrorAction Stop
        return $os.Caption
    }

    $res = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock { (Get-CimInstance Win32_OperatingSystem).Caption }
    return $res
}

function Get-RemoteDomain {
<#
.SYNOPSIS
    Uzak sunucunun AD domain bilgisini (varsa) getirir.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    try {
        $domain = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                try {
                    $info = Get-ADDomain -ErrorAction Stop
                    $info.DNSRoot
                } catch {
                    if ($env:USERDOMAIN) { $env:USERDOMAIN } else { 'WORKGROUP' }
                }
            }
        return $domain
    } catch {
        Write-Verbose "Domain bilgisi alinamadi: $($_.Exception.Message)"
        return 'WORKGROUP'
    }
}

function Get-RemoteWindowsFeatures {
<#
.SYNOPSIS
    Get-WindowsFeature -ComputerName $Server cagrisi. Iki liste dondurur:
    - rdsAll   : RDS* jokerinden gelen tum roller
    - rdsSpec  : RD-Gateway, RD-Web-Access, RD-Session-Hos spesifik roller
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    $result = [ordered]@{
        rdsAll  = @()
        rdsSpec = @()
    }

    try {
        $all = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock { Get-WindowsFeature -Name 'RDS*' -ErrorAction SilentlyContinue }
        if ($all) {
            $result.rdsAll = @($all | Select-Object Name, DisplayName, InstallState)
        }
    } catch {
        Write-Verbose "RDS* feature sorgusu basarisiz: $($_.Exception.Message)"
    }

    try {
        $spec = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                param($names)
                Get-WindowsFeature -Name $names -ErrorAction SilentlyContinue
            } -ArgumentList @('RD-Gateway','RD-Web-Access','RD-Session-Host')
        if ($spec) {
            $result.rdsSpec = @($spec | Select-Object Name, DisplayName, InstallState)
        }
    } catch {
        Write-Verbose "Spesifik RDS feature sorgusu basarisiz: $($_.Exception.Message)"
    }

    return $result
}

function Get-RemoteApps {
<#
.SYNOPSIS
    Get-RDRemoteApp cagrisi ile sunucudaki yayinlanmis RemoteApp listesini
    [{alias, name, path}] olarak dondurur.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    $list = @()
    try {
        $raw = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                try {
                    Get-RDRemoteApp -ErrorAction Stop
                } catch {
                    @()
                }
            }
        foreach ($a in $raw) {
            $alias = if ($a.PSObject.Properties.Match('Alias').Count -gt 0) { [string]$a.Alias } else { '' }
            $name  = if ($a.PSObject.Properties.Match('Name').Count -gt 0 -or $a.PSObject.Properties.Match('DisplayName').Count -gt 0) {
                if ($a.DisplayName) { [string]$a.DisplayName } else { [string]$a.Name }
            } else { '' }
            $path  = if ($a.PSObject.Properties.Match('FilePath').Count -gt 0) { [string]$a.FilePath } else { '' }
            $list += [ordered]@{
                alias = $alias
                name  = $name
                path  = $path
            }
        }
    } catch {
        Write-Verbose "RemoteApp listesi alinamadi: $($_.Exception.Message)"
    }
    return ,$list
}

function Get-RemoteLicenseStatus {
<#
.SYNOPSIS
    HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters\License
    anahtarini okuyarak TermService lisans durumunu tespit eder.

.RETURN
    {status,value,details} hashtable. status degerleri: ok, warning, error, unknown.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    $empty = [ordered]@{ status = 'unknown'; value = 'Unknown'; details = @() }
    try {
        $lic = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters'
                if (Test-Path $key) {
                    try {
                        Get-ItemProperty -Path $key -Name 'License' -ErrorAction SilentlyContinue
                    } catch {
                        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
                    }
                } else {
                    $null
                }
            }

        if ($null -eq $lic) {
            return [ordered]@{
                status  = 'warning'
                value   = 'Unknown'
                details = @('Registry anahtari okunamadi veya bulunamadi.')
            }
        }

        # Olasiliga gore durum cikarimi
        $props = $lic.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }
        $details = @($props)

        # Yaygin degerler: "1,2,3,..." veya "activated" / "0"
        $flat = ($props -join ' ').ToLower()
        if ($flat -match 'activated' -or $flat -match 'licensetype' -or $flat -match 'licenseserver') {
            return [ordered]@{
                status  = 'ok'
                value   = 'Activated'
                details = $details
            }
        }
        if ($flat -match 'grace' -or $flat -match '120') {
            return [ordered]@{
                status  = 'warning'
                value   = 'Grace Period'
                details = $details
            }
        }
        # Belirgin "0" degeri -> Not configured
        if ($flat -match 'license=0') {
            return [ordered]@{
                status  = 'error'
                value   = 'Not Configured'
                details = $details
            }
        }
        return [ordered]@{
            status  = 'ok'
            value   = 'Configured'
            details = $details
        }
    } catch {
        Write-Verbose "Lisans durumu sorgusu basarisiz: $($_.Exception.Message)"
        return [ordered]@{
            status  = 'unknown'
            value   = 'Unknown'
            details = @("Sorgu hatasi: $($_.Exception.Message)")
        }
    }
}

function Get-RemoteGuacamoleState {
<#
.SYNOPSIS
    Uzak sunucuda Apache Guacamole kurulumunun varligini sorgular.
    Dondurulen nesne: { guacamolePortOpen, guacdService, webAppOk, installPath }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    $state = [ordered]@{
        guacamolePortOpen = $false
        guacdService      = 'Unknown'
        webAppOk          = $false
        installPath       = ''
        tomcatDetected    = $false
    }

    # 1) Port kontrolu (yerel)
    $state.guacamolePortOpen = Test-RemotePort -ComputerName $Server -Port $Script:GuacamolePort

    # 2) guacd Windows service
    try {
        $svc = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                try {
                    $s = Get-Service -Name 'guacd' -ErrorAction SilentlyContinue
                    if ($s) { $s.Status.ToString() } else { 'NotInstalled' }
                } catch { 'Unknown' }
            }
        $state.guacdService = $svc
    } catch {
        Write-Verbose "guacd servisi sorgusu basarisiz: $($_.Exception.Message)"
    }

    # 3) Web app ve Tomcat varligi
    try {
        $web = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                $tomcat = 'C:\Program Files\Apache Software Foundation\Tomcat'
                $tomcatAlt = 'C:\Program Files\Apache Software Foundation\Tomcat 9.0'
                $installed = $false
                $ipath = ''
                if (Test-Path $tomcat)       { $installed = $true; $ipath = $tomcat }
                elseif (Test-Path $tomcatAlt) { $installed = $true; $ipath = $tomcatAlt }
                $webapps = if ($installed) {
                    Join-Path $ipath 'webapps'
                } else { '' }
                $guacWar = if ($webapps -and (Test-Path $webapps)) {
                    Test-Path (Join-Path $webapps 'guacamole')
                } else { $false }
                [pscustomobject]@{
                    TomcatInstalled = $installed
                    InstallPath     = $ipath
                    GuacWarExists   = $guacWar
                }
            }
        $state.tomcatDetected = [bool] $web.TomcatInstalled
        $state.installPath    = [string] $web.InstallPath
        $state.webAppOk       = [bool] $web.GuacWarExists
    } catch {
        Write-Verbose "Tomcat/Guacamole webapp sorgusu basarisiz: $($_.Exception.Message)"
    }

    return $state
}

function Get-RemoteRdWebState {
<#
.SYNOPSIS
    Uzak sunucuda RD Web Access rolunun ve HTTPS 443 uzerinden yayinin varligini
    sorgular.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential] $Credential
    )

    $state = [ordered]@{
        featureInstalled = $false
        httpsOpen        = $false
        webClientOk      = $false
    }

    try {
        $feat = Invoke-Command -ComputerName $Server -Credential $Credential -ErrorAction Stop `
            -ScriptBlock {
                $f = Get-WindowsFeature -Name 'RD-Web-Access' -ErrorAction SilentlyContinue
                if ($f) { [bool]($f.InstallState -eq 'Installed') } else { $false }
            }
        $state.featureInstalled = [bool] $feat
    } catch {
        Write-Verbose "RD-Web-Access feature sorgusu basarisiz: $($_.Exception.Message)"
    }

    $state.httpsOpen   = Test-RemotePort -ComputerName $Server -Port $Script:DefaultHttpsPort
    $state.webClientOk = $state.httpsOpen -and $state.featureInstalled
    return $state
}

function Test-WinRmAvailable {
<#
.SYNOPSIS
    Uzak sunucuya WinRM baglantisinin kurulup kurulamayacagini kontrol eder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Server,
        [int] $Port = $Script:DefaultWinRMPort,
        [int] $TimeoutSec = 30
    )

    $timeout = $TimeoutSec
    $job = Start-Job -ScriptBlock {
        param($s, $p)
        try {
            $null = Test-WSMan -ComputerName $s -Port $p -ErrorAction Stop
            return $true
        } catch { return $false }
    } -ArgumentList $Server, $Port

    try {
        $completed = $job | Wait-Job -Timeout $timeout
        if ($null -eq $completed) {
            Stop-Job -Job $job -Force | Out-Null
            return $false
        }
        return [bool] ($job | Receive-Job)
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Ana giris noktasi: Invoke-ServerProbe
# ---------------------------------------------------------------------------

function Invoke-ServerProbe {
<#
.SYNOPSIS
    Bir Windows Server uzerinde WinRM ile kapsamli yoklama yapar ve
    JSON-benzeri hashtable dondurur.

.DESCRIPTION
    -Server, -Credential ile calisir. Opsiyonel olarak WinRM erisilemezse WMI
    fallback yapar. Sonuc:
    reachable, os, domain, components (11+ alan), existingRemoteApps,
    webEndpoint, connectionStrategies, recommendations

.PARAMETER Server
    Hedef sunucu IP veya FQDN.

.PARAMETER Credential
    PSCredential.

.PARAMETER Port
    WinRM portu. Default 5985.

.PARAMETER TimeoutSec
    Toplam islem zaman asimi. Default 30.

.PARAMETER TemplatePath
    apps.template.json yolu. Bos birakildiginda moduleDir'den turetilir.

.PARAMETER PassThru
    $false ise sonuc JSON string olarak doner. $true (default) hashtable.

.EXAMPLE
    $cred = Get-Credential
    $probe = Invoke-ServerProbe -Server '192.168.0.106' -Credential $cred
    $probe | ConvertTo-Json -Depth 6
#>
    [CmdletBinding()]
    [OutputType([hashtable], [string])]
    param(
        [Parameter(Mandatory)]
        [string] $Server,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential] $Credential,

        [ValidateRange(1, 65535)]
        [int] $Port = $Script:DefaultWinRMPort,

        [ValidateRange(1, 600)]
        [int] $TimeoutSec = 30,

        [string] $TemplatePath,

        [bool] $PassThru = $true
    )

    Write-Verbose "Invoke-ServerProbe: basladi. Server=$Server Port=$Port"

    $probe = [ordered]@{
        server             = $Server
        reachable          = $false
        os                 = ''
        domain             = ''
        components         = [ordered]@{}
        existingRemoteApps = @()
        webEndpoint        = [ordered]@{
            type               = 'Unknown'
            url                = ''
            rdWebAvailable     = $false
            guacamoleAvailable = $false
        }
        connectionStrategies = [ordered]@{
            direct     = [ordered]@{ available = $false; port = $Script:RdpPort }
            gateway    = [ordered]@{ available = $false; port = $Script:DefaultHttpsPort }
            guacamole  = [ordered]@{ available = $false; url = '' }
            tailscale  = [ordered]@{ available = $false }
            cloudflare = [ordered]@{ available = $false }
        }
        recommendations  = @()
        timestamp        = (Get-Date).ToString('o')
    }

    # 1) WinRM erisilebilirlik testi
    $winrmOk = Test-WinRmAvailable -Server $Server -Port $Port -TimeoutSec $TimeoutSec
    $probe.reachable = $winrmOk

    $wmiFallback = -not $winrmOk
    if ($wmiFallback) {
        Write-Verbose "WinRM erisilemedi. WMI fallback deneniyor..."
        try {
            $null = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Server `
                                  -Credential $Credential -ErrorAction Stop
            $probe.reachable = $true
        } catch {
            Write-Verbose "WMI fallback da basarisiz: $($_.Exception.Message)"
            $probe.components['WinRM'] = Get-ComponentStatus -Name 'WinRM' `
                -Status error -Value 'Unreachable' `
                -Details @("Test-WSMan ve WMI fallback basarisiz. Port $Port kontrol edin.")
            return $(if ($PassThru) { $probe } else { $probe | ConvertTo-Json -Depth 8 })
        }
    }

    # WinRM / WMI status
    if ($winrmOk) {
        $probe.components['WinRM'] = Get-ComponentStatus -Name 'WinRM' `
            -Status ok -Value "Accessible on port $Port"
    } else {
        # WinRM yok ama WMI ile devam ediyoruz; "warning" olarak kaydet
        $probe.components['WinRM'] = Get-ComponentStatus -Name 'WinRM' `
            -Status warning -Value 'Unreachable (WMI fallback in use)'
    }

    # 2) OS
    try {
        $osValue = Get-RemoteOs -Server $Server -Credential $Credential -UseWmiFallback $wmiFallback
        $probe.os = [string] $osValue
        $probe.components['OS'] = Get-ComponentStatus -Name 'OS' `
            -Status ok -Value ([string] $osValue)
    } catch {
        $probe.components['OS'] = Get-ComponentStatus -Name 'OS' `
            -Status warning -Value 'Unknown' -Details @($_.Exception.Message)
    }

    # 3) Domain
    try {
        $domainValue = Get-RemoteDomain -Server $Server -Credential $Credential
        $probe.domain = [string] $domainValue
        $status = if ($domainValue -and $domainValue -ne 'WORKGROUP') { 'ok' } else { 'warning' }
        $probe.components['Domain'] = Get-ComponentStatus -Name 'Domain' `
            -Status $status -Value ([string] $domainValue)
    } catch {
        $probe.components['Domain'] = Get-ComponentStatus -Name 'Domain' `
            -Status warning -Value 'Unknown' -Details @($_.Exception.Message)
    }

    # 4) RDS Feature'lar
    try {
        $features = Get-RemoteWindowsFeatures -Server $Server -Credential $Credential
        $rdsAllInstalled = ($features.rdsAll | Where-Object { $_.InstallState -eq 'Installed' }).Count -gt 0
        $probe.components['RDS_Role'] = Get-ComponentStatus -Name 'RDS_Role' `
            -Status (if ($rdsAllInstalled) { 'ok' } else { 'error' }) `
            -Value (if ($rdsAllInstalled) { 'Installed' } else { 'Not Installed' })

        # Spesifik roller
        $specDict = @{}
        foreach ($f in $features.rdsSpec) {
            $specDict[$f.Name] = [bool]($f.InstallState -eq 'Installed')
        }

        $sessionHost = $specDict['RD-Session-Host']
        $webAccess   = $specDict['RD-Web-Access']
        $gateway     = $specDict['RD-Gateway']

        $probe.components['RD_SessionHost'] = Get-ComponentStatus -Name 'RD_SessionHost' `
            -Status (if ($sessionHost) { 'ok' } else { 'error' }) `
            -Value (if ($sessionHost) { 'Installed' } else { 'Not Installed' })
        $probe.components['RD_WebAccess'] = Get-ComponentStatus -Name 'RD_WebAccess' `
            -Status (if ($webAccess) { 'ok' } else { 'warning' }) `
            -Value (if ($webAccess) { 'Installed' } else { 'Not Installed' })
        $probe.components['RD_Gateway'] = Get-ComponentStatus -Name 'RD_Gateway' `
            -Status (if ($gateway) { 'ok' } else { 'warning' }) `
            -Value (if ($gateway) { 'Installed' } else { 'Missing' })
    } catch {
        Write-Verbose "Feature toplama hata: $($_.Exception.Message)"
        $probe.components['RDS_Role']      = Get-ComponentStatus -Name 'RDS_Role' -Status unknown -Value 'Unknown'
        $probe.components['RD_SessionHost']= Get-ComponentStatus -Name 'RD_SessionHost' -Status unknown -Value 'Unknown'
        $probe.components['RD_WebAccess']  = Get-ComponentStatus -Name 'RD_WebAccess' -Status unknown -Value 'Unknown'
        $probe.components['RD_Gateway']    = Get-ComponentStatus -Name 'RD_Gateway' -Status unknown -Value 'Unknown'
    }

    # 5) RemoteApp listesi (yalniz WinRM/WMI calisiyorsa, RDS_Role installed ise)
    if ($probe.components['RDS_Role'].status -eq 'ok') {
        try {
            $apps = Get-RemoteApps -Server $Server -Credential $Credential
            $probe.existingRemoteApps = $apps
            $probe.components['RemoteApps'] = Get-ComponentStatus -Name 'RemoteApps' `
                -Status (if ($apps.Count -gt 0) { 'ok' } else { 'warning' }) `
                -Value "$($apps.Count) application(s) published"
        } catch {
            $probe.components['RemoteApps'] = Get-ComponentStatus -Name 'RemoteApps' `
                -Status warning -Value 'Unavailable' -Details @($_.Exception.Message)
            # RemoteApp alinamadiysa apps.template.json fallback'i yukle
            $fallback = Get-ProbeFallbackApps -TemplatePath $TemplatePath
            if ($fallback.Count -gt 0) {
                $probe.existingRemoteApps = @($fallback | ForEach-Object {
                    [ordered]@{
                        alias = [string] $_.id
                        name  = [string] $_.name
                        path  = [string] $_.executable
                    }
                })
                Write-Verbose "Fallback sablonundan $($fallback.Count) kayit yuklendi."
            }
        }
    } else {
        $probe.components['RemoteApps'] = Get-ComponentStatus -Name 'RemoteApps' `
            -Status warning -Value 'Skipped (RDS not installed)'
        # RDS yoksa fallback sablonu yukle
        $fallback = Get-ProbeFallbackApps -TemplatePath $TemplatePath
        if ($fallback.Count -gt 0) {
            $probe.existingRemoteApps = @($fallback | ForEach-Object {
                [ordered]@{
                    alias = [string] $_.id
                    name  = [string] $_.name
                    path  = [string] $_.executable
                }
            })
        }
    }

    # 6) Port testleri (yerel TCP)
    $rdpOpen = Test-RemotePort -ComputerName $Server -Port $Script:RdpPort -TimeoutSec 5
    $httpsOpen = Test-RemotePort -ComputerName $Server -Port $Script:DefaultHttpsPort -TimeoutSec 5
    $guacOpen = Test-RemotePort -ComputerName $Server -Port $Script:GuacamolePort -TimeoutSec 5

    $probe.components['RDP_Port'] = Get-ComponentStatus -Name 'RDP_Port' `
        -Status (if ($rdpOpen) { 'ok' } else { 'error' }) `
        -Value (if ($rdpOpen) { "$($Script:RdpPort) open" } else { "$($Script:RdpPort) closed/filtered" })

    $probe.components['HTTPS_Port'] = Get-ComponentStatus -Name 'HTTPS_Port' `
        -Status (if ($httpsOpen) { 'ok' } else { 'warning' }) `
        -Value (if ($httpsOpen) { "$($Script:DefaultHttpsPort) open" } else { "$($Script:DefaultHttpsPort) closed/filtered" })

    $probe.components['Guacamole_Port'] = Get-ComponentStatus -Name 'Guacamole_Port' `
        -Status (if ($guacOpen) { 'ok' } else { 'warning' }) `
        -Value (if ($guacOpen) { "$($Script:GuacamolePort) open" } else { "$($Script:GuacamolePort) closed/filtered" })

    # 7) Sertifika durumu
    $cert = Get-CertificateStatus -Server $Server -Credential $Credential
    $probe.components['Certificate'] = [ordered]@{
        name    = 'Certificate'
        status  = $cert.status
        value   = $cert.value
        details = $cert.details
    }

    # 8) Lisans durumu
    $lic = Get-RemoteLicenseStatus -Server $Server -Credential $Credential
    $probe.components['License'] = [ordered]@{
        name    = 'License'
        status  = $lic.status
        value   = $lic.value
        details = $lic.details
    }

    # 9) HTML5 endpoint tespiti
    $rdw  = Get-RemoteRdWebState  -Server $Server -Credential $Credential
    $guac = Get-RemoteGuacamoleState -Server $Server -Credential $Credential

    $probe.webEndpoint.rdWebAvailable     = $rdw.webClientOk
    $probe.webEndpoint.guacamoleAvailable = ($guac.guacamolePortOpen -or $guac.webAppOk)

    if ($rdw.webClientOk -and $guac.webAppOk) {
        $probe.webEndpoint.type = 'Both'
        $probe.webEndpoint.url  = "https://$Server/guacamole"
    } elseif ($rdw.webClientOk) {
        $probe.webEndpoint.type = 'RDWeb'
        $probe.webEndpoint.url  = "https://$Server/RDWeb/webclient"
    } elseif ($probe.webEndpoint.guacamoleAvailable) {
        $probe.webEndpoint.type = 'Guacamole'
        $probe.webEndpoint.url  = "https://$Server`:$($Script:GuacamolePort)/guacamole"
    } else {
        $probe.webEndpoint.type = 'None'
        $probe.webEndpoint.url  = ''
    }

    # 10) Baglanti stratejileri haritasi
    $probe.connectionStrategies.direct     = [ordered]@{
        available = $rdpOpen
        port      = $Script:RdpPort
    }
    $probe.connectionStrategies.gateway    = [ordered]@{
        available = ($httpsOpen -and ($probe.components['RD_Gateway'].status -eq 'ok'))
        port      = $Script:DefaultHttpsPort
        note      = if (-not $probe.connectionStrategies.gateway.available) {
            'RD Gateway rolunu kurun veya HTTPS acin'
        } else { '' }
    }
    $probe.connectionStrategies.guacamole  = [ordered]@{
        available = $probe.webEndpoint.guacamoleAvailable
        url       = "https://$Server`:$($Script:GuacamolePort)/guacamole"
    }
    # Tailscale / Cloudflare tarafindan bilgi yoksa false birak. Dogrulama
    # client wizard'da opsiyonel olarak sorulur.
    $probe.connectionStrategies.tailscale  = [ordered]@{ available = $false }
    $probe.connectionStrategies.cloudflare = [ordered]@{ available = $false }

    # 11) Oneriler
    $recs = New-Object System.Collections.Generic.List[string]
    if (-not $rdpOpen)              { $recs.Add('RDP portu (3389) erisilemez - firewall veya NAT kontrol edin.') }
    if (-not $probe.components['RD_SessionHost'].status) { } # noop - status zaten set edildi
    if ($probe.components['RD_SessionHost'].status -ne 'ok') {
        $recs.Add('RD Session Host rolu kurulu degil. RemoteApp yayinlamak icin gereklidir.')
    }
    if (-not $probe.webEndpoint.rdWebAvailable -and -not $probe.webEndpoint.guacamoleAvailable) {
        $recs.Add('HTML5 endpoint tespit edilmedi - RD Web Access kurun veya Apache Guacamole fallback kullanin.')
    }
    if ($probe.webEndpoint.guacamoleAvailable -and -not $probe.webEndpoint.rdWebAvailable) {
        $recs.Add('HTML5 erisimi icin Guacamole kullanin (RD Web lisansi yok).')
    }
    if ($probe.components['Certificate'].status -eq 'warning') {
        $recs.Add('RDP sertifikasi self-signed - CA-imzali sertifika ile degistirin.')
    }
    if ($probe.components['License'].status -in @('error','warning')) {
        $recs.Add('Lisans yapilandirmasini kontrol edin (grace period veya konfigurasyon eksik olabilir).')
    }
    if ($probe.existingRemoteApps.Count -eq 0 -and $probe.components['RDS_Role'].status -eq 'ok') {
        $recs.Add('Henuz yayinlanmis RemoteApp yok. Server-side kurulum ile uygulama ekleyin.')
    }
    $probe.recommendations = @($recs)

    Write-Verbose "Invoke-ServerProbe: tamamlandi. $(($probe.components.Keys | Measure-Object).Count) bilesen, $($probe.existingRemoteApps.Count) RemoteApp kayit edildi."

    if ($PassThru) {
        return $probe
    } else {
        return ($probe | ConvertTo-Json -Depth 10)
    }
}

# ---------------------------------------------------------------------------
# Modul olarak yuklendiginde export edilecek fonksiyonlar
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Invoke-ServerProbe'
    'Get-ComponentStatus'
    'Test-RemotePort'
    'Get-CertificateStatus'
    'Format-ProbeResult'
    'Get-ProbeFallbackApps'
    'Get-RemoteApps'
    'Get-RemoteLicenseStatus'
    'Get-RemoteOs'
    'Get-RemoteDomain'
    'Get-RemoteWindowsFeatures'
    'Get-RemoteGuacamoleState'
    'Get-RemoteRdWebState'
    'Test-WinRmAvailable'
) -Variable @()

# ---------------------------------------------------------------------------
# Bu dosya dogrudan calistirildiginda (.ps1 olarak) ornek kullanim
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path.EndsWith('.ps1')) {
    # Betik olarak calistirildi: ornek cikti uretiyoruz (etkilesimli mod).
    Write-Host "ServerProbe.ps1 modul halinde yuklenmedi. Ornek kullanim icin:"
    Write-Host ""
    Write-Host "  Import-Module ./ServerProbe.ps1 -Force"
    Write-Host "  `$cred = Get-Credential"
    Write-Host "  `$probe = Invoke-ServerProbe -Server '192.168.0.106' -Credential `$cred"
    Write-Host "  Format-ProbeResult -ProbeResult `$probe"
    Write-Host "  `$probe | ConvertTo-Json -Depth 8"
}
