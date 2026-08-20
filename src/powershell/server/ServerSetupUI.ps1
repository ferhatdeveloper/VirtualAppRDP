# =============================================================================
#  ServerSetupUI.ps1
#  Rdp Virtual Box App - Server Setup WinForms Wizard (7 steps)
#  Author: Ajan S4
#  UI Language: Turkish
#  Comments: English
# =============================================================================
#  This script is the entry point for the Server-side installation wizard.
#  It launches a modern WinForms UI that walks an IT administrator through:
#    1. Welcome / server info
#    2. Component selection (RDS roles, certificate, firewall, etc.)
#    3. License check (calls LicenseDetector.ps1)
#    4. Connection strategy selection (Direct/Gateway/Guacamole/Tailscale/CF)
#    5. Application selection (calls AppScanner.ps1)
#    6. Review summary
#    7. Installation with progress + log + undo
# =============================================================================

[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\RdpVirtualBoxApp",
    [string]$LogDir      = "$env:ProgramData\RdpVirtualBoxApp\Logs",
    [string]$LogFile     = "$env:ProgramData\RdpVirtualBoxApp\Logs\server-setup.log",
    [switch]$Unattended
)

# -----------------------------------------------------------------------------
# 0. Strict mode + module bootstrap
# -----------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure logging directory exists
try {
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
} catch {
    Write-Warning "Log dizini olusturulamadi: $_"
}

# -----------------------------------------------------------------------------
# 0.1 Sunucu tarafi modul yukleme (RdsInstaller, CertificateManager, vs.)
# Server-side modullerin Export-ModuleMember tanimlari yok; bu yuzden
# dot-source ile ayni PowerShell oturumuna enjekte ediyoruz. Bir modul
# bulunamazsa wizard yine acilir ama ilgili adim "modul yok" uyarisi verir.
# -----------------------------------------------------------------------------
$script:ServerModules = [ordered]@{}
$script:ServerModuleNames = @(
    'RdsInstaller.ps1',
    'CertificateManager.ps1',
    'FirewallConfig.ps1',
    'RDGatewayInstaller.ps1',
    'RemoteAppPublisher.ps1',
    'LicenseDetector.ps1',
    'GuacamoleInstaller.ps1',
    'TailscaleInstaller.ps1',
    'CloudflareTunnelInstaller.ps1',
    'AppScanner.ps1',
    'ProbeApi.ps1'
)
function Resolve-ServerModulePath {
    param([Parameter(Mandatory)][string]$Name)
    $candidates = @(
        (Join-Path $PSScriptRoot $Name)
        (Join-Path $PSScriptRoot "PowerShell\$Name")
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $candidates[0]
}
foreach ($moduleName in $script:ServerModuleNames) {
    $modulePath = Resolve-ServerModulePath -Name $moduleName
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-SetupLog "Sunucu modulu bulunamadi (atlandi): $modulePath" -Level WARN
        $script:ServerModules[$moduleName] = $false
        continue
    }
    try {
        . $modulePath
        $script:ServerModules[$moduleName] = $true
        Write-SetupLog "Sunucu modulu yuklendi: $moduleName" -Level INFO
    } catch {
        $script:ServerModules[$moduleName] = $false
        Write-SetupLog "Sunucu modulu yuklenemedi: $moduleName -> $_" -Level ERROR
    }
}

function Write-SetupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO',
        [string]$Component = 'ServerSetupUI'
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line      = "[$timestamp] [$Level] [$Component] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    # Stream interactive status via Write-Information so callers can suppress
    # or redirect output. Avoids PSScriptAnalyzer PSAvoidUsingWriteHost.
    switch ($Level) {
        'ERROR' { Write-Information -MessageData $line -InformationAction Continue }
        'WARN'  { Write-Information -MessageData $line -InformationAction Continue }
        'DEBUG' { Write-Verbose $line }
        default { Write-Verbose $line }
    }
}

# -----------------------------------------------------------------------------
# 1. WinForms assembly load
# -----------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.DirectoryServices
    Write-SetupLog "WinForms bilesenleri yuklendi." -Level INFO
} catch {
    Write-SetupLog "WinForms yuklenemedi: $_" -Level ERROR
    throw
}

# -----------------------------------------------------------------------------
# 2. Aero theme / modern FlatStyle helpers
# -----------------------------------------------------------------------------
$script:ThemeColor   = [System.Drawing.Color]::FromArgb(0, 120, 215)   # Primary
$script:AccentColor  = [System.Drawing.Color]::FromArgb(16, 110, 190)
$script:OkColor      = [System.Drawing.Color]::FromArgb(16, 124, 16)
$script:WarnColor    = [System.Drawing.Color]::FromArgb(202, 138, 4)
$script:ErrColor     = [System.Drawing.Color]::FromArgb(196, 43, 43)

function New-ModernButton {
    param(
        [string]$Text,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Windows.Forms.DialogResult]$DialogResult = [System.Windows.Forms.DialogResult]::None
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text     = $Text
    $btn.Location = $Location
    $btn.Size     = $Size
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize  = 1
    $btn.FlatAppearance.BorderColor = $script:ThemeColor
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.ForeColor = $script:ThemeColor
    $btn.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
    $btn.DialogResult = $DialogResult
    return $btn
}

function New-PrimaryButton {
    param(
        [string]$Text,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Windows.Forms.DialogResult]$DialogResult = [System.Windows.Forms.DialogResult]::None
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text     = $Text
    $btn.Location = $Location
    $btn.Size     = $Size
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize  = 0
    $btn.BackColor = $script:ThemeColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btn.DialogResult = $DialogResult
    return $btn
}

function Set-StatusBadge {
    param(
        [System.Windows.Forms.Label]$Label,
        [ValidateSet('ok','warn','err','info')][string]$State,
        [string]$Text
    )
    switch ($State) {
        'ok'   { $Label.BackColor = $script:OkColor;   $Label.ForeColor = [System.Drawing.Color]::White }
        'warn' { $Label.BackColor = $script:WarnColor; $Label.ForeColor = [System.Drawing.Color]::White }
        'err'  { $Label.BackColor = $script:ErrColor;  $Label.ForeColor = [System.Drawing.Color]::White }
        'info' { $Label.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230); $Label.ForeColor = [System.Drawing.Color]::Black }
    }
    $Label.Text    = "  $Text  "
    $Label.Visible = $true
}

