<#
.SYNOPSIS
    Rdp Virtual Box App - Client Setup WinForms Wizard (4 steps).

.DESCRIPTION
    Single-form wizard pattern for the client-side setup. Each step is rendered
    on the same System.Windows.Forms.Form instance by swapping the contents of
    a host Panel. The UI text is Turkish by default and an English fallback is
    available through the resource hashtable.

    Steps:
        1. Server information (IP, port, username, password).
        2. Server probe results (component status grid + recommendations).
        3. Application selection + access type + credential mode.
        4. Review & install (summary + progress bar).

.NOTES
    Author : Rdp Virtual Box App Project
    Module : client/SetupUI.ps1
    Std    : CmdletBinding, try/catch, Verbose, English comments, Export-ModuleMember.
    Exit   : 0 success, non-zero fatal error.
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Module manifest (lets this file also be used as a .psm1 via dot-source)
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'Start-ClientSetupWizard',
        'New-SetupUiStrings',
        'Show-ClientWizard'
    )
}

# ---------------------------------------------------------------------------
# String resources (Turkish default + English fallback).
# A simple toggle: $script:UiLanguage = 'tr' | 'en'
# ---------------------------------------------------------------------------
function New-SetupUiStrings {
    <#
    .SYNOPSIS  Returns the localized string table used by the wizard.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('tr', 'en')]
        [string] $Language = 'tr'
    )

    if ($Language -eq 'en') {
        return @{
            FormTitle         = 'Rdp Virtual Box App - Setup'
            HelpTooltip       = 'Help'
            StepLabelFormat   = 'Step {0}/4: {1}'
            Step1Title        = 'Server information'
            Step2Title        = 'Server probe results'
            Step3Title        = 'Application and access type'
            Step4Title        = 'Review and install'
            ServerIpLabel     = 'Server IP:'
            PortLabel         = 'Port:'
            UsernameLabel     = 'Username (domain\user):'
            PasswordLabel     = 'Password:'
            ProbeButton       = 'Probe server'
            BackButton        = 'Back'
            NextButton        = 'Next'
            InstallButton     = 'Start install'
            CancelButton      = 'Cancel'
            ProbeProgress     = 'Probing server, please wait...'
            ComponentHeader   = 'Component'
            StatusHeader      = 'Status'
            ValueHeader       = 'Value'
            Recommendations   = 'Recommendations'
            ChooseApps        = 'Select applications to install (multiple allowed):'
            AccessTypeLabel   = 'Access type'
            NativeRdp         = 'Native (.rdp file) - RECOMMENDED'
            WebHtml5          = 'Web (HTML5, browser)'
            BothModes         = 'Both'
            CredentialLabel   = 'Credential handling'
            AskEveryTime      = 'Ask on every connection'
            SaveCredman       = 'Save to Windows Credential Manager'
            EmbedInRdp        = 'Embed in RDP file (not recommended, security warning)'
            CustomAppPath     = 'Custom application path (optional):'
            SummaryLabel      = 'Review your selections:'
            InstallingLabel   = 'Installing, please wait...'
            ConfirmCancel     = 'Are you sure you want to exit the setup?'
            ConfirmCancelCap  = 'Confirm exit'
            ErrorTitle        = 'Error'
            WarningTitle      = 'Warning'
            InvalidIp         = 'Please enter a valid IPv4 or hostname.'
            InvalidPort       = 'Port must be between 1 and 65535.'
            InvalidUser       = 'Username must be in DOMAIN\user or user@domain format.'
            MissingPassword    = 'Password cannot be empty.'
            ProbeFailed       = 'Server probe failed: {0}'
            InstallDone       = 'Setup completed successfully.'
            LogDirectory      = 'Logs'
            LogFile           = 'setup.log'
            StatusOk          = 'OK'
            StatusWarn        = 'WARNING'
            StatusError       = 'ERROR'
            RecommendedBadge  = ' (recommended)'
            EmbedWarning      = 'Embedding credentials in RDP files is not secure. Continue?'
        }
    }

    # Default: Turkish
    return @{
        FormTitle         = 'Rdp Virtual Box App - Kurulum'
        HelpTooltip       = 'Yardım'
        StepLabelFormat   = 'Adım {0}/4: {1}'
        Step1Title        = 'Sunucu bilgileri'
        Step2Title        = 'Sunucu tespit sonuçları'
        Step3Title        = 'Uygulama ve erişim tipi'
        Step4Title        = 'İnceleme ve kurulum'
        ServerIpLabel     = 'Sunucu IP:'
        PortLabel         = 'Port:'
        UsernameLabel     = 'Kullanıcı adı (domain\user):'
        PasswordLabel     = 'Parola:'
        ProbeButton       = 'Sunucuyu Tara'
        BackButton        = 'Geri'
        NextButton        = 'İleri'
        InstallButton     = 'Kurulumu Başlat'
        CancelButton      = 'İptal'
        ProbeProgress     = 'Sunucu taranıyor, lütfen bekleyin...'
        ComponentHeader   = 'Bileşen'
        StatusHeader      = 'Durum'
        ValueHeader       = 'Değer'
        Recommendations   = 'Öneriler'
        ChooseApps        = 'Kurulacak uygulamaları seçin (çoklu seçim):'
        AccessTypeLabel   = 'Erişim Tipi'
        NativeRdp         = 'Native (.rdp dosyası) - ÖNERİLEN'
        WebHtml5          = 'Web (HTML5, tarayıcı üzerinden)'
        BothModes         = 'Her ikisi'
        CredentialLabel   = 'Kimlik Bilgisi Yönetimi'
        AskEveryTime      = 'Her bağlantıda sor'
        SaveCredman       = 'Credential Manager''a kaydet'
        EmbedInRdp        = 'RDP dosyasına göm (önerilmez, güvenlik uyarısı)'
        CustomAppPath     = 'Özel uygulama yolu (opsiyonel):'
        SummaryLabel      = 'Seçimlerinizi inceleyin:'
        InstallingLabel   = 'Kurulum yapılıyor, lütfen bekleyin...'
        ConfirmCancel     = 'Kurulumdan çıkmak istediğinize emin misiniz?'
        ConfirmCancelCap  = 'Çıkışı Onayla'
        ErrorTitle        = 'Hata'
        WarningTitle      = 'Uyarı'
        InvalidIp         = 'Lütfen geçerli bir IPv4 veya hostname girin.'
        InvalidPort       = 'Port 1 ile 65535 arasında olmalıdır.'
        InvalidUser       = 'Kullanıcı adı DOMAIN\kullanici veya kullanici@domain formatında olmalıdır.'
        MissingPassword   = 'Parola boş olamaz.'
        ProbeFailed       = 'Sunucu taraması başarısız: {0}'
        InstallDone       = 'Kurulum başarıyla tamamlandı.'
        LogDirectory      = 'Logs'
        LogFile           = 'setup.log'
        StatusOk          = 'TAMAM'
        StatusWarn        = 'UYARI'
        StatusError       = 'HATA'
        RecommendedBadge  = ' (önerilen)'
        EmbedWarning      = 'Kimlik bilgisini RDP dosyasına gömmek güvenli değildir. Devam edilsin mi?'
    }
}

