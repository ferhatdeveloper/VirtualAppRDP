<#
.SYNOPSIS
    Installs and configures the Remote Desktop Gateway (RD Gateway) role.

.DESCRIPTION
    Performs the following steps:
      1. Installs the RDS-Gateway feature plus management tools.
      2. Assigns a TLS certificate (by thumbprint) to the RD Gateway HTTPS
         listener.
      3. Creates a Connection Authorization Policy (CAP) and a Resource
         Authorization Policy (RAP) so authenticated user groups can
        tunnel RDP traffic to internal session hosts.
      4. Returns the public hostname and listening port (typically 443)
         that clients should use.

.PARAMETER GatewayHostname
    Public FQDN that clients use to reach the gateway.

.PARAMETER GatewayPort
    TCP port the gateway listens on. Defaults to 443.

.PARAMETER CertificateThumbprint
    Thumbprint of the TLS certificate in Cert:\LocalMachine\My.

.PARAMETER AllowedUserGroup
    Name of an Active Directory user group granted access by the CAP.
    Defaults to 'Domain Users'.

.PARAMETER AllowedResourceGroup
    Name of an AD computer group containing the RD Session Hosts that
    clients may connect to through the gateway. Defaults to
    'RD Gateway Managed Servers'.

.PARAMETER LogPath
    Optional path to a log file. Defaults to
    "$env:ProgramData\RdpVirtualBoxApp\Logs\rd-gateway-installer.log".

.EXAMPLE
    Install-RDGateway -GatewayHostname 'gateway.example.com' -CertificateThumbprint 'AABBCC...' -AllowedUserGroup 'Domain Users'

.NOTES
    Author : Rdp Virtual Box App
    Module  : RDGatewayInstaller.ps1
    Tags    : RDS, Gateway, CAP, RAP, TLS
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$GatewayHostname,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$GatewayPort = 443,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [string]$AllowedUserGroup = 'Domain Users',

    [Parameter()]
    [string]$AllowedResourceGroup = 'RD Gateway Managed Servers',

    [Parameter()]
    [string]$LogPath
)

# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------
$script:DefaultCapName = 'RdpVirtualBoxApp-CAP'
$script:DefaultRapName = 'RdpVirtualBoxApp-RAP'

function Initialize-RDGatewayLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

function Write-RDGatewayLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('Info', 'Warning', 'Error', 'Debug')][string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    Add-Content -LiteralPath $script:RdgLogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8

    switch ($Level) {
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning   $Message }
        'Error'   { Write-Error     $Message }
        'Debug'   { Write-Debug     $Message }
    }
}