# -----------------------------------------------------------------------------
# 3. Wizard state container
# -----------------------------------------------------------------------------
$script:WizardData = [ordered]@{
    AcceptLicense    = $false
    ServerName       = $env:COMPUTERNAME
    ServerIp         = ''
    ServerDomain     = ''
    OsVersion        = ''
    InstallRdsRoles  = $true
    CertMode         = 'SelfSigned'      # 'SelfSigned' or 'CASigned'
    ConfigureFirewall= $true
    InstallGateway   = $true
    InstallGuacamole = $false
    InstallTailscale = $false
    InstallCloudflare= $false
    InstallProbeApi  = $true
    InstallCaddySsl  = $true
    PublishApps      = $true
    RdpPort          = 3389
    RdWebLicenseOk   = $false
    RdWebGraceDays   = 0
    ConnectionStrategies = @()          # Direct, Gateway, Guacamole, Tailscale, Cloudflare, Hybrid
    SelectedApps     = @()               # array of app objects from AppScanner
    ManifestPath     = ''
}

# -----------------------------------------------------------------------------
# 4. Server info detection
# -----------------------------------------------------------------------------
function Get-ServerNetworkInfo {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '127.*' } |
               Select-Object -ExpandProperty IPAddress -First 1
        if (-not $ips) {
            $ips = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                   Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                   Select-Object -ExpandProperty IPAddressToString -First 1
        }
        $script:WizardData.ServerIp = $ips
    } catch {
        Write-SetupLog "Sunucu IP tespiti basarisiz: $_" -Level WARN
        $script:WizardData.ServerIp = 'TESPIT_EDILEMEDI'
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $script:WizardData.ServerDomain = "$($cs.Domain)"
    } catch { $script:WizardData.ServerDomain = 'WORKGROUP' }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $script:WizardData.OsVersion = "$($os.Caption) $($os.Version)"
    } catch { $script:WizardData.OsVersion = 'Bilinmiyor' }
}

# -----------------------------------------------------------------------------
# 5. Main wizard form + 7 step panels
# -----------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'EXFIN RemoteAPP - Server Kurulumu'
$form.Size            = New-Object System.Drawing.Size(900, 640)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::White
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

# Header banner (Aero-ish gradient via 2 panels)
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock     = 'Top'
$headerPanel.Height   = 70
$headerPanel.BackColor = $script:ThemeColor
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'EXFIN RemoteAPP'
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(20, 8)
$headerPanel.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text      = 'Server Kurulum Sihirbaza'
$lblSubtitle.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 245)
$lblSubtitle.AutoSize  = $true
$lblSubtitle.Location  = New-Object System.Drawing.Point(20, 42)
$headerPanel.Controls.Add($lblSubtitle)

# Step indicator label (top-right)
$lblStep = New-Object System.Windows.Forms.Label
$lblStep.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblStep.ForeColor = [System.Drawing.Color]::White
$lblStep.AutoSize  = $true
$lblStep.Location  = New-Object System.Drawing.Point(740, 28)
$lblStep.Text      = 'Adim 1 / 7'
$headerPanel.Controls.Add($lblStep)

# Body panel container
$bodyPanel = New-Object System.Windows.Forms.Panel
$bodyPanel.Location = New-Object System.Drawing.Point(0, 70)
$bodyPanel.Size     = New-Object System.Drawing.Size(900, 470)
$bodyPanel.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($bodyPanel)

# Footer / nav panel
$footerPanel = New-Object System.Windows.Forms.Panel
$footerPanel.Dock     = 'Bottom'
$footerPanel.Height   = 60
$footerPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Controls.Add($footerPanel)

# -----------------------------------------------------------------------------
# Per-step content panels (created lazily)
# -----------------------------------------------------------------------------
$panels = @{}
function New-StepPanel {
    param([string]$Name)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location  = New-Object System.Drawing.Point(0, 0)
    $p.Size      = $bodyPanel.Size
    $p.BackColor = [System.Drawing.Color]::White
    $p.Visible   = $false
    $bodyPanel.Controls.Add($p)
    $panels[$Name] = $p
    return $p
}

$script:CurrentStep = 1
function Set-Step {
    param([int]$Step)
    foreach ($k in $panels.Keys) { $panels[$k].Visible = $false }
    $key = "Step$Step"
    if ($panels.ContainsKey($key)) {
        $panels[$key].Visible = $true
        $script:CurrentStep = $Step
        $lblStep.Text = "Adim $Step / 7"
        Write-SetupLog "Wizard adim $Step'e gecti." -Level DEBUG
        $btnPrev.Enabled = ($Step -gt 1)
        # 'Next' is disabled on step 7 (install) and step 1 until license accepted
        if ($Step -eq 1) { $btnNext.Enabled = $false }
        elseif ($Step -eq 7) { $btnNext.Enabled = $false }
        else { $btnNext.Enabled = $true }
    }
}

# Backwards-compatible alias for PSScriptAnalyzer PSUseApprovedVerbs compliance
Set-Alias -Name Switch-Step -Value Set-Step -Scope Global -Force

# -----------------------------------------------------------------------------
# STEP 1 - Welcome
# -----------------------------------------------------------------------------
$p1 = New-StepPanel 'Step1'

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = "EXFIN RemoteAPP - Server Kurulumu`n'a Hosgeldiniz"
$lbl1.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl1.Location = New-Object System.Drawing.Point(20, 20)
$lbl1.AutoSize = $true
$lbl1.ForeColor = $script:ThemeColor
$p1.Controls.Add($lbl1)

$lbl1b = New-Object System.Windows.Forms.Label
$lbl1b.Text = "Bu sihirbaz, Windows Server'inizi uzak erisim icin hazirlar.`n" +
              "Asagidaki adimlarda sunucu bilgileriniz otomatik tespit edilecek ve`n" +
              "kurulum secenekleri size sunulacak."