# ---------------------------------------------------------------------------
# Logging helper - writes to %LOCALAPPDATA%\RdpVirtualBoxApp\Logs\setup.log
# ---------------------------------------------------------------------------
function Write-SetupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Debug')]
        [string] $Level = 'Info',
        [string] $LogRoot = ('{0}\RdpVirtualBoxApp' -f $env:LOCALAPPDATA)
    )

    try {
        $logDir = Join-Path -Path $LogRoot -ChildPath 'Logs'
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFile = Join-Path -Path $logDir -ChildPath 'setup.log'
        $ts      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $line    = "[$ts] [$Level] $Message"
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging must never throw to the caller.
        Write-Verbose ("Log write failed: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
function Test-IpAddress {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }

    # Try IPv4 first
    $ipv4Regex = '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$'
    if ($Value -match $ipv4Regex) { return $true }

    # Then a permissive hostname check
    $hostRegex = '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
    return ($Value -match $hostRegex)
}

function Test-Port {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][int] $Value)

    return ($Value -ge 1 -and $Value -le 65535)
}

function Test-UsernameFormat {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    # Accept DOMAIN\user or user@domain.tld
    return ($Value -match '^[^\\\/\s]+\\[^\\\/\s]+$' -or $Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

# ---------------------------------------------------------------------------
# Color & font palette (centralized for consistency)
# ---------------------------------------------------------------------------
function Get-SetupPalette {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Background   = [System.Drawing.Color]::FromArgb(245, 245, 245)
        Accent       = [System.Drawing.Color]::FromArgb(0, 120, 212)   # #0078D4
        Success      = [System.Drawing.Color]::FromArgb(16, 124, 16)   # #107C10
        Warning      = [System.Drawing.Color]::FromArgb(255, 185, 0)   # #FFB900
        Danger       = [System.Drawing.Color]::FromArgb(216, 59, 1)    # #D83B01
        Text         = [System.Drawing.Color]::FromArgb(32, 32, 32)
        SubtleText   = [System.Drawing.Color]::FromArgb(96, 96, 96)
        FontBody     = New-Object System.Drawing.Font('Segoe UI', 9)
        FontTitle    = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        FontSmall    = New-Object System.Drawing.Font('Segoe UI', 8)
    }
}

# ---------------------------------------------------------------------------
# Optional Aero theming via SetWindowTheme (UX polish, safe to skip on error)
# ---------------------------------------------------------------------------
function Set-AeroTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Forms.Control] $Control)

    try {
        $signature = @'
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetWindowTheme(System.IntPtr hWnd, string pszSubAppName, string pszSubIdList);
'@
        $type = Add-Type -MemberDefinition $signature -Name 'UxThemeHelper' -Namespace 'RdpVBoxApp' -PassThru -ErrorAction Stop
        $type::SetWindowTheme($Control.Handle, 'explorer', $null) | Out-Null
    } catch {
        Write-Verbose ("SetWindowTheme skipped: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Wizard state container - shared between the four steps.
# ---------------------------------------------------------------------------
function New-WizardState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Server          = [pscustomobject]@{ Ip = ''; Port = 3389; Username = ''; SecurePassword = $null }
        Probe           = $null        # PSCustomObject produced by ServerProbe (filled on step 2)
        AccessType      = 'Native'     # Native | Web | Both
        CredentialMode  = 'Ask'        # Ask | Save | Embed
        SelectedApps    = @()          # string[]  - app ids chosen on step 3
        CustomAppPath   = ''
        OutputDir       = ('{0}\Documents\RdpVirtualBoxApp' -f $env:USERPROFILE)
        CurrentStep     = 1
        Strings         = $null
        Palette         = Get-SetupPalette
    }
}

# ---------------------------------------------------------------------------
# Lightweight UI builders - keep the main wizard function readable.
# ---------------------------------------------------------------------------
function New-Label {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [System.Drawing.Font] $Font,
        [System.Drawing.Color] $ForeColor,
        [int] $X, [int] $Y, [int] $Width, [int] $Height = 23,
        [System.Windows.Forms.Form] $Parent
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $Text
    $lbl.AutoSize = $false
    if ($Font) { $lbl.Font = $Font }
    if ($ForeColor) { $lbl.ForeColor = $ForeColor }
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size     = New-Object System.Drawing.Size($Width, $Height)
    if ($Parent) { $Parent.Controls.Add($lbl) }
    return $lbl
}

function New-TextBox {
    [CmdletBinding()]
    param(
        [int] $X, [int] $Y, [int] $Width, [int] $Height = 23,
        [bool] $UseSystemPasswordChar = $false,
        [System.Windows.Forms.Form] $Parent
    )

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($X, $Y)
    $tb.Size     = New-Object System.Drawing.Size($Width, $Height)
    if ($UseSystemPasswordChar) { $tb.UseSystemPasswordChar = $true }
    if ($Parent) { $Parent.Controls.Add($tb) }
    return $tb
}

function New-Button {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [int] $X, [int] $Y, [int] $Width = 100, [int] $Height = 30,
        [System.Drawing.Color] $BackColor,
        [System.Drawing.Color] $ForeColor = [System.Drawing.Color]::White,
        [System.Windows.Forms.Form] $Parent
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text     = $Text
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    if ($BackColor) { $btn.BackColor = $BackColor }
    $btn.ForeColor = $ForeColor
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btn.Location  = New-Object System.Drawing.Point($X, $Y)
    $btn.Size      = New-Object System.Drawing.Size($Width, $Height)
    if ($Parent) { $Parent.Controls.Add($btn) }
    return $btn
}