function Set-RDGatewayCertificate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Thumbprint
    )

    $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction Stop
    if (-not $cert.HasPrivateKey) {
        throw "Certificate $Thumbprint does not contain a private key."
    }

    Write-RDGatewayLogEntry -Message "Assigning certificate $Thumbprint to RD Gateway."
    Set-ItemProperty -LiteralPath 'RDS:\GatewayServer\GatewayServer' -Name 'CertificateThumbprint' -Value $Thumbprint -ErrorAction Stop
    Write-RDGatewayLogEntry -Message "Certificate assignment completed."
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function Install-RDGateway {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GatewayHostname,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$GatewayPort = 443,

        [Parameter()]
        [string]$CertificateThumbprint,

        [Parameter()]
        [string]$AllowedUserGroup = 'Domain Users',

        [Parameter()]
        [string]$AllowedResourceGroup = 'RD Gateway Managed Servers',

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\rd-gateway-installer.log'
    }

    Initialize-RDGatewayLog -Path $LogPath
    $script:RdgLogPath = $LogPath

    try {
        # 1. Install RD Gateway role
        if ($PSCmdlet.ShouldProcess('local computer', 'Install-WindowsFeature RDS-Gateway')) {
            Write-RDGatewayLogEntry -Message 'Installing RDS-Gateway role with management tools.'
            $installResult = Install-WindowsFeature -Name RDS-Gateway -IncludeManagementTools -ErrorAction Stop

            if (-not $installResult.Success) {
                throw "RDS-Gateway installation failed (ExitCode=$($installResult.ExitCode))."
            }
            Write-RDGatewayLogEntry -Message 'RDS-Gateway installation completed successfully.'

            if ($installResult.RestartNeeded) {
                Write-RDGatewayLogEntry -Level Warning -Message 'Restart pending after RDS-Gateway installation.'
            }
        }

        # 2. Assign certificate
        if ($CertificateThumbprint) {
            if ($PSCmdlet.ShouldProcess('RDS Gateway', "Bind certificate $CertificateThumbprint")) {
                try {
                    Set-RDGatewayCertificate -Thumbprint $CertificateThumbprint -ErrorAction Stop
                }
                catch {
                    Write-RDGatewayLogEntry -Level Error -Message "Failed to assign certificate: $($_.Exception.Message)"
                    throw
                }
            }
        }
        else {
            Write-RDGatewayLogEntry -Level Warning -Message 'No certificate thumbprint supplied; gateway will use the default self-signed certificate.'
        }

        # 3. Create Connection Authorization Policy (CAP)
        if ($PSCmdlet.ShouldProcess($AllowedUserGroup, "New RD Gateway CAP '$script:DefaultCapName'")) {
            try {
                $capParams = @{
                    Name                 = $script:DefaultCapName
                    UserGroups           = @($AllowedUserGroup)
                    AuthenticationMethod = 'Password'
                    AllowedConnections   = 'AuthorizedUsers'
                    IdleTimeout          = 15
                    SessionTimeout       = 600
                }

                if (Get-RDConnectionAuthorizationPolicy -Name $capParams['Name'] -ErrorAction SilentlyContinue) {
                    Write-RDGatewayLogEntry -Level Debug -Message "CAP '$($capParams['Name'])' already exists, skipping creation."
                }
                else {
                    New-RDAuthorizationPolicy @capParams -ErrorAction Stop -Type CAP | Out-Null
                    Write-RDGatewayLogEntry -Message "Created CAP '$($capParams['Name'])' for group '$AllowedUserGroup'."
                }
            }
            catch {
                Write-RDGatewayLogEntry -Level Warning -Message "CAP creation failed: $($_.Exception.Message)"
            }
        }

        # 4. Create Resource Authorization Policy (RAP)
        if ($PSCmdlet.ShouldProcess($AllowedResourceGroup, "New RD Gateway RAP '$script:DefaultRapName'")) {
            try {
                $rapParams = @{
                    Name           = $script:DefaultRapName
                    UserGroups     = @($AllowedUserGroup)
                    ComputerGroup  = $AllowedResourceGroup
                    AllowedConnections = 'AuthorizedUsers'
                }

                if (Get-RDResourceAuthorizationPolicy -Name $rapParams['Name'] -ErrorAction SilentlyContinue) {
                    Write-RDGatewayLogEntry -Level Debug -Message "RAP '$($rapParams['Name'])' already exists, skipping creation."
                }
                else {
                    New-RDAuthorizationPolicy @rapParams -ErrorAction Stop -Type RAP | Out-Null
                    Write-RDGatewayLogEntry -Message "Created RAP '$($rapParams['Name'])' for resource group '$AllowedResourceGroup'."
                }
            }
            catch {
                Write-RDGatewayLogEntry -Level Warning -Message "RAP creation failed: $($_.Exception.Message)"
            }
        }

        # 5. Bind policies to the gateway
        if ($PSCmdlet.ShouldProcess('Gateway', 'Assign CAP/RAP')) {
            try {
                $cap = Get-RDConnectionAuthorizationPolicy -Name $script:DefaultCapName -ErrorAction Stop
                $rap = Get-RDResourceAuthorizationPolicy -Name $script:DefaultRapName -ErrorAction Stop

                Set-RDGatewayConfiguration -ConnectionAuthorizationPolicyName $cap.Name -ResourceAuthorizationPolicyName $rap.Name -ErrorAction Stop
                Write-RDGatewayLogEntry -Message "Bound CAP '$($cap.Name)' and RAP '$($rap.Name)' to the gateway."
            }
            catch {
                Write-RDGatewayLogEntry -Level Warning -Message "Policy binding failed: $($_.Exception.Message)"
            }
        }

        return [PSCustomObject]@{
            GatewayHostname    = $GatewayHostname
            GatewayPort        = $GatewayPort
            Endpoint           = "https://$GatewayHostname`:$GatewayPort"
            CertificateThumbprint = $CertificateThumbprint
            CapName            = $script:DefaultCapName
            RapName            = $script:DefaultRapName
            AllowedUserGroup   = $AllowedUserGroup
            AllowedResourceGroup = $AllowedResourceGroup
            LogPath            = $LogPath
        }
    }
    catch {
        Write-RDGatewayLogEntry -Level Error -Message "RD Gateway installation failed: $($_.Exception.Message)"
        throw
    }
}

function Uninstall-RDGateway {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\rd-gateway-installer.log'
    }

    Initialize-RDGatewayLog -Path $LogPath
    $script:RdgLogPath = $LogPath

    try {
        if (Get-RDConnectionAuthorizationPolicy -Name $script:DefaultCapName -ErrorAction SilentlyContinue) {
            Remove-RDAuthorizationPolicy -Name $script:DefaultCapName -ErrorAction Stop -Type CAP
            Write-RDGatewayLogEntry -Message "Removed CAP '$script:DefaultCapName'."
        }
        if (Get-RDResourceAuthorizationPolicy -Name $script:DefaultRapName -ErrorAction SilentlyContinue) {
            Remove-RDAuthorizationPolicy -Name $script:DefaultRapName -ErrorAction Stop -Type RAP
            Write-RDGatewayLogEntry -Message "Removed RAP '$script:DefaultRapName'."
        }
    }
    catch {
        Write-RDGatewayLogEntry -Level Warning -Message "Policy cleanup failed: $($_.Exception.Message)"
    }

    if ($PSCmdlet.ShouldProcess('local computer', 'Uninstall-WindowsFeature RDS-Gateway')) {
        $result = Uninstall-WindowsFeature -Name RDS-Gateway -ErrorAction Stop -Remove
        if (-not $result.Success) {
            Write-RDGatewayLogEntry -Level Error -Message "Uninstall failed (ExitCode=$($result.ExitCode))."
            return $false
        }
        Write-RDGatewayLogEntry -Message 'RDS-Gateway uninstall completed.'
        return $true
    }
}

function Get-RDGatewayStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $feature = Get-WindowsFeature -Name RDS-Gateway -ErrorAction SilentlyContinue
    $cap = Get-RDConnectionAuthorizationPolicy -Name $script:DefaultCapName -ErrorAction SilentlyContinue
    $rap = Get-RDResourceAuthorizationPolicy -Name $script:DefaultRapName -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        Installed   = ($feature -and $feature.InstallState -eq 'Installed')
        CapExists   = ($null -ne $cap)
        RapExists   = ($null -ne $rap)
        RestartNeeded = ($feature -and $feature.InstallState -eq 'InstallPending')
    }
}

Export-ModuleMember -Function @(
    'Install-RDGateway',
    'Uninstall-RDGateway',
    'Get-RDGatewayStatus'
)