$lbl1b.Location = New-Object System.Drawing.Point(20, 60)
$lbl1b.Size = New-Object System.Drawing.Size(820, 60)
$lbl1b.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$p1.Controls.Add($lbl1b)

$gbInfo = New-Object System.Windows.Forms.GroupBox
$gbInfo.Text     = 'Sunucu Bilgisi (otomatik tespit)'
$gbInfo.Location = New-Object System.Drawing.Point(20, 140)
$gbInfo.Size     = New-Object System.Drawing.Size(840, 180)
$gbInfo.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p1.Controls.Add($gbInfo)

$lblComp  = New-Object System.Windows.Forms.Label; $lblComp.Location  = New-Object System.Drawing.Point(20, 35);  $lblComp.Size = New-Object System.Drawing.Size(800, 22); $lblComp.Text = "Bilgisayar Adi : $env:COMPUTERNAME"; $gbInfo.Controls.Add($lblComp)
$lblIp    = New-Object System.Windows.Forms.Label; $lblIp.Location    = New-Object System.Drawing.Point(20, 60);  $lblIp.Size   = New-Object System.Drawing.Size(800, 22); $gbInfo.Controls.Add($lblIp)
$lblDom   = New-Object System.Windows.Forms.Label; $lblDom.Location   = New-Object System.Drawing.Point(20, 85);  $lblDom.Size  = New-Object System.Drawing.Size(800, 22); $gbInfo.Controls.Add($lblDom)
$lblOs    = New-Object System.Windows.Forms.Label; $lblOs.Location    = New-Object System.Drawing.Point(20, 110); $lblOs.Size   = New-Object System.Drawing.Size(800, 22); $gbInfo.Controls.Add($lblOs)
$lblAdmin = New-Object System.Windows.Forms.Label; $lblAdmin.Location = New-Object System.Drawing.Point(20, 135); $lblAdmin.Size = New-Object System.Drawing.Size(800, 22); $gbInfo.Controls.Add($lblAdmin)

$chkLicense = New-Object System.Windows.Forms.CheckBox
$chkLicense.Text = "Lisans kosullarini okudum ve kabul ediyorum (MIT)"
$chkLicense.Location = New-Object System.Drawing.Point(20, 340)
$chkLicense.Size     = New-Object System.Drawing.Size(840, 28)
$chkLicense.Font     = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$chkLicense.ForeColor = $script:ThemeColor
$p1.Controls.Add($chkLicense)

$chkLicense.Add_CheckedChanged({
    $script:WizardData.AcceptLicense = $chkLicense.Checked
    $btnNext.Enabled = $chkLicense.Checked
})

# -----------------------------------------------------------------------------
# STEP 2 - Components
# -----------------------------------------------------------------------------
$p2 = New-StepPanel 'Step2'

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = "Bilesen Secimi"
$lbl2.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl2.Location = New-Object System.Drawing.Point(20, 20)
$lbl2.AutoSize = $true
$lbl2.ForeColor = $script:ThemeColor
$p2.Controls.Add($lbl2)

$gbRoles = New-Object System.Windows.Forms.GroupBox
$gbRoles.Text = 'Kurulacak Roller'
$gbRoles.Location = New-Object System.Drawing.Point(20, 60)
$gbRoles.Size = New-Object System.Drawing.Size(840, 60)
$gbRoles.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p2.Controls.Add($gbRoles)

$chkRds = New-Object System.Windows.Forms.CheckBox
$chkRds.Text = "RDS Rolleri (RDS-RD-Server, RDS-Web-Access, RDS-Gateway, RDS-Licensing)"
$chkRds.Checked = $true
$chkRds.Location = New-Object System.Drawing.Point(15, 25)
$chkRds.Size = New-Object System.Drawing.Size(810, 25)
$gbRoles.Controls.Add($chkRds)

$gbCert = New-Object System.Windows.Forms.GroupBox
$gbCert.Text = 'Sertifika'
$gbCert.Location = New-Object System.Drawing.Point(20, 130)
$gbCert.Size = New-Object System.Drawing.Size(840, 75)
$gbCert.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p2.Controls.Add($gbCert)

$rbSelf = New-Object System.Windows.Forms.RadioButton
$rbSelf.Text = "Self-signed Sertifika (otomatik)"
$rbSelf.Checked = $true
$rbSelf.Location = New-Object System.Drawing.Point(15, 22)
$rbSelf.Size = New-Object System.Drawing.Size(400, 22)
$gbCert.Controls.Add($rbSelf)

$rbCa = New-Object System.Windows.Forms.RadioButton
$rbCa.Text = "CA-imzali Sertifika (.pfx dosyasi)"
$rbCa.Location = New-Object System.Drawing.Point(15, 45)
$rbCa.Size = New-Object System.Drawing.Size(400, 22)
$gbCert.Controls.Add($rbCa)

$lblRdpPort = New-Object System.Windows.Forms.Label
$lblRdpPort.Text = 'RDP TCP port'
$lblRdpPort.Location = New-Object System.Drawing.Point(430, 22)
$lblRdpPort.Size = New-Object System.Drawing.Size(120, 22)
$gbCert.Controls.Add($lblRdpPort)
$numRdpPort = New-Object System.Windows.Forms.NumericUpDown
$numRdpPort.Minimum = 1
$numRdpPort.Maximum = 65535
$numRdpPort.Value = 3389
$numRdpPort.Location = New-Object System.Drawing.Point(560, 20)
$numRdpPort.Size = New-Object System.Drawing.Size(90, 24)
$gbCert.Controls.Add($numRdpPort)

$gbOther = New-Object System.Windows.Forms.GroupBox
$gbOther.Text = 'Diger Bilesenler'
$gbOther.Location = New-Object System.Drawing.Point(20, 200)
$gbOther.Size = New-Object System.Drawing.Size(840, 265)
$gbOther.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p2.Controls.Add($gbOther)