function New-HelpButton {
    [CmdletBinding()]
    param([int] $X, [int] $Y, [System.Windows.Forms.Form] $Parent)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = '?'
    $btn.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btn.Size      = New-Object System.Drawing.Size(28, 28)
    $btn.Location  = New-Object System.Drawing.Point($X, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    if ($Parent) { $Parent.Controls.Add($btn) }
    return $btn
}

# ---------------------------------------------------------------------------
# Step 1 - Server information (Welcome / Server)
# ---------------------------------------------------------------------------
function Build-Step1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel] $Host,
        [Parameter(Mandatory)][hashtable] $State,
        [System.Windows.Forms.Button] $NextButton,
        [System.Windows.Forms.Button] $ProbeButton,
        [System.Windows.Forms.ToolTip] $ToolTip
    )

    $Host.Controls.Clear()
    $p = $State.Palette
    $s = $State.Strings

    # Logo PictureBox (placeholder, drawn rather than loaded from disk so the
    # wizard works without extra asset files).
    $logo = New-Object System.Windows.Forms.PictureBox
    $logo.Location = New-Object System.Drawing.Point(20, 12)
    $logo.Size     = New-Object System.Drawing.Size(64, 64)
    $logo.BackColor = $p.Accent
    $logo.Paint    = {
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $font  = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
        $g.DrawString('R', $font, $brush, 14, 12)
        $font.Dispose()
        $brush.Dispose()
    }
    $Host.Controls.Add($logo)

    # Title block
    New-Label -Text $s.FormTitle -Font $p.FontTitle -ForeColor $p.Text -X 100 -Y 12 -Width 480 -Height 28 -Parent $Host
    New-Label -Text ($s.StepLabelFormat -f 1, $s.Step1Title) -Font $p.FontBody -ForeColor $p.SubtleText -X 100 -Y 42 -Width 480 -Height 20 -Parent $Host

    # Form fields
    $yBase = 90
    $lblIp = New-Label -Text $s.ServerIpLabel -X 20 -Y $yBase -Width 150 -Height 23 -Parent $Host
    $tbIp  = New-TextBox -X 180 -Y $yBase -Width 380 -Parent $Host

    $lblPort = New-Label -Text $s.PortLabel -X 20 -Y ($yBase + 35) -Width 150 -Height 23 -Parent $Host
    $tbPort  = New-TextBox -X 180 -Y ($yBase + 35) -Width 120 -Parent $Host
    $tbPort.Text = '3389'

    $lblUser = New-Label -Text $s.UsernameLabel -X 20 -Y ($yBase + 70) -Width 150 -Height 23 -Parent $Host
    $tbUser  = New-TextBox -X 180 -Y ($yBase + 70) -Width 380 -Parent $Host

    $lblPass = New-Label -Text $s.PasswordLabel -X 20 -Y ($yBase + 105) -Width 150 -Height 23 -Parent $Host
    $tbPass  = New-TextBox -X 180 -Y ($yBase + 105) -Width 380 -UseSystemPasswordChar -Parent $Host

    # Probe button (manual trigger, doesn't gate the wizard).
    $probeBtn = New-Button -Text $s.ProbeButton -X 180 -Y ($yBase + 145) -Width 150 -BackColor $p.Accent -Parent $Host
    $probeBtn.Add_Click({
        if (-not (Test-IpAddress -Value $tbIp.Text)) {
            [System.Windows.Forms.MessageBox]::Show($s.InvalidIp, $s.ErrorTitle, 'OK', 'Error') | Out-Null
            return
        }
        if (-not (Test-Port -Value ([int]($tbPort.Text)))) {
            [System.Windows.Forms.MessageBox]::Show($s.InvalidPort, $s.ErrorTitle, 'OK', 'Error') | Out-Null
            return
        }
        Write-SetupLog -Message ("Manual probe triggered for {0}:{1}" -f $tbIp.Text, $tbPort.Text)
        $probeResult = Invoke-ServerProbeQuick -Ip $tbIp.Text -Port ([int]$tbPort.Text) -State $State
        if ($probeResult.Reachable) {
            [System.Windows.Forms.MessageBox]::Show("Sunucuya erişim sağlandı: $($probeResult.Os)", 'Probe OK', 'OK', 'Information') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show(($s.ProbeFailed -f $probeResult.Error), $s.ErrorTitle, 'OK', 'Error') | Out-Null
        }
    })

    # Persist references so the wizard can read them on Next.
    $State['_tbIp']   = $tbIp
    $State['_tbPort'] = $tbPort
    $State['_tbUser'] = $tbUser
    $State['_tbPass'] = $tbPass

    # Live validation - enable Next only when inputs are valid.
    $validateHandler = {
        $ok = (Test-IpAddress -Value $tbIp.Text) -and
              (Test-Port -Value ([int]($tbPort.Text))) -and
              (Test-UsernameFormat -Value $tbUser.Text) -and
              (-not [string]::IsNullOrEmpty($tbPass.Text))
        $NextButton.Enabled = $ok
    }
    $tbIp.Add_TextChanged($validateHandler)
    $tbPort.Add_TextChanged($validateHandler)
    $tbUser.Add_TextChanged($validateHandler)
    $tbPass.Add_TextChanged($validateHandler)
    $validateHandler.Invoke()

    $NextButton.Text = $s.NextButton
}

# ---------------------------------------------------------------------------
# Step 2 - Server probe results.
# ---------------------------------------------------------------------------
function Build-Step2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel] $Host,
        [Parameter(Mandatory)][hashtable] $State,
        [System.Windows.Forms.Button] $BackButton,
        [System.Windows.Forms.Button] $NextButton,
        [System.Windows.Forms.ToolTip] $ToolTip
    )

    $Host.Controls.Clear()
    $p = $State.Palette
    $s = $State.Strings

    New-Label -Text $s.FormTitle -Font $p.FontTitle -ForeColor $p.Text -X 20 -Y 12 -Width 560 -Height 28 -Parent $Host
    New-Label -Text ($s.StepLabelFormat -f 2, $s.Step2Title) -Font $p.FontBody -ForeColor $p.SubtleText -X 20 -Y 42 -Width 560 -Height 20 -Parent $Host

    # DataGridView: Component | Status | Value
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(20, 80)
    $grid.Size     = New-Object System.Drawing.Size(560, 200)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.ReadOnly = $true
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = 'FixedSingle'
    $grid.ColumnCount = 3
    $grid.Columns[0].Name = $s.ComponentHeader
    $grid.Columns[1].Name = $s.StatusHeader
    $grid.Columns[2].Name = $s.ValueHeader
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.Font = (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold))
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $Host.Controls.Add($grid)

    # Progress bar (shown only during probing).
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20, 290)
    $progress.Size     = New-Object System.Drawing.Size(560, 22)
    $progress.Style    = 'Marquee'
    $progress.MarqueeAnimationSpeed = 30
    $progress.Visible  = $false
    $Host.Controls.Add($progress)

    # Recommendations RichTextBox
    New-Label -Text $s.Recommendations -Font $p.FontBody -X 20 -Y 320 -Width 200 -Height 20 -Parent $Host
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location = New-Object System.Drawing.Point(20, 345)
    $rtb.Size     = New-Object System.Drawing.Size(560, 80)
    $rtb.ReadOnly = $true
    $rtb.BackColor = [System.Drawing.Color]::White
    $Host.Controls.Add($rtb)

    $State['_probeGrid']    = $grid
    $State['_probeProgress'] = $progress
    $State['_probeRtb']     = $rtb

    $BackButton.Text  = $s.BackButton
    $BackButton.Visible = $true
    $NextButton.Text  = $s.NextButton
    $NextButton.Enabled = ($State.Probe -ne $null)
}

