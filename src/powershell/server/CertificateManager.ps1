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

function Initialize-CertificateLog {
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

    Initialize-CertificateLog -Path $LogPath
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

Export-ModuleMember -Function @(
    'New-RdsCertificate',
    'Get-RdsCertificate',
    'Remove-RdsCertificate'
)