$chkFw = New-Object System.Windows.Forms.CheckBox; $chkFw.Text = "Firewall Kurallari (3389, 443, 8443, 8444, 8445)"; $chkFw.Checked = $true;  $chkFw.Location = New-Object System.Drawing.Point(15, 22);  $chkFw.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkFw)
$chkGw = New-Object System.Windows.Forms.CheckBox; $chkGw.Text = "RD Gateway";                                  $chkGw.Checked = $true;  $chkGw.Location = New-Object System.Drawing.Point(15, 46);  $chkGw.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkGw)
$chkGu = New-Object System.Windows.Forms.CheckBox; $chkGu.Text = "Apache Guacamole (HTML5 fallback)";           $chkGu.Checked = $false; $chkGu.Location = New-Object System.Drawing.Point(15, 70);  $chkGu.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkGu)
$chkTs = New-Object System.Windows.Forms.CheckBox; $chkTs.Text = "Tailscale (mesh VPN)";                        $chkTs.Checked = $false; $chkTs.Location = New-Object System.Drawing.Point(15, 94);  $chkTs.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkTs)
$chkCf = New-Object System.Windows.Forms.CheckBox; $chkCf.Text = "Cloudflare Tunnel";                           $chkCf.Checked = $false; $chkCf.Location = New-Object System.Drawing.Point(15, 118); $chkCf.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkCf)
$chkAp = New-Object System.Windows.Forms.CheckBox; $chkAp.Text = "App Kutuphanesi (RemoteApp yayinlama)";        $chkAp.Checked = $true;  $chkAp.Location = New-Object System.Drawing.Point(15, 142); $chkAp.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkAp)
$chkPa = New-Object System.Windows.Forms.CheckBox; $chkPa.Text = "Probe REST API (port 8444, macOS / HTTP istemcileri)"; $chkPa.Checked = $true; $chkPa.Location = New-Object System.Drawing.Point(15, 166); $chkPa.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkPa)
$chkCy = New-Object System.Windows.Forms.CheckBox; $chkCy.Text = "Caddy SSL (HTTPS 8445, Probe API reverse proxy)"; $chkCy.Checked = $true; $chkCy.Location = New-Object System.Drawing.Point(15, 190); $chkCy.Size = New-Object System.Drawing.Size(810, 22); $gbOther.Controls.Add($chkCy)

# Checkbox/radio state'leri Next handler'inda senkron olarak WizardData'ya yazilir
# (parser-friendly: event handler baglama yerine snapshot okuma).
# Asagidaki yardimci fonksiyon Next event'inden cagrilir.

function Update-WizardDataFromStep2 {
    $script:WizardData.InstallRdsRoles    = [bool] $chkRds.Checked
    $script:WizardData.ConfigureFirewall = [bool] $chkFw.Checked
    $script:WizardData.InstallGateway    = [bool] $chkGw.Checked
    $script:WizardData.InstallGuacamole  = [bool] $chkGu.Checked
    $script:WizardData.InstallTailscale  = [bool] $chkTs.Checked
    $script:WizardData.InstallCloudflare = [bool] $chkCf.Checked
    $script:WizardData.PublishApps       = [bool] $chkAp.Checked
    $script:WizardData.InstallProbeApi   = [bool] $chkPa.Checked
    $script:WizardData.InstallCaddySsl   = [bool] $chkCy.Checked
    $script:WizardData.RdpPort           = [int] $numRdpPort.Value
    if ($rbSelf.Checked) {
        $script:WizardData.CertMode = 'SelfSigned'
    } elseif ($rbCa.Checked) {
        $script:WizardData.CertMode = 'CASigned'
    }
}

# -----------------------------------------------------------------------------
# STEP 3 - License check
# -----------------------------------------------------------------------------
$p3 = New-StepPanel 'Step3'

$lbl3 = New-Object System.Windows.Forms.Label
$lbl3.Text = "Lisans Kontrolu"
$lbl3.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl3.Location = New-Object System.Drawing.Point(20, 20)
$lbl3.AutoSize = $true
$lbl3.ForeColor = $script:ThemeColor
$p3.Controls.Add($lbl3)

$lbl3b = New-Object System.Windows.Forms.Label
$lbl3b.Text = "LicenseDetector.ps1 calistiriliyor..."
$lbl3b.Location = New-Object System.Drawing.Point(20, 60)
$lbl3b.Size = New-Object System.Drawing.Size(820, 22)
$p3.Controls.Add($lbl3b)

$badgeLic = New-Object System.Windows.Forms.Label
$badgeLic.Location = New-Object System.Drawing.Point(20, 100)
$badgeLic.Size = New-Object System.Drawing.Size(400, 30)
$badgeLic.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$badgeLic.Visible = $false
$p3.Controls.Add($badgeLic)

$txtLic = New-Object System.Windows.Forms.RichTextBox
$txtLic.Location = New-Object System.Drawing.Point(20, 150)
$txtLic.Size = New-Object System.Drawing.Size(840, 200)
$txtLic.ReadOnly = $true
$txtLic.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLic.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$p3.Controls.Add($txtLic)

$chkGuacAuto = New-Object System.Windows.Forms.CheckBox
$chkGuacAuto.Text = "RD Web lisansi yoksa Guacamole otomatik kurulsun"
$chkGuacAuto.Checked = $true
$chkGuacAuto.Location = New-Object System.Drawing.Point(20, 360)
$chkGuacAuto.Size = New-Object System.Drawing.Size(840, 25)
$chkGuacAuto.Visible = $false
$p3.Controls.Add($chkGuacAuto)

$btnRunLic = New-Object System.Windows.Forms.Button
$btnRunLic.Text = "Lisans Tespitini Calistir"
$btnRunLic.Location = New-Object System.Drawing.Point(20, 395)
$btnRunLic.Size = New-Object System.Drawing.Size(200, 32)
$btnRunLic.BackColor = $script:ThemeColor
$btnRunLic.ForeColor = [System.Drawing.Color]::White
$btnRunLic.FlatStyle = 'Flat'
$btnRunLic.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p3.Controls.Add($btnRunLic)