function Populate-Step2 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $State)

    $p = $State.Palette
    $s = $State.Strings
    $grid = $State['_probeGrid']
    $rtb  = $State['_probeRtb']

    $grid.Rows.Clear()
    $rtb.Clear()

    if (-not $State.Probe) {
        $rtb.AppendText(("Sunucu tespit verisi yok. Geri dönüp '{0}' butonunu kullanın." -f $s.ProbeButton))
        return
    }

    foreach ($component in $State.Probe.Components.PSObject.Properties) {
        $rowIdx = $grid.Rows.Add($component.Name, '', $component.Value.value)
        $statusCell = $grid.Rows[$rowIdx].Cells[1]
        switch ($component.Value.status) {
            'ok'      {
                $statusCell.Value = "✓ $($s.StatusOk)"
                $statusCell.Style.ForeColor = $p.Success
            }
            'warning' {
                $statusCell.Value = "! $($s.StatusWarn)"
                $statusCell.Style.ForeColor = $p.Warning
            }
            'error'   {
                $statusCell.Value = "✗ $($s.StatusError)"
                $statusCell.Style.ForeColor = $p.Danger
            }
            default   { $statusCell.Value = $component.Value.status }
        }
    }

    if ($State.Probe.recommendations) {
        foreach ($rec in $State.Probe.recommendations) {
            $rtb.AppendText(("• {0}" -f $rec))
            $rtb.AppendText([Environment]::NewLine)
        }
    } else {
        $rtb.AppendText('Öneri bulunamadı.')
    }
}

# ---------------------------------------------------------------------------
# Step 3 - Application selection + access type + credential mode.
# ---------------------------------------------------------------------------
function Build-Step3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel] $Host,
        [Parameter(Mandatory)][hashtable] $State,
        [System.Windows.Forms.Button] $BackButton,
        [System.Windows.Forms.Button] $NextButton
    )

    $Host.Controls.Clear()
    $p = $State.Palette
    $s = $State.Strings

    New-Label -Text $s.FormTitle -Font $p.FontTitle -ForeColor $p.Text -X 20 -Y 12 -Width 560 -Height 28 -Parent $Host
    New-Label -Text ($s.StepLabelFormat -f 3, $s.Step3Title) -Font $p.FontBody -ForeColor $p.SubtleText -X 20 -Y 42 -Width 560 -Height 20 -Parent $Host

    # Applications list
    New-Label -Text $s.ChooseApps -X 20 -Y 80 -Width 560 -Height 20 -Parent $Host
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(20, 105)
    $clb.Size     = New-Object System.Drawing.Size(560, 150)
    $clb.CheckOnClick = $true
    $clb.IntegralHeight = $false
    if ($State.Probe -and $State.Probe.existingRemoteApps) {
        foreach ($app in $State.Probe.existingRemoteApps) { [void]$clb.Items.Add($app) }
    }
    if ($clb.Items.Count -eq 0) {
        [void]$clb.Items.Add('(Sunucuda tespit edilen uygulama yok)')
        $clb.Enabled = $false
    }
    $Host.Controls.Add($clb)

    # Access type radios
    $gbAccess = New-Object System.Windows.Forms.GroupBox
    $gbAccess.Text  = $s.AccessTypeLabel
    $gbAccess.Location = New-Object System.Drawing.Point(20, 265)
    $gbAccess.Size  = New-Object System.Drawing.Size(270, 100)
    $Host.Controls.Add($gbAccess)

    $rbNative = New-Object System.Windows.Forms.RadioButton
    $rbNative.Text = $s.NativeRdp
    $rbNative.Location = New-Object System.Drawing.Point(10, 22)
    $rbNative.AutoSize = $true
    $rbNative.Checked = $true
    $gbAccess.Controls.Add($rbNative)

    $rbWeb = New-Object System.Windows.Forms.RadioButton
    $rbWeb.Text = $s.WebHtml5
    $rbWeb.Location = New-Object System.Drawing.Point(10, 47)
    $rbWeb.AutoSize = $true
    $gbAccess.Controls.Add($rbWeb)

    $rbBoth = New-Object System.Windows.Forms.RadioButton
    $rbBoth.Text = $s.BothModes
    $rbBoth.Location = New-Object System.Drawing.Point(10, 72)
    $rbBoth.AutoSize = $true
    $gbAccess.Controls.Add($rbBoth)

    # Credential mode radios
    $gbCred = New-Object System.Windows.Forms.GroupBox
    $gbCred.Text  = $s.CredentialLabel
    $gbCred.Location = New-Object System.Drawing.Point(310, 265)
    $gbCred.Size  = New-Object System.Drawing.Size(270, 100)
    $Host.Controls.Add($gbCred)

    $rbAsk = New-Object System.Windows.Forms.RadioButton
    $rbAsk.Text = $s.AskEveryTime
    $rbAsk.Location = New-Object System.Drawing.Point(10, 22)
    $rbAsk.AutoSize = $true
    $rbAsk.Checked = $true
    $gbCred.Controls.Add($rbAsk)

    $rbSave = New-Object System.Windows.Forms.RadioButton
    $rbSave.Text = $s.SaveCredman
    $rbSave.Location = New-Object System.Drawing.Point(10, 47)
    $rbSave.AutoSize = $true
    $gbCred.Controls.Add($rbSave)

    $rbEmbed = New-Object System.Windows.Forms.RadioButton
    $rbEmbed.Text = $s.EmbedInRdp
    $rbEmbed.Location = New-Object System.Drawing.Point(10, 72)
    $rbEmbed.AutoSize = $true
    $rbEmbed.ForeColor = $p.Danger
    $gbCred.Controls.Add($rbEmbed)

    # Custom app path
    New-Label -Text $s.CustomAppPath -X 20 -Y 375 -Width 560 -Height 20 -Parent $Host
    $tbCustom = New-TextBox -X 20 -Y 400 -Width 560 -Parent $Host

    $State['_clb']      = $clb
    $State['_rbNative'] = $rbNative
    $State['_rbWeb']    = $rbWeb
    $State['_rbBoth']   = $rbBoth
    $State['_rbAsk']    = $rbAsk
    $State['_rbSave']   = $rbSave
    $State['_rbEmbed']  = $rbEmbed
    $State['_tbCustom'] = $tbCustom

    $BackButton.Text = $s.BackButton
    $BackButton.Visible = $true
    $NextButton.Text = $s.NextButton
    $NextButton.Enabled = $true
}

