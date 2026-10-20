<#
.SYNOPSIS
    Manages TLS/SSL certificates used by RDS components (RDP-Tcp, RD Web
    Access, RD Gateway).

.DESCRIPTION
    Provides three operating modes:

      * Self-signed certificate creation via New-SelfSignedCertificate.
      * CA-signed certificate import via Import-PfxCertificate.
      * Binding a certificate thumbprint to the RDP-Tcp listener by
        invoking wmic against the WMI namespace root\cimv2\TerminalServices.

    The returned thumbprint can be consumed by RD Web Access and RD Gateway
    configuration routines.

.PARAMETER Mode
    'SelfSigned' or 'CA'. Selects the certificate source.

.PARAMETER ServerFqdn
    Fully qualified DNS name of the server. Used as the certificate
    subject for self-signed certificates.

.PARAMETER PfxPath
    Path to a .pfx file. Required for Mode 'CA'.

.PARAMETER PfxPassword
    SecureString containing the PFX password. Required for Mode 'CA'.

.PARAMETER CertStoreLocation
    Certificate store location. Defaults to Cert:\LocalMachine\My.

.PARAMETER YearsValid
    Years of validity for self-signed certificates. Defaults to 5.

.PARAMETER Thumbprint
    When supplied together with -BindRdpTcp, the function only assigns
    the existing certificate to the RDP listener.

.PARAMETER BindRdpTcp
    When set, the certificate is also bound to the RDP-Tcp listener via
    wmic Win32_TSGeneralSetting.

.PARAMETER LogPath
    Optional path to a log file. Defaults to
    "$env:ProgramData\RdpVirtualBoxApp\Logs\certificate-manager.log".

.EXAMPLE
    New-RdsCertificate -Mode SelfSigned -ServerFqdn 'rdp.example.com' -BindRdpTcp

.EXAMPLE
    New-RdsCertificate -Mode CA -PfxPath 'C:\certs\rdp.pfx' -PfxPassword (Read-Host -AsSecureString) -BindRdpTcp

.NOTES
    Author : Rdp Virtual Box App
    Module  : CertificateManager.ps1
    Tags    : Certificate, TLS, SSL, RDP
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateSet('SelfSigned', 'CA')]
    [string]$Mode,

    [Parameter()]
    [string]$ServerFqdn,

    [Parameter()]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$PfxPassword,

    [Parameter()]
    [string]$CertStoreLocation = 'Cert:\LocalMachine\My',

    [Parameter()]
    [ValidateRange(1, 30)]
    [int]$YearsValid = 5,

    [Parameter()]
    [string]$Thumbprint,

    [Parameter()]
    [switch]$BindRdpTcp,

    [Parameter()]
    [string]$LogPath
)

# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------
$script:RdpSelfSignedStore = 'Cert:\LocalMachine\Remote Desktop'

function Set-CertificateLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

# Backwards-compatible alias for PSScriptAnalyzer PSUseApprovedVerbs compliance
Set-Alias -Name Initialize-CertificateLog -Value Set-CertificateLog -Scope Global -Force

function Write-CertificateLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    Add-Content -LiteralPath $script:CertLogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8

    switch ($Level) {
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning   $Message }
        'Error'   { Write-Error     $Message }
        'Debug'   { Write-Debug     $Message }
    }
}