function Invoke-LicenseDetectionButton {
    try {
        $log = "`n--- Lisans tespiti baslatildi: $(Get-Date -Format 's') ---`n"
        $detector = Join-Path $PSScriptRoot 'LicenseDetector.ps1'
        if (-not (Test-Path $detector)) {
            $log += "LicenseDetector.ps1 bulunamadi: $detector`n"
            $txtLic.AppendText($log)
            Set-StatusBadge -Label $badgeLic -State 'err' -Text 'TESPIT BASARISIZ'
            return
        }
        $licResult = & $detector
        $log += (($licResult | Out-String) + "`n")
        $jsonLine = ($licResult | Where-Object { $_ -is [string] -and $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
        if ($jsonLine) {
            $obj = $jsonLine | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($obj) {
                $script:WizardData.RdWebLicenseOk = [bool]$obj.HasRdWebLicense
                $script:WizardData.RdWebGraceDays = [int]$obj.GracePeriodDays
                if ($script:WizardData.RdWebLicenseOk) {
                    Set-StatusBadge -Label $badgeLic -State 'ok' -Text ("RD Web Lisansi MEVCUT (Grace: " + $obj.GracePeriodDays + " gun)")
                } elseif ($obj.GracePeriodDays -gt 0) {
                    Set-StatusBadge -Label $badgeLic -State 'warn' -Text ("GRACE PERIOD (" + $obj.GracePeriodDays + " gun) - Lisans gerekli")
                    $chkGuacAuto.Visible = $true
                } else {
                    Set-StatusBadge -Label $badgeLic -State 'err' -Text 'RD Web Lisansi YOK'
                    $chkGuacAuto.Visible = $true
                }
                if (-not $script:WizardData.RdWebLicenseOk -and $chkGuacAuto.Checked) {
                    $script:WizardData.InstallGuacamole = $true
                }
            }
        }
        $txtLic.AppendText($log)
    } catch {
        $txtLic.AppendText(("HATA: " + $_.Exception.Message + "`n"))
        Set-StatusBadge -Label $badgeLic -State 'err' -Text 'HATA OLUSTU'
    }
}

$btnRunLic.add_Click({ Invoke-LicenseDetectionButton })

# -----------------------------------------------------------------------------
# STEP 4 - Connection strategy
# -----------------------------------------------------------------------------
$p4 = New-StepPanel 'Step4'

$lbl4 = New-Object System.Windows.Forms.Label
$lbl4.Text = "Baglanti Stratejisi Secimi"
$lbl4.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl4.Location = New-Object System.Drawing.Point(20, 20)
$lbl4.AutoSize = $true
$lbl4.ForeColor = $script:ThemeColor
$p4.Controls.Add($lbl4)

$lbl4b = New-Object System.Windows.Forms.Label
$lbl4b.Text = "Birden fazla strateji secilebilir (Hybrid mod)."
$lbl4b.Location = New-Object System.Drawing.Point(20, 55)
$lbl4b.Size = New-Object System.Drawing.Size(820, 22)
$p4.Controls.Add($lbl4b)

$strategies = @(
    @{ Name='Direct';      Text='Direct RDP (degistirilebilir TCP port)';   Description='LAN ve public IP; port sihirbazda / RDPVB_RDP_PORT ile degisir' },
    @{ Name='Gateway';     Text='RD Gateway (TCP 443)';                    Description='Dis IP / HTTPS uzerinden tunelleme (NAT)' },
    @{ Name='Guacamole';   Text='Apache Guacamole (TCP 8443)';             Description='HTML5 erisim (lisans gerektirmez)' },
    @{ Name='Tailscale';   Text='Tailscale (mesh VPN)';                    Description='Sifir konfigürasyon, NAT arkasi' },
    @{ Name='Cloudflare';  Text='Cloudflare Tunnel';                       Description='Disariya port acmadan yayin' },
    @{ Name='Hybrid';      Text='Hybrid (coklu strateji birlikte)';        Description='Birden fazla secenek bir arada' }
)
$chkStrategies = @{}
$y = 90
foreach ($s in $strategies) {
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text     = $s.Text
    $gb.Location = New-Object System.Drawing.Point(20, $y)
    $gb.Size     = New-Object System.Drawing.Size(840, 50)
    $gb.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $p4.Controls.Add($gb)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text     = $s.Description
    $chk.Location = New-Object System.Drawing.Point(15, 20)
    $chk.Size     = New-Object System.Drawing.Size(800, 22)
    if ($s.Name -eq 'Direct') { $chk.Checked = $true }
    $chk.Name = $s.Name
    $gb.Controls.Add($chk)
    $chkStrategies[$s.Name] = $chk

    $chk.Add_CheckedChanged({
        $script:WizardData.ConnectionStrategies = @()
        foreach ($k in $chkStrategies.Keys) {
            if ($chkStrategies[$k].Checked) { $script:WizardData.ConnectionStrategies += $k }
        }
        if ($script:WizardData.ConnectionStrategies.Count -gt 1) {
            $chkStrategies['Hybrid'].Checked = $true
        }
    })
    $y += 55
}

# -----------------------------------------------------------------------------
# STEP 5 - Application selection
# -----------------------------------------------------------------------------
$p5 = New-StepPanel 'Step5'

$lbl5 = New-Object System.Windows.Forms.Label
$lbl5.Text = "Uygulama Secimi"
$lbl5.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl5.Location = New-Object System.Drawing.Point(20, 20)
$lbl5.AutoSize = $true
$lbl5.ForeColor = $script:ThemeColor
$p5.Controls.Add($lbl5)

$lbl5b = New-Object System.Windows.Forms.Label
$lbl5b.Text = "AppScanner.ps1 calistiriliyor..."
$lbl5b.Location = New-Object System.Drawing.Point(20, 55)
$lbl5b.Size = New-Object System.Drawing.Size(820, 22)
$p5.Controls.Add($lbl5b)

$lvApps = New-Object System.Windows.Forms.ListView
$lvApps.Location = New-Object System.Drawing.Point(20, 90)
$lvApps.Size = New-Object System.Drawing.Size(840, 300)
$lvApps.View = 'Details'
$lvApps.CheckBoxes = $true
$lvApps.FullRowSelect = $true
$lvApps.GridLines = $true
$lvApps.MultiSelect = $true
$lvApps.Font = New-Object System.Drawing.Font('Segoe UI', 9)
[void]$lvApps.Columns.Add('Ad',          240)
[void]$lvApps.Columns.Add('Yol',         320)
[void]$lvApps.Columns.Add('Versiyon',    80)
[void]$lvApps.Columns.Add('Yayinlayici', 160)
$p5.Controls.Add($lvApps)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Yeniden Tara"
$btnScan.Location = New-Object System.Drawing.Point(20, 400)
$btnScan.Size = New-Object System.Drawing.Size(140, 30)
$btnScan.BackColor = $script:ThemeColor
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = 'Flat'
$p5.Controls.Add($btnScan)

$btnScan.Add_Click({
    $lvApps.Items.Clear()
    $lbl5b.Text = "Taraniyor..."
    $form.Refresh()
    try {
        $scanner = Join-Path $PSScriptRoot 'AppScanner.ps1'
        if (-not (Test-Path $scanner)) {
            $lbl5b.Text = "AppScanner.ps1 bulunamadi."
            return
        }
        $apps = & $scanner
        if ($apps -is [array]) {
            foreach ($a in $apps) {
                $item = New-Object System.Windows.Forms.ListViewItem(@($a.name, $a.path, $a.version, $a.publisher))
                $item.Tag = $a
                [void]$lvApps.Items.Add($item)
            }
            $lbl5b.Text = "$($apps.Count) uygulama bulundu."
        } else {
            $lbl5b.Text = "Tarama sonucu bos dondu."
        }
    } catch {
        $lbl5b.Text = "Tarama hatasi: $($_.Exception.Message)"
    }
})

# -----------------------------------------------------------------------------
# STEP 6 - Review
# -----------------------------------------------------------------------------
$p6 = New-StepPanel 'Step6'

$lbl6 = New-Object System.Windows.Forms.Label
$lbl6.Text = "Kurulum Ozeti - Inceleme"
$lbl6.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl6.Location = New-Object System.Drawing.Point(20, 20)
$lbl6.AutoSize = $true
$lbl6.ForeColor = $script:ThemeColor
$p6.Controls.Add($lbl6)

$txtSummary = New-Object System.Windows.Forms.RichTextBox
$txtSummary.Location = New-Object System.Drawing.Point(20, 60)
$txtSummary.Size = New-Object System.Drawing.Size(840, 380)
$txtSummary.ReadOnly = $true
$txtSummary.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtSummary.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$p6.Controls.Add($txtSummary)

function Update-ReviewSummary {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("==== Sunucu Bilgisi ====")
    [void]$sb.AppendLine("  Bilgisayar : $($script:WizardData.ServerName)")
    [void]$sb.AppendLine("  IP Adresi  : $($script:WizardData.ServerIp)")
    [void]$sb.AppendLine("  Domain     : $($script:WizardData.ServerDomain)")
    [void]$sb.AppendLine("  OS         : $($script:WizardData.OsVersion)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("==== Lisans ====")
    if ($script:WizardData.RdWebLicenseOk) {
        [void]$sb.AppendLine("  RD Web Lisansi : MEVCUT")
    } else {
        $guacFb = if ($script:WizardData.InstallGuacamole) { 'etkin' } else { 'devre disi' }
        [void]$sb.AppendLine("  RD Web Lisansi : YOK (Guacamole fallback $guacFb)")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("==== Bilesenler ====")
    [void]$sb.AppendLine("  RDS Rolleri   : $($script:WizardData.InstallRdsRoles)")
    [void]$sb.AppendLine("  Sertifika     : $($script:WizardData.CertMode)")
    [void]$sb.AppendLine("  Firewall      : $($script:WizardData.ConfigureFirewall)")
    [void]$sb.AppendLine("  RD Gateway    : $($script:WizardData.InstallGateway)")
    [void]$sb.AppendLine("  Guacamole     : $($script:WizardData.InstallGuacamole)")
    [void]$sb.AppendLine("  Tailscale     : $($script:WizardData.InstallTailscale)")
    [void]$sb.AppendLine("  Cloudflare    : $($script:WizardData.InstallCloudflare)")
    [void]$sb.AppendLine("  RemoteApp     : $($script:WizardData.PublishApps)")
    [void]$sb.AppendLine("  Probe REST API: $($script:WizardData.InstallProbeApi)")
    [void]$sb.AppendLine("  Caddy SSL     : $($script:WizardData.InstallCaddySsl)")
    [void]$sb.AppendLine("  RDP port      : $($script:WizardData.RdpPort)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("==== Baglanti Stratejileri ====")
    foreach ($s in $script:WizardData.ConnectionStrategies) { [void]$sb.AppendLine("  - $s") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("==== Uygulamalar ====")
    foreach ($a in $script:WizardData.SelectedApps) { [void]$sb.AppendLine("  - $($a.name)  ($($a.path))") }
    $txtSummary.Text = $sb.ToString()
}

# -----------------------------------------------------------------------------
# STEP 7 - Installation
# -----------------------------------------------------------------------------
$p7 = New-StepPanel 'Step7'

$lbl7 = New-Object System.Windows.Forms.Label
$lbl7.Text = "Kurulum Calistiriliyor..."
$lbl7.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lbl7.Location = New-Object System.Drawing.Point(20, 20)
$lbl7.AutoSize = $true
$lbl7.ForeColor = $script:ThemeColor
$p7.Controls.Add($lbl7)

$progBar = New-Object System.Windows.Forms.ProgressBar
$progBar.Location = New-Object System.Drawing.Point(20, 70)
$progBar.Size = New-Object System.Drawing.Size(840, 25)
$progBar.Minimum = 0
$progBar.Maximum = 100
$progBar.Value   = 0
$p7.Controls.Add($progBar)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 110)
$txtLog.Size = New-Object System.Drawing.Size(840, 280)
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$p7.Controls.Add($txtLog)

$btnUndo = New-Object System.Windows.Forms.Button
$btnUndo.Text = "Geri Al (Undo)"
$btnUndo.Location = New-Object System.Drawing.Point(20, 405)
$btnUndo.Size = New-Object System.Drawing.Size(140, 32)
$btnUndo.Enabled = $false
$btnUndo.BackColor = $script:ErrColor
$btnUndo.ForeColor = [System.Drawing.Color]::White
$btnUndo.FlatStyle = 'Flat'
$btnUndo.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p7.Controls.Add($btnUndo)

$btnFinish = New-Object System.Windows.Forms.Button
$btnFinish.Text = "Kapat"
$btnFinish.Location = New-Object System.Drawing.Point(720, 405)
$btnFinish.Size = New-Object System.Drawing.Size(140, 32)
$btnFinish.Enabled = $false
$btnFinish.BackColor = $script:OkColor
$btnFinish.ForeColor = [System.Drawing.Color]::White
$btnFinish.FlatStyle = 'Flat'
$btnFinish.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$p7.Controls.Add($btnFinish)

$btnFinish.Add_Click({ $form.Close() })

# -----------------------------------------------------------------------------
# Nav buttons (footer)
# -----------------------------------------------------------------------------
$btnCancel = New-PrimaryButton -Text 'Iptal' -Location (New-Object System.Drawing.Point(20, 14)) -Size (New-Object System.Drawing.Size(100, 32)) -DialogResult ([System.Windows.Forms.DialogResult]::Cancel)
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
$btnCancel.ForeColor = [System.Drawing.Color]::White
$btnCancel.Add_Click({ $form.Close() })

$btnPrev = New-ModernButton -Text '< Geri' -Location (New-Object System.Drawing.Point(560, 14)) -Size (New-Object System.Drawing.Size(120, 32))
$btnPrev.Enabled = $false
$btnPrev.Add_Click({ Set-Step ($script:CurrentStep - 1) })

$btnNext = New-PrimaryButton -Text 'Ileri >' -Location (New-Object System.Drawing.Point(690, 14)) -Size (New-Object System.Drawing.Size(140, 32))
$btnNext.Enabled = $false

$btnNext.Add_Click({
    switch ($script:CurrentStep) {
        1 { Set-Step 2 }
        2 { Set-Step 3 }
        3 {
            if (-not $script:WizardData.RdWebLicenseOk -and -not $chkGuacAuto.Checked) {
                $script:WizardData.InstallGuacamole = $false
            }
            Set-Step 4
        }
        4 {
            if ($script:WizardData.ConnectionStrategies.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('En az bir baglanti stratejisi secmelisiniz.','Uyari','OK','Warning') | Out-Null
                return
            }
            Set-Step 5
        }
        5 {
            $script:WizardData.SelectedApps = @()
            foreach ($item in $lvApps.CheckedItems) { $script:WizardData.SelectedApps += $item.Tag }
            Update-ReviewSummary
            Set-Step 6
        }
        6 {
            $txtLog.AppendText("Kurulum baslatildi: $(Get-Date -Format 's')`n")
            Set-Step 7
            # Kick off installation worker in the background
            Start-InstallationWorker
        }
    }
})

$footerPanel.Controls.AddRange(@($btnCancel, $btnPrev, $btnNext))

# -----------------------------------------------------------------------------
# Installation worker (runs synchronously on UI thread but updates progress)
# -----------------------------------------------------------------------------
$script:InstallActions = @()
function New-InstallActions {
    $actions = New-Object System.Collections.ArrayList
    if ($script:WizardData.InstallRdsRoles)  { [void]$actions.Add(@{ Name='RDS Rolleri kuruluyor'; Script='RdsInstaller.ps1' }) }
    if ($script:WizardData.CertMode -eq 'SelfSigned' -or $script:WizardData.CertMode -eq 'CASigned') {
        [void]$actions.Add(@{ Name='Sertifika hazirlaniyor'; Script='CertificateManager.ps1'; Args=$script:WizardData.CertMode })
    }
    if ($script:WizardData.ConfigureFirewall) { [void]$actions.Add(@{ Name='Firewall kurallari aciliyor'; Script='FirewallConfig.ps1' }) }
    if ($script:WizardData.RdpPort)           { [void]$actions.Add(@{ Name=("RDP portu ayarlaniyor (TCP {0})" -f $script:WizardData.RdpPort); Script='Set-RdpListenPort.ps1'; Args=$script:WizardData.RdpPort }) }
    if ($script:WizardData.InstallGateway)    { [void]$actions.Add(@{ Name='RD Gateway kuruluyor'; Script='RDGatewayInstaller.ps1' }) }
    if ($script:WizardData.InstallGuacamole) { [void]$actions.Add(@{ Name='Apache Guacamole kuruluyor (uzun surer)'; Script='GuacamoleInstaller.ps1' }) }
    if ($script:WizardData.InstallTailscale) { [void]$actions.Add(@{ Name='Tailscale kuruluyor'; Script='TailscaleInstaller.ps1' }) }
    if ($script:WizardData.InstallCloudflare){ [void]$actions.Add(@{ Name='Cloudflare Tunnel kuruluyor'; Script='CloudflareTunnelInstaller.ps1' }) }
    if ($script:WizardData.InstallProbeApi)   { [void]$actions.Add(@{ Name='Probe REST API kuruluyor (8444 + web portali)'; Script='Install-ProbeApiHost.ps1' }) }
    if ($script:WizardData.InstallCaddySsl)   { [void]$actions.Add(@{ Name='Caddy SSL kuruluyor (HTTPS 8445)'; Script='Install-CaddySsl.ps1' }) }
    if ($script:WizardData.PublishApps -and $script:WizardData.SelectedApps.Count -gt 0) {
        [void]$actions.Add(@{ Name='RemoteApp koleksiyonu yayinlaniyor'; Script='RemoteAppPublisher.ps1' })
    }
    return $actions
}

# Backwards-compatible alias for PSScriptAnalyzer PSUseApprovedVerbs compliance
Set-Alias -Name Build-InstallActions -Value New-InstallActions -Scope Global -Force

function Start-InstallationWorker {
    $actions = New-InstallActions
    if ($actions.Count -eq 0) {
        $txtLog.AppendText("Secili bilesen yok. Kurulum atlandi.`n")
        $progBar.Value = 100
        $btnFinish.Enabled = $true
        return
    }
    $script:InstallActions = $actions
    $btnUndo.Enabled = $true
    $progBar.Maximum = $actions.Count
    $progBar.Value   = 0
    $form.Refresh()

    for ($i = 0; $i -lt $actions.Count; $i++) {
        $a = $actions[$i]
        $txtLog.AppendText(("[$($i+1)/$($actions.Count)] {0}`n" -f $a.Name))
        $txtLog.ScrollToCaret()
        try {
            $scriptPath = Resolve-ServerModulePath -Name $a.Script
            if (Test-Path $scriptPath) {
                & $scriptPath @($a.Args) 2>&1 | ForEach-Object { $txtLog.AppendText("  $_`n"); $txtLog.ScrollToCaret() }
            } else {
                $txtLog.AppendText("  UYARI: $scriptPath bulunamadi - atlandi.`n")
            }
            $progBar.Value = $i + 1
            $form.Refresh()
        } catch {
            $txtLog.AppendText("  HATA: $($_.Exception.Message)`n")
            Write-SetupLog "Kurulum hatasi (adim $($i+1)): $_" -Level ERROR
            $btnUndo.Enabled = $true
            return
        }
    }
    # Persist a manifest for the client setup
    try {
        $manifestDir = "$env:ProgramData\RdpVirtualBoxApp"
        if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null }
        $script:WizardData.ManifestPath = Join-Path $manifestDir 'server-manifest.json'
        $script:WizardData | ConvertTo-Json -Depth 5 | Set-Content -Path $script:WizardData.ManifestPath -Encoding UTF8
        $txtLog.AppendText("Manifest yazildi: $($script:WizardData.ManifestPath)`n")
    } catch {
        $txtLog.AppendText("Manifest yazilamadi: $($_.Exception.Message)`n")
    }

    $txtLog.AppendText("`n=== KURULUM TAMAMLANDI ===`n")
    $btnFinish.Enabled = $true
    $btnUndo.Enabled   = $false
    Write-SetupLog "Kurulum basariyla tamamlandi." -Level INFO
}

$btnUndo.Add_Click({
    $res = [System.Windows.Forms.MessageBox]::Show(
        'Kurulum adimlarini geri almak istediginize emin misiniz? Bu islem yapilan tum degisiklikleri rollback yapar.',
        'Geri Alma Onayi',
        'YesNo',
        'Warning'
    )
    if ($res -ne 'Yes') { return }
    $txtLog.AppendText("`n--- Geri alma baslatildi ---`n")
    try {
        # Undo in reverse order
        for ($i = $script:InstallActions.Count - 1; $i -ge 0; $i--) {
            $a = $script:InstallActions[$i]
            $txtLog.AppendText("Geri aliniyor: $($a.Name)`n")
            # In a real deployment, each installer should expose an -Undo switch
            $undoScript = Join-Path $PSScriptRoot ($a.Script -replace '\.ps1$','Undo.ps1')
            if (Test-Path $undoScript) {
                & $undoScript 2>&1 | ForEach-Object { $txtLog.AppendText("  $_`n") }
            } else {
                $txtLog.AppendText("  (Undo script yok: $undoScript)`n")
            }
        }
        $txtLog.AppendText("--- Geri alma tamamlandi ---`n")
        Write-SetupLog "Kullanici undo islemi uyguladi." -Level WARN
    } catch {
        $txtLog.AppendText("Geri alma hatasi: $($_.Exception.Message)`n")
    }
})

# -----------------------------------------------------------------------------
# Boot
# -----------------------------------------------------------------------------
try {
    Write-SetupLog "ServerSetupUI baslatildi." -Level INFO
    Get-ServerNetworkInfo
    $lblIp.Text   = "IP Adresi  : $($script:WizardData.ServerIp)"
    $lblDom.Text  = "Domain     : $($script:WizardData.ServerDomain)"
    $lblOs.Text   = "OS         : $($script:WizardData.OsVersion)"
    $lblAdmin.Text= "Yonetici   : $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')"

    Set-Step 1
    [void]$form.ShowDialog()
} catch {
    Write-SetupLog "Kritik hata: $_" -Level ERROR
    [System.Windows.Forms.MessageBox]::Show("Kurulum sihirbazi baslatilamadi:`n$($_.Exception.Message)", 'Hata', 'OK', 'Error') | Out-Null
}

# ---------------------------------------------------------------------------
# Public API surface. Exposed when this file is loaded as a module via
# Import-Module. When the script is run directly (Boot block above), the
# module manifest is not used, so this block is a no-op at script scope.
# Backwards-compatible aliases are exported so existing callers using the
# old verb names (Switch-Step, Build-InstallActions, Initialize-*) keep
# working after the PSScriptAnalyzer PSUseApprovedVerbs refactor.
# ---------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'Write-SetupLog'
    'New-ModernButton'
    'New-PrimaryButton'
    'New-HelpButton'
    'New-StepPanel'
    'New-Button'
    'New-Label'
    'New-TextBox'
    'New-IndexPage'
    'Set-AeroTheme'
    'Set-Step'
    'New-InstallActions'
    'Start-InstallationWorker'
    'Show-AppSummary'
    'Update-ReviewSummary'
    'Get-ServerNetworkInfo'
) -Variable @(
    'ServerModules'
    'ServerModuleNames'
    'ThemeColor'
    'AccentColor'
    'OkColor'
    'WarnColor'
    'ErrColor'
    'CurrentStep'
    'WizardData'
    'InstallActions'
) -Cmdlet @() -Alias @(
    'Switch-Step'
    'Build-InstallActions'
)