function Capture-Step3 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $State)

    $clb = $State['_clb']
    $selected       = @()
    $selectedObjs   = @()
    for ($i = 0; $i -lt $clb.Items.Count; $i++) {
        if ($clb.GetItemChecked($i)) {
            $item = $clb.Items[$i]
            $selected += [string]$item
            $selectedObjs += ([pscustomobject]@{
                id    = if ($item.alias) { [string]$item.alias } else { [string]$item }
                alias = if ($item.alias) { [string]$item.alias } else { [string]$item }
                name  = if ($item.name)  { [string]$item.name  } else { [string]$item }
                path  = if ($item.path)  { [string]$item.path  } else { '' }
            })
        }
    }
    $State.SelectedApps        = $selected
    $State.SelectedAppObjects  = $selectedObjs

    if     ($State['_rbNative'].Checked) { $State.AccessType = 'Native' }
    elseif ($State['_rbWeb'].Checked)    { $State.AccessType = 'Web' }
    else                                 { $State.AccessType = 'Both' }

    if     ($State['_rbAsk'].Checked)   { $State.CredentialMode = 'Ask' }
    elseif ($State['_rbSave'].Checked)  { $State.CredentialMode = 'Save' }
    else                                { $State.CredentialMode = 'Embed' }

    $State.CustomAppPath = $State['_tbCustom'].Text
}

# ---------------------------------------------------------------------------
# Step 4 - Review and install.
# ---------------------------------------------------------------------------
function Build-Step4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Panel] $Host,
        [Parameter(Mandatory)][hashtable] $State,
        [System.Windows.Forms.Button] $BackButton,
        [System.Windows.Forms.Button] $InstallButton,
        [System.Windows.Forms.Button] $CancelButton
    )

    $Host.Controls.Clear()
    $p = $State.Palette
    $s = $State.Strings

    New-Label -Text $s.FormTitle -Font $p.FontTitle -ForeColor $p.Text -X 20 -Y 12 -Width 560 -Height 28 -Parent $Host
    New-Label -Text ($s.StepLabelFormat -f 4, $s.Step4Title) -Font $p.FontBody -ForeColor $p.SubtleText -X 20 -Y 42 -Width 560 -Height 20 -Parent $Host

    New-Label -Text $s.SummaryLabel -X 20 -Y 80 -Width 560 -Height 20 -Parent $Host

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location = New-Object System.Drawing.Point(20, 105)
    $rtb.Size     = New-Object System.Drawing.Size(560, 240)
    $rtb.ReadOnly = $true
    $rtb.BackColor = [System.Drawing.Color]::White
    $rtb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $Host.Controls.Add($rtb)

    # Install progress
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20, 355)
    $progress.Size     = New-Object System.Drawing.Size(560, 22)
    $progress.Style    = 'Continuous'
    $progress.Minimum  = 0
    $progress.Maximum  = 100
    $progress.Value    = 0
    $Host.Controls.Add($progress)

    $State['_reviewRtb']     = $rtb
    $State['_installProgress'] = $progress

    $BackButton.Text    = $s.BackButton
    $BackButton.Visible = $true
    $InstallButton.Text = $s.InstallButton
    $InstallButton.Visible = $true
    $CancelButton.Text  = $s.CancelButton
}

function Populate-Step4 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $State)

    $s = $State.Strings
    $rtb = $State['_reviewRtb']
    $rtb.Clear()

    $lines = @()
    $lines += "=== $($s.FormTitle) ==="
    $lines += ""
    $lines += "Sunucu       : $($State.Server.Ip):$($State.Server.Port)"
    $lines += "Kullanıcı   : $($State.Server.Username)"
    $lines += "Erişim tipi : $($State.AccessType)"
    $lines += "Kimlik      : $($State.CredentialMode)"
    $lines += ""
    if ($State.SelectedApps -and $State.SelectedApps.Count -gt 0) {
        $lines += "Uygulamalar:"
        foreach ($a in $State.SelectedApps) { $lines += "  - $a" }
    } else {
        $lines += "Uygulamalar: (seçim yok)"
    }
    if ($State.CustomAppPath) {
        $lines += ""
        $lines += "Özel uygulama yolu: $($State.CustomAppPath)"
    }
    $lines += ""
    $lines += "Çıktı dosyaları:"
    $lines += "  $($State.OutputDir)"
    foreach ($a in $State.SelectedApps) {
        $lines += "    - $a.rdp"
    }
    if ($State.AccessType -in 'Web','Both') {
        $endpoint = if ($State.Probe -and $State.Probe.webEndpoint) { $State.Probe.webEndpoint.url } else { '(sunucu tarafında HTML5 endpoint tespit edilemedi)' }
        $lines += "  Web URL: $endpoint"
    }

    $rtb.Text = ($lines -join "`r`n")
}

# ---------------------------------------------------------------------------
# Quick server probe (TCP only) - used by the manual "Probe server" button.
# ServerProbe.ps1 (Ajan C1) provides the full component-level probe for
# step 2's automatic population.
# ---------------------------------------------------------------------------
function Invoke-ServerProbeQuick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Ip,
        [Parameter(Mandatory)][int]    $Port,
        [Parameter(Mandatory)][hashtable] $State
    )

    $result = [pscustomobject]@{ Reachable = $false; Os = ''; Error = '' }
    try {
        $conn = Test-NetConnection -ComputerName $Ip -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
        $result.Reachable = [bool]$conn
        if ($result.Reachable) {
            $os = (Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Ip -ErrorAction SilentlyContinue)
            if ($os) { $result.Os = $os.Caption }
        }
    } catch {
        $result.Error = $_.Exception.Message
    }
    Write-SetupLog -Message ("Quick probe {0}:{1} -> Reachable={2} Os='{3}'" -f $Ip, $Port, $result.Reachable, $result.Os)
    return $result
}