function Set-RdpTcpCertificateBinding {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CertificateThumbprint
    )

    $thumb = $CertificateThumbprint.Replace(' ', '').ToUpper()
    $wmiArgs = @(
        '/namespace:\\root\cimv2\TerminalServices'
        'path'
        'Win32_TSGeneralSetting'
        'Set'
        "SSLCertificateSHA1Hash=$thumb"
    )

    $display = "wmic $($wmiArgs -join ' ')"

    if ($PSCmdlet.ShouldProcess('RDP-Tcp listener', "Bind certificate thumbprint $thumb")) {
        $output = & wmic @wmiArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "wmic failed to bind certificate: $output"
        }
        Write-CertificateLogEntry -Message "Bound certificate $thumb to RDP-Tcp. Output: $output"
    }
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function New-RdsCertificate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SelfSigned', 'CA')]
        [string]$Mode,

        [Parameter()]
        [string]$ServerFqdn,

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$PfxPath,

        [Parameter()]
        [SecureString]$PfxPassword,

        [Parameter()]
        [string]$CertStoreLocation = 'Cert:\LocalMachine\My',

        [Parameter()]
        [ValidateRange(1, 30)]
        [int]$YearsValid = 5,

        [Parameter()]
        [switch]$BindRdpTcp,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\certificate-manager.log'
    }

    Set-CertificateLog -Path $LogPath
    $script:CertLogPath = $LogPath

    if ($Mode -eq 'SelfSigned' -and -not $ServerFqdn) {
        throw "When -Mode is 'SelfSigned', -ServerFqdn must be supplied."
    }
    if ($Mode -eq 'CA' -and (-not $PfxPath -or -not $PfxPassword)) {
        throw "When -Mode is 'CA', both -PfxPath and -PfxPassword are required."
    }

    try {
        if ($Mode -eq 'SelfSigned') {
            if ($PSCmdlet.ShouldProcess($ServerFqdn, 'Create self-signed certificate')) {
                Write-CertificateLogEntry -Message "Creating self-signed certificate for $ServerFqdn (valid for $YearsValid years)."

                $notAfter = (Get-Date).AddYears($YearsValid)

                $cert = New-SelfSignedCertificate `
                    -DnsName $ServerFqdn `
                    -CertStoreLocation $CertStoreLocation `
                    -NotAfter $notAfter `
                    -KeyUsage DigitalSignature, KeyEncipherment `
                    -KeyAlgorithm RSA `
                    -KeyLength 2048 `
                    -FriendlyName "RdpVirtualBoxApp ($ServerFqdn)" `
                    -ErrorAction Stop
            }
            else {
                return
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($PfxPath, 'Import PFX certificate')) {
                Write-CertificateLogEntry -Message "Importing PFX certificate from $PfxPath."

                $cert = Import-PfxCertificate `
                    -FilePath $PfxPath `
                    -CertStoreLocation $CertStoreLocation `
                    -Password $PfxPassword `
                    -Exportable `
                    -ErrorAction Stop
            }
            else {
                return
            }
        }

        if ($null -eq $cert) {
            throw "Certificate object is null. Cannot continue."
        }

        $thumb = $cert.Thumbprint
        Write-CertificateLogEntry -Message "Certificate installed. Thumbprint=$thumb Subject=$($cert.Subject)"

        if ($BindRdpTcp) {
            try {
                Set-RdpTcpCertificateBinding -CertificateThumbprint $thumb -ErrorAction Stop
            }
            catch {
                Write-CertificateLogEntry -Level Warning -Message "RDP-Tcp binding failed: $($_.Exception.Message)"
            }
        }

        return [PSCustomObject]@{
            Thumbprint         = $thumb
            Subject            = $cert.Subject
            NotAfter           = $cert.NotAfter
            CertStoreLocation  = $CertStoreLocation
            BoundToRdpTcp      = [bool]$BindRdpTcp
            Certificate        = $cert
            LogPath            = $LogPath
        }
    }
    catch {
        Write-CertificateLogEntry -Level Error -Message "Certificate operation failed: $($_.Exception.Message)"
        throw
    }
}

function Get-RdsCertificate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Thumbprint,

        [Parameter()]
        [string]$CertStoreLocation = 'Cert:\LocalMachine\My'
    )

    if ($Thumbprint) {
        $cert = Get-ChildItem -Path "$CertStoreLocation\$Thumbprint" -ErrorAction SilentlyContinue
        if (-not $cert) {
            return $null
        }
        return [PSCustomObject]@{
            Thumbprint = $cert.Thumbprint
            Subject    = $cert.Subject
            NotAfter   = $cert.NotAfter
            Issuer     = $cert.Issuer
            HasPrivateKey = $cert.HasPrivateKey
        }
    }

    $certs = Get-ChildItem -Path $CertStoreLocation -ErrorAction SilentlyContinue
    return $certs | ForEach-Object {
        [PSCustomObject]@{
            Thumbprint    = $_.Thumbprint
            Subject       = $_.Subject
            NotAfter      = $_.NotAfter
            Issuer        = $_.Issuer
            HasPrivateKey = $_.HasPrivateKey
            FriendlyName  = $_.FriendlyName
        }
    }
}

function Remove-RdsCertificate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint,

        [Parameter()]
        [string]$CertStoreLocation = 'Cert:\LocalMachine\My'
    )

    $path = "$CertStoreLocation\$Thumbprint"
    if (Test-Path -LiteralPath $path) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove certificate')) {
            Remove-Item -LiteralPath $path -DeleteKey -Force -ErrorAction Stop
        }
    }
    else {
        Write-Warning "Certificate $Thumbprint not found in $CertStoreLocation."
    }
}

function Get-AutoTlsDnsNames {
    <#
    .SYNOPSIS
        Self-signed SAN listesi: hostname, FQDN, LAN/public IP, localhost.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string[]]$ExtraNames)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($n in @('localhost', '127.0.0.1', $env:COMPUTERNAME)) {
        if ($n -and -not $names.Contains($n)) { [void]$names.Add($n) }
    }
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.DNSHostName -and -not $names.Contains([string]$cs.DNSHostName)) {
            [void]$names.Add([string]$cs.DNSHostName)
        }
        if ($cs.Domain -and $cs.Domain -ne 'WORKGROUP' -and $cs.DNSHostName) {
            $fqdn = '{0}.{1}' -f $cs.DNSHostName, $cs.Domain
            if (-not $names.Contains($fqdn)) { [void]$names.Add($fqdn) }
        }
    } catch { }

    $cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
    foreach ($file in @('customers.json', 'client-endpoints.json')) {
        $path = Join-Path $cfgDir $file
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($file -eq 'customers.json' -and $j.customers) {
                foreach ($c in @($j.customers)) {
                    foreach ($prop in @('publicIp', 'lanIp', 'vpnIp', 'hostname', 'fqdn')) {
                        if ($c.PSObject.Properties[$prop] -and $c.$prop) {
                            $v = [string]$c.$prop
                            if ($v -and -not $names.Contains($v)) { [void]$names.Add($v) }
                        }
                    }
                }
            } else {
                foreach ($prop in @('public', 'lan', 'vpn', 'client', 'hostname', 'fqdn')) {
                    if ($j.PSObject.Properties[$prop] -and $j.$prop) {
                        $v = [string]$j.$prop
                        if ($v -and -not $names.Contains($v)) { [void]$names.Add($v) }
                    }
                }
            }
        } catch { }
    }

    if ($ExtraNames) {
        foreach ($e in $ExtraNames) {
            if ($e -and -not $names.Contains($e)) { [void]$names.Add($e) }
        }
    }
    return @($names.ToArray())
}

function Install-AutoTlsCertificate {
    <#
    .SYNOPSIS
        Gerekirse self-signed TLS sertifikasi olusturur, Root'a guvenir, .cer export eder, RDP'ye baglar.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [string[]]$DnsNames,
        [ValidateRange(1, 30)]
        [int]$YearsValid = 5,
        [switch]$BindRdpTcp,
        [switch]$ForceNew,
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs\certificate-manager.log'
    }
    Set-CertificateLog -Path $LogPath
    $script:CertLogPath = $LogPath

    if (-not $DnsNames -or $DnsNames.Count -lt 1) {
        $DnsNames = Get-AutoTlsDnsNames
    } else {
        $DnsNames = Get-AutoTlsDnsNames -ExtraNames $DnsNames
    }
    if ($DnsNames.Count -lt 1) { $DnsNames = @($env:COMPUTERNAME, 'localhost') }

    $primary = $DnsNames[0]
    $cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
    if (-not (Test-Path -LiteralPath $cfgDir)) {
        New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    }
    $cerSql = Join-Path $cfgDir 'EXFIN-SqlBridge.cer'
    $cerGw  = Join-Path $cfgDir 'EXFIN-RD-Gateway.cer'
    $metaPath = Join-Path $cfgDir 'auto-tls.json'

    # Mevcut uygun sertifika var mi?
    $existing = $null
    if (-not $ForceNew -and (Test-Path -LiteralPath $metaPath)) {
        try {
            $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($meta.thumbprint) {
                $existing = Get-ChildItem -Path "Cert:\LocalMachine\My\$($meta.thumbprint)" -ErrorAction SilentlyContinue
                if ($existing -and $existing.NotAfter -gt (Get-Date).AddDays(30)) {
                    Write-CertificateLogEntry -Message "Reusing auto TLS cert $($existing.Thumbprint)"
                } else { $existing = $null }
            }
        } catch { $existing = $null }
    }

    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess(($DnsNames -join ', '), 'Create auto self-signed TLS certificate')) {
            Write-CertificateLogEntry -Message ("Creating auto TLS cert SAN=[{0}]" -f ($DnsNames -join ', '))
            $existing = New-SelfSignedCertificate `
                -DnsName $DnsNames `
                -CertStoreLocation 'Cert:\LocalMachine\My' `
                -NotAfter (Get-Date).AddYears($YearsValid) `
                -KeyUsage DigitalSignature, KeyEncipherment `
                -KeyAlgorithm RSA `
                -KeyLength 2048 `
                -FriendlyName ("RdpVirtualBoxApp AutoTLS ({0})" -f $primary) `
                -ErrorAction Stop
        } else {
            return $null
        }
    }

    $thumb = $existing.Thumbprint
    Export-Certificate -Cert $existing -FilePath $cerSql -Force | Out-Null
    Copy-Item -LiteralPath $cerSql -Destination $cerGw -Force
    try {
        Import-Certificate -FilePath $cerSql -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
        Write-CertificateLogEntry -Message "Trusted auto TLS cert in LocalMachine\Root"
    } catch {
        Write-CertificateLogEntry -Level Warning -Message "Root trust failed: $($_.Exception.Message)"
    }

    if ($BindRdpTcp) {
        try {
            Set-RdpTcpCertificateBinding -CertificateThumbprint $thumb
        } catch {
            Write-CertificateLogEntry -Level Warning -Message "RDP bind skipped: $($_.Exception.Message)"
        }
    }

    $metaObj = [ordered]@{
        thumbprint = $thumb
        subject    = [string]$existing.Subject
        notAfter   = $existing.NotAfter.ToUniversalTime().ToString('o')
        dnsNames   = @($DnsNames)
        cerPath    = $cerSql
        updatedAt  = (Get-Date).ToUniversalTime().ToString('o')
    }
    ($metaObj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $metaPath -Encoding UTF8

    return [pscustomobject]@{
        Thumbprint        = $thumb
        Subject           = $existing.Subject
        NotAfter          = $existing.NotAfter
        DnsNames          = @($DnsNames)
        CerPath           = $cerSql
        GatewayCerPath    = $cerGw
        BoundToRdpTcp     = [bool]$BindRdpTcp
        DownloadPath      = '/sql-bridge.cer'
    }
}

# Script dogrudan calistirilirsa (sihirbaz: CertificateManager.ps1 SelfSigned)
$isDirectCert = $MyInvocation.InvocationName -ne '.' -and
                $MyInvocation.Line -notmatch '^\s*\.\s+' -and
                $PSCommandPath -and
                $MyInvocation.MyCommand.Path -and
                ($MyInvocation.MyCommand.Path -eq $PSCommandPath)

if ($isDirectCert -and $Mode) {
    try {
        if ($Mode -eq 'SelfSigned') {
            $result = Install-AutoTlsCertificate -BindRdpTcp -DnsNames $(if ($ServerFqdn) { @($ServerFqdn) } else { @() })
            $result | ConvertTo-Json -Depth 5
        } elseif ($Mode -eq 'CA') {
            if (-not $ServerFqdn) { $ServerFqdn = $env:COMPUTERNAME }
            $result = New-RdsCertificate -Mode CA -PfxPath $PfxPath -PfxPassword $PfxPassword -BindRdpTcp:$BindRdpTcp
            $result | Select-Object Thumbprint, Subject, NotAfter, BoundToRdpTcp | ConvertTo-Json -Depth 4
        }
    } catch {
        Write-Error -ErrorRecord $_
        exit 1
    }
}

if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'New-RdsCertificate',
        'Get-RdsCertificate',
        'Remove-RdsCertificate',
        'Get-AutoTlsDnsNames',
        'Install-AutoTlsCertificate'
    )
}