# ---------------------------------------------------------------------------
# Wizard orchestrator
# ---------------------------------------------------------------------------
function Show-ClientWizard {
    <#
    .SYNOPSIS  Shows the 4-step setup wizard and returns the resulting state.
    .DESCRIPTION
        Returns the populated $State hashtable if the user completes the
        wizard, or $null if they cancel.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('tr', 'en')]
        [string] $Language = 'tr',

        # If provided, the wizard will skip the manual probe and use this
        # payload as the ServerProbe result. Used by the headless installer
        # driver and by the tests.
        [psobject] $PreloadedProbe = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $strings = New-SetupUiStrings -Language $Language
    $state   = New-WizardState
    $state.Strings = $strings

    if ($PreloadedProbe) { $state.Probe = $PreloadedProbe }

    # --- Form ---------------------------------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $form.Text              = $strings.FormTitle
    $form.FormBorderStyle   = 'FixedDialog'
    $form.StartPosition     = 'CenterScreen'
    $form.ClientSize        = New-Object System.Drawing.Size(620, 540)
    $form.MinimizeBox       = $false
    $form.MaximizeBox       = $false
    $form.BackColor         = $state.Palette.Background

    # Top host panel that swaps content per step.
    $hostPanel = New-Object System.Windows.Forms.Panel
    $hostPanel.Location = New-Object System.Drawing.Point(0, 0)
    $hostPanel.Size     = New-Object System.Drawing.Size(620, 460)
    $hostPanel.BackColor = $state.Palette.Background
    $form.Controls.Add($hostPanel)

    # Tooltip for help buttons.
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.AutoPopDelay = 8000
    $tooltip.InitialDelay  = 400

    # --- Bottom button strip -----------------------------------------------
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Location = New-Object System.Drawing.Point(0, 460)
    $bottomPanel.Size     = New-Object System.Drawing.Size(620, 80)
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(232, 232, 232)
    $form.Controls.Add($bottomPanel)

    $btnBack    = New-Button -Text $strings.BackButton    -X 230 -Y 24 -Width 100 -Height 32 -BackColor [System.Drawing.Color]::FromArgb(200,200,200) -ForeColor $state.Palette.Text -Parent $bottomPanel
    $btnNext    = New-Button -Text $strings.NextButton    -X 340 -Y 24 -Width 100 -Height 32 -BackColor $state.Palette.Accent -Parent $bottomPanel
    $btnInstall = New-Button -Text $strings.InstallButton -X 340 -Y 24 -Width 130 -Height 32 -BackColor $state.Palette.Success  -Parent $bottomPanel
    $btnInstall.Visible = $false
    $btnCancel  = New-Button -Text $strings.CancelButton  -X 480 -Y 24 -Width 100 -Height 32 -BackColor [System.Drawing.Color]::FromArgb(200,200,200) -ForeColor $state.Palette.Text -Parent $bottomPanel

    $btnHelp = New-HelpButton -X 580 -Y 24 -Parent $bottomPanel
    $tooltip.SetToolTip($btnHelp, $strings.HelpTooltip)

    # --- Step navigation helpers ------------------------------------------
    $goNext = {
        try {
            Write-SetupLog -Message ("Wizard: advancing from step {0}" -f $state.CurrentStep)

            switch ($state.CurrentStep) {
                1 {
                    $state.Server.Ip             = $state['_tbIp'].Text
                    $state.Server.Port           = [int]$state['_tbPort'].Text
                    $state.Server.Username       = $state['_tbUser'].Text
                    $state.Server.SecurePassword = $state['_tbPass'].SecurePassword

                    # Run the full server probe (Ajan C1 module).
                    $probe = Invoke-FullServerProbe -Ip $state.Server.Ip -State $state
                    $state.Probe = $probe

                    Build-Step2 -Host $hostPanel -State $state -BackButton $btnBack -NextButton $btnNext -ToolTip $tooltip
                    Populate-Step2 -State $state
                }
                2 {
                    Build-Step3 -Host $hostPanel -State $state -BackButton $btnBack -NextButton $btnNext
                }
                3 {
                    Capture-Step3 -State $state
                    if ($state.CredentialMode -eq 'Embed') {
                        $ans = [System.Windows.Forms.MessageBox]::Show($strings.EmbedWarning, $strings.WarningTitle, 'YesNo', 'Warning')
                        if ($ans -ne 'Yes') { return }
                    }
                    Build-Step4 -Host $hostPanel -State $state -BackButton $btnBack -InstallButton $btnInstall -CancelButton $btnCancel
                    Populate-Step4 -State $state
                    $btnNext.Visible     = $false
                    $btnInstall.Visible  = $true
                    $btnCancel.Visible   = $true
                    $btnBack.Visible     = $true
                }
                default { return }
            }

            $state.CurrentStep++
            Set-AeroTheme -Control $hostPanel
        } catch {
            Write-SetupLog -Level Error -Message ("goNext error: {0}" -f $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $strings.ErrorTitle, 'OK', 'Error') | Out-Null
        }
    }

    $goBack = {
        try {
            Write-SetupLog -Message ("Wizard: stepping back from {0}" -f $state.CurrentStep)
            if ($state.CurrentStep -le 1) { return }

            switch ($state.CurrentStep) {
                3 { Build-Step2 -Host $hostPanel -State $state -BackButton $btnBack -NextButton $btnNext -ToolTip $tooltip; Populate-Step2 -State $state }
                4 { Build-Step3 -Host $hostPanel -State $state -BackButton $btnBack -NextButton $btnNext; $btnInstall.Visible = $false; $btnNext.Visible = $true }
            }
            $state.CurrentStep--
            Set-AeroTheme -Control $hostPanel
        } catch {
            Write-SetupLog -Level Error -Message ("goBack error: {0}" -f $_.Exception.Message)
        }
    }

    $installClick = {
        try {
            Write-SetupLog -Message "Wizard: install started"
            $progress = $state['_installProgress']
            $progress.Visible = $true
            $progress.Value   = 0
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

            # Hand off to the install orchestrator (Ajan C2 + C5).
            $result = Start-ClientInstall -State $state -ProgressCallback {
                param($pct)
                if ($progress.InvokeRequired) {
                    $progress.Invoke([Action[int]]{ param($v) $progress.Value = $v }, [int]$pct) | Out-Null
                } else {
                    $progress.Value = [int]$pct
                }
            }

            if ($result.Success) {
                $progress.Value = 100
                Write-SetupLog -Message "Install completed successfully"
                [System.Windows.Forms.MessageBox]::Show($strings.InstallDone, $strings.FormTitle, 'OK', 'Information') | Out-Null
                $form.DialogResult = 'OK'
                $form.Close()
            } else {
                Write-SetupLog -Level Error -Message ("Install failed: {0}" -f $result.Error)
                [System.Windows.Forms.MessageBox]::Show($result.Error, $strings.ErrorTitle, 'OK', 'Error') | Out-Null
            }
        } catch {
            Write-SetupLog -Level Error -Message ("Install error: {0}" -f $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $strings.ErrorTitle, 'OK', 'Error') | Out-Null
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    $cancelClick = {
        $ans = [System.Windows.Forms.MessageBox]::Show($strings.ConfirmCancel, $strings.ConfirmCancelCap, 'YesNo', 'Question')
        if ($ans -eq 'Yes') {
            Write-SetupLog -Message "Wizard cancelled by user"
            $form.DialogResult = 'Cancel'
            $form.Close()
        }
    }

    $helpClick = {
        $helpText = switch ($state.CurrentStep) {
            1 { "Sunucu IP'si, port (varsayılan 3389), etki alanı\kullanıcı adı ve parolayı girin. 'Sunucuyu Tara' butonu hızlı bir TCP testi yapar." }
            2 { "Sunucudaki bileşenlerin durumu listelenir. Yeşil: hazır, sarı: dikkat, kırmızı: eksik." }
            3 { "Yayınlanmış uygulamalardan birden fazlasını seçebilirsiniz. Erişim tipi için 'Native' önerilir." }
            4 { "Tüm seçimlerin özetini kontrol edin ve 'Kurulumu Başlat' ile devam edin." }
        }
        [System.Windows.Forms.MessageBox]::Show($helpText, $strings.HelpTooltip, 'OK', 'Information') | Out-Null
    }

    $btnNext.Add_Click($goNext)
    $btnBack.Add_Click($goBack)
    $btnInstall.Add_Click($installClick)
    $btnCancel.Add_Click($cancelClick)
    $btnHelp.Add_Click($helpClick)

    # Form close request: route through the cancel handler.
    $form.add_FormClosing({
        param($sender, $e)
        if ($form.DialogResult -eq 'None') {
            $ans = [System.Windows.Forms.MessageBox]::Show($strings.ConfirmCancel, $strings.ConfirmCancelCap, 'YesNo', 'Question')
            if ($ans -ne 'Yes') {
                $e.Cancel = $true
                return
            }
        }
        Write-SetupLog -Message ("Wizard closed at step {0} with DialogResult {1}" -f $state.CurrentStep, $form.DialogResult)
    })

    Build-Step1 -Host $hostPanel -State $state -NextButton $btnNext -ProbeButton $null -ToolTip $tooltip

    Set-AeroTheme -Control $form
    $form.Topmost = $false
    Write-SetupLog -Message ("Wizard started (language={0})" -f $Language)
    $dr = $form.ShowDialog()
    if ($dr -eq 'OK') { return $state } else { return $null }
}

# Public alias
function Start-ClientSetupWizard {
    [CmdletBinding()]
    param([ValidateSet('tr','en')][string] $Language = 'tr', [psobject] $PreloadedProbe = $null)
    Show-ClientWizard -Language $Language -PreloadedProbe $PreloadedProbe
}

# ---------------------------------------------------------------------------
# Module wiring - load the real client-side modules so the wizard hooks can
# delegate to them. Each Import-Module is guarded: the file is resolved
# relative to the script root, a missing file logs a warning (the wizard
# still works in a degraded mode for local testing), and any syntax/runtime
# error during dot-source is caught and surfaced through Write-SetupLog.
# ---------------------------------------------------------------------------

function Import-ClientModule {
    <#
    .SYNOPSIS
        Dot-sources a client-side module that lives next to SetupUI.ps1 and
        returns $true on success, $false on failure. Failures are logged
        through Write-SetupLog so the wizard can degrade gracefully.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name
    )

    $baseDir = $PSScriptRoot
    if (-not $baseDir -and $MyInvocation.MyCommand.Path) {
        $baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if (-not $baseDir) {
        $baseDir = (Get-Location).Path
    }
    $modulePath = Join-Path -Path $baseDir -ChildPath $Name
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-SetupLog -Level Warn -Message ("Modül bulunamadı, stub'a düşüyor: {0}" -f $modulePath)
        return $false
    }
    try {
        . (Get-Item -LiteralPath $modulePath).FullName
        Write-SetupLog -Message ("Modül yüklendi: {0}" -f $modulePath)
        return $true
    } catch {
        Write-SetupLog -Level Error -Message ("Modül yüklenemedi: {0} -> {1}" -f $modulePath, $_.Exception.Message)
        return $false
    }
}

$script:ClientModulesLoaded = @{
    ServerProbe = (Import-ClientModule -Name 'ServerProbe.ps1')
    RdpBuilder  = (Import-ClientModule -Name 'RdpBuilder.ps1')
    WebShortcuts= (Import-ClientModule -Name 'WebShortcuts.ps1')
    Credential  = (Import-ClientModule -Name 'Credential.ps1')
    AppRegistry = (Import-ClientModule -Name 'AppRegistry.ps1')
    SelfTest    = (Import-ClientModule -Name 'SelfTest.ps1')
}

# ---------------------------------------------------------------------------
# Wizard hooks - delegate to the real modules when they are available, and
# fall back to safe placeholders otherwise. This way the wizard can still be
# loaded and exercised locally even when running outside the full install
# layout (eg. Pester tests on a developer workstation).
# ---------------------------------------------------------------------------

function Invoke-FullServerProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Ip,
        [Parameter(Mandatory)][hashtable] $State
    )

    if (-not $script:ClientModulesLoaded.ServerProbe) {
        Write-SetupLog -Level Warn -Message ("ServerProbe.ps1 yüklü değil; stub sonuç döndürülüyor ({0})" -f $Ip)
        return [pscustomobject]@{
            server             = $Ip
            os                 = 'Unknown (probe module not loaded)'
            reachable          = $true
            winrm              = $false
            components         = [pscustomobject]@{
                RDP_Port = [pscustomobject]@{ status = 'ok';      value = '3389 open' }
                RDS_Role = [pscustomobject]@{ status = 'warning'; value = 'ServerProbe.ps1 not loaded' }
            }
            existingRemoteApps = @()
            recommendations    = @('ServerProbe.ps1 modülü yüklenmedi. Ajan C1 çıktısı bekleniyor.')
            webEndpoint        = $null
        }
    }

    Write-SetupLog -Message ("Invoke-FullServerProbe: {0}" -f $Ip)
    try {
        # WinRM/WMI için PSCredential gerekli; State'de yoksa boş credential
        # ile bağlanmaya çalışıp, başarısız olursa stub'a düşeriz.
        $cred = $null
        if ($State -and $State.ContainsKey('_securePass')) {
            $cred = New-Object System.Management.Automation.PSCredential(
                [string]$State.Server.Username,
                [System.Security.SecureString]$State.Server.SecurePassword
            )
        } else {
            $cred = New-Object System.Management.Automation.PSCredential(
                'guest',
                (ConvertTo-SecureString 'placeholder' -AsPlainText -Force)
            )
        }
        $probe = Invoke-ServerProbe -Server $Ip -Credential $cred -PassThru $true
        Write-SetupLog -Message ("Invoke-FullServerProbe tamamlandı: reachable={0} os='{1}' apps={2}" -f $probe.reachable, $probe.os, $probe.existingRemoteApps.Count)
        return $probe
    } catch {
        Write-SetupLog -Level Error -Message ("Invoke-ServerProbe başarısız: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{
            server             = $Ip
            os                 = ''
            reachable          = $false
            winrm              = $false
            components         = [pscustomobject]@{
                RDP_Port = [pscustomobject]@{ status = 'error'; value = "Probe failed: $($_.Exception.Message)" }
            }
            existingRemoteApps = @()
            recommendations    = @("Sunucu tespiti başarısız: $($_.Exception.Message)")
            webEndpoint        = $null
        }
    }
}

function Start-ClientInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $State,
        [scriptblock] $ProgressCallback
    )

    $selectedApps = @()
    if ($State.ContainsKey('SelectedAppObjects') -and $State.SelectedAppObjects) {
        $selectedApps = @($State.SelectedAppObjects)
    } elseif ($State.ContainsKey('SelectedApps')) {
        foreach ($id in @($State.SelectedApps)) {
            $selectedApps += ([pscustomobject]@{ id = [string]$id; alias = [string]$id; name = [string]$id; path = '' })
        }
    }
    $accessType   = if ($State.ContainsKey('AccessType')) { [string]$State.AccessType } else { 'Native' }
    $credMode     = if ($State.ContainsKey('CredentialMode')) { [string]$State.CredentialMode } else { 'Ask' }

    Write-SetupLog -Message ("Start-ClientInstall: {0} uygulama, access={1}, cred={2}" -f $selectedApps.Count, $accessType, $credMode)

    if (-not $script:ClientModulesLoaded.RdpBuilder) {
        Write-SetupLog -Level Warn -Message "RdpBuilder.ps1 yüklü değil; install atlandı (stub)."
        return [pscustomobject]@{ Success = $false; Error = 'RdpBuilder.ps1 modülü yüklenmedi.'; OutputDir = $State.OutputDir }
    }

    $outputDir = $State.OutputDir
    try {
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $endpoint = $null
        if ($State -and ($State.Probe -as [psobject])) {
            $endpoint = $State.Probe.webEndpoint
        }
        $endpointType = if ($endpoint -and $endpoint.type -in @('RDWeb', 'Guacamole')) { [string]$endpoint.type } else { 'RDWeb' }

        # New-RdpFileForApps hashtable[] istiyor; sunucudan gelen existingRemoteApps
        # PSCustomObject olduğu için ortak bir forma çeviriyoruz.
        $rdpApps = @()
        foreach ($app in $selectedApps) {
            $rdpApps += @{
                Alias = if ($app.alias) { [string]$app.alias } else { [string]$app.id }
                Name  = [string]$app.name
            }
        }

        # 1) .rdp dosyaları (Native veya Both modunda)
        $generatedRdp = @()
        if ($accessType -in @('Native', 'Both')) {
            if ($rdpApps.Count -eq 0) {
                Write-SetupLog -Level Warn -Message "Seçili uygulama yok; .rdp üretimi atlandı."
            } else {
                $generatedRdp = @(New-RdpFileForApps -Apps $rdpApps -Server $State.Server.Ip -Username $State.Server.Username -OutputDir $outputDir)
                Write-SetupLog -Message ("{0} adet .rdp dosyası üretildi." -f $generatedRdp.Count)
            }
        }

        # 2) HTML5 web kısayolları (Web veya Both modunda)
        if ($accessType -in @('Web', 'Both') -and $script:ClientModulesLoaded.WebShortcuts -and $endpoint -and $endpoint.url) {
            try {
                $webCount = 0
                foreach ($app in $selectedApps) {
                    $null = New-WebShortcutBundle -EndpointType $endpointType -Server $State.Server.Ip -AppName ([string]$app.name) -AppId ([string]$app.id) -WebPath ([string]$endpoint.url) -OutputPath (Join-Path $outputDir 'web')
                    $webCount++
                }
                Write-SetupLog -Message ("{0} adet web kısayolu üretildi." -f $webCount)
            } catch {
                Write-SetupLog -Level Warn -Message ("Web kısayolları üretilemedi: {0}" -f $_.Exception.Message)
            }
        } elseif ($accessType -in @('Web', 'Both')) {
            Write-SetupLog -Level Warn -Message "Web modu seçildi ama WebShortcuts.ps1 yüklü değil veya HTML5 endpoint tespit edilmedi; web kısayolları atlandı."
        }

        # 3) Credential Manager (Save modunda)
        if ($credMode -eq 'Save' -and $script:ClientModulesLoaded.Credential) {
            foreach ($app in $selectedApps) {
                $target = Format-StoredCredentialTarget -Server $State.Server.Ip -AppId ([string]$app.id)
                $null = New-StoredCredential -Target $target -UserName $State.Server.Username -SecurePassword $State.Server.SecurePassword
            }
            Write-SetupLog -Message "Credential Manager kayıtları yazıldı."
        }

        # 4) AppRegistry'ye uygulama kayıtları
        if ($script:ClientModulesLoaded.AppRegistry -and $rdpApps.Count -gt 0) {
            $regPath = Get-AppRegistryPath
            if (-not (Test-Path -LiteralPath $regPath)) {
                $null = Initialize-AppRegistryFile -Path $regPath
            }
            for ($i = 0; $i -lt $selectedApps.Count; $i++) {
                $app   = $selectedApps[$i]
                $rdp   = if ($generatedRdp.Count -gt $i) { $generatedRdp[$i] } else { $null }
                if (-not $rdp) { continue }
                $null = Register-App -Id ([string]$app.id) -Name ([string]$app.name) -Server $State.Server.Ip -Port $State.Server.Port -RdpPath $rdp -RemoteAppAlias ([string]$app.alias) -CredentialMode $credMode
            }
            Write-SetupLog -Message "AppRegistry güncellendi."
        }

        # 5) SelfTest (bağlantı doğrulama) - opsiyonel, modül yüklüyse çağrılır
        if ($script:ClientModulesLoaded.SelfTest) {
            try {
                $report = Test-ServerConnection -Server $State.Server.Ip -Port $State.Server.Port
                Write-SetupLog -Message ("Self-test sonucu: {0}" -f ($report | Out-String))
            } catch {
                Write-SetupLog -Level Warn -Message ("Self-test çalıştırılamadı: {0}" -f $_.Exception.Message)
            }
        }

        if ($ProgressCallback) { & $ProgressCallback 100 }
        return [pscustomobject]@{ Success = $true; Error = ''; OutputDir = $outputDir }
    } catch {
        Write-SetupLog -Level Error -Message ("Install hata: {0}" -f $_.Exception.Message)
        return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; OutputDir = $outputDir }
    }
}

# ---------------------------------------------------------------------------
# If invoked directly (not dot-sourced), launch the wizard.
# ---------------------------------------------------------------------------
if ($MyInvocation.InvocationName -and $MyInvocation.MyCommand.Path -like '*SetupUI.ps1' -and $Host.Name -eq 'ConsoleHost') {
    try {
        Start-ClientSetupWizard
    } catch {
        Write-Error -ErrorRecord $_
    }
}