; =============================================================================
;  RdpVirtualBoxApp-Server.iss
;  Inno Setup Script - Server-Side Installer
;  Product: Rdp Virtual Box App - Server
;  Author : Ajan S4
;  Notes  : Requires admin rights, installs PowerShell modules to
;           %ProgramFiles%\RdpVirtualBoxApp and config/logs under
;           %ProgramData%\RdpVirtualBoxApp.
; =============================================================================

#define MyAppName      "Rdp Virtual Box App - Server"
#define MyAppShortName  "RdpVirtualBoxApp-Server"
#define MyAppVersion    "1.0.1"
#define MyAppPublisher  "ferhatdeveloper"
#define MyAppURL        "https://github.com/ferhatdeveloper/VirtualAppRDP"
#define MyAppExeName    "ServerSetupUI.ps1"

[Setup]
; NOTE: AppId is a unique GUID identifying this product.
; Do NOT use the same AppId for different products.
AppId=8B6A8C2D-1234-5678-9012-RDPVB-SERVER1
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
AppCopyright=Copyright (C) 2026 {#MyAppPublisher}
DefaultDirName={autopf}\RdpVirtualBoxApp
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; The {user} ... {userovern} ... flag means the installer was run by the
; original (non-admin) user, not by an elevated process.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
AllowNoIcons=yes
; Modern wizard look & feel
WizardStyle=modern
WizardSizePercent=120
; Compression: lzma2 / ultra (no extra LZMA threads — avoids OOM on CI)
Compression=lzma2/ultra
SolidCompression=yes
; Visual assets
SetupIconFile=src\assets\icon.ico
WizardSmallImageFile=src\assets\server\server-wizard.bmp
WizardImageFile=src\assets\server\server-banner.bmp
; Uninstaller
UninstallDisplayIcon={app}\Assets\icon.ico
UninstallDisplayName={#MyAppName}
; Paths are relative to the repository root (this script lives in src\inno).
SourceDir=..\..
OutputDir=build\output
OutputBaseFilename=RdpVirtualBoxApp-Server-v1.0.1
VersionInfoVersion=1.0.1.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}
; Misc
AppMutex=RdpVirtualBoxApp-Server-Setup-Mutex
; Min Windows version: Windows Server 2016 / Windows 10 1607
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=LICENSE

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; PowerShell modules (Server-side)
Source: "src\powershell\server\*"; DestDir: "{app}\PowerShell"; Flags: ignoreversion recursesubdirs createallsubdirs
; Config templates
Source: "src\config\server\*"; DestDir: "{app}\Config"; Flags: ignoreversion recursesubdirs createallsubdirs
; Server assets (icon + wizard / banner bitmaps)
Source: "src\assets\icon.ico"; DestDir: "{app}\Assets"; Flags: ignoreversion
Source: "src\assets\server\*"; DestDir: "{app}\Assets"; Flags: ignoreversion recursesubdirs createallsubdirs
; Launch helper at {app} so {app}\ServerSetupUI.ps1 matches shortcut / [Run] paths
Source: "src\powershell\server\ServerSetupUI.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\RdpVirtualBoxApp";        Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Logs";    Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Config";  Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Manifest";Permissions: users-modify

[Icons]
; Start Menu shortcuts
Name: "{group}\{#MyAppName}";                   Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\icon.ico"; Comment: "Rdp Virtual Box App - Server Kurulum Sihirbazi"
Name: "{group}\Sunucu Klasoru";                 Filename: "{app}";            IconFilename: "{app}\Assets\icon.ico"; Comment: "Kurulan sunucu dosyalari"
Name: "{group}\Log Dosyalari";                  Filename: "{commonappdata}\RdpVirtualBoxApp\Logs"; Comment: "Kurulum log dosyalari"
Name: "{group}\Yardim / GitHub";                Filename: "{#MyAppURL}";      Comment: "Proje sayfasi"
; Desktop shortcut (optional task)
Name: "{autodesktop}\{#MyAppName}";              Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\icon.ico"; Comment: "Rdp Virtual Box App - Server Kurulum"; Tasks: desktopicon

[Run]
; Optionally launch the wizard elevated at the end of installation
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent runhidden

[UninstallDelete]
; Optional: clean up %ProgramData%\RdpVirtualBoxApp entirely on uninstall.
Type: filesandordirs; Name: "{commonappdata}\RdpVirtualBoxApp"
; Remove the per-user app cache if present
Type: filesandordirs; Name: "{userappdata}\RdpVirtualBoxApp"

[Code]
// ---------------------------------------------------------------------------
// Pascal Script: minimal pre-install checks (no heavy logic).
// All Pascal Script code lives in this single [Code] section.
// ---------------------------------------------------------------------------
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Friendly message if .NET Framework / PowerShell prerequisites are missing.
  // The wizard itself will surface a friendlier error in Turkish, but we
  // bail out early here if the OS is plainly unsupported.
  if not IsWin64 then
  begin
    MsgBox('Bu kurulum yalnizca 64-bit Windows Server (2016/2019/2022) ve Windows 10/11 sistemlerinde desteklenir.',
           mbError, MB_OK);
    Result := False;
    exit;
  end;

  // Verify Windows PowerShell 5.x (or PowerShell 7) is available
  if not Exec('powershell.exe', '-NoProfile -Command "$PSVersionTable.PSVersion.Major -ge 5"',
              '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox('Windows PowerShell 5 veya uzeri bulunamadi. Lutfen en gunun Windows Management Framework''u kurun.',
           mbError, MB_OK);
    Result := False;
    exit;
  end;

  Result := True;
end;

// Make sure elevated install dir is honoured even if user accepts the dialog
procedure CurStepChanged(CurStep: TSetupStep);
var
  InstalledVersion, InstalledDate: String;
begin
  if CurStep = ssPostInstall then
  begin
    // Touch a marker file so the wizard knows install completed cleanly
    InstalledVersion := ExpandConstant('{#MyAppVersion}');
    InstalledDate    := GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':');
    SaveStringToFile(ExpandConstant('{commonappdata}\RdpVirtualBoxApp\installed.marker'),
                     'RdpVirtualBoxApp Server v' + InstalledVersion + ' installed on ' + InstalledDate,
                     False);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  Cleanup: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Optional: invoke a PowerShell cleanup script if the server modules
    // expose one. We keep it best-effort and never fail uninstall.
    Cleanup := ExpandConstant('{app}\PowerShell\Uninstall-Cleanup.ps1');
    Exec('powershell.exe',
         '-NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path ''' + Cleanup + ''') { & ''' + Cleanup + ''' | Out-Null }"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function NeedRestart(): Boolean;
begin
  // We don't currently require a reboot after install; PowerShell modules
  // are loaded at runtime, RDS roles are installed but won't restart the box.
  Result := False;
end;

[Messages]
english.BeveledLabel=This wizard installs {#MyAppName} on your computer.
english.SetupWindowTitle={#MyAppName} Setup
english.WelcomeLabel2=This will install [name] on your computer.[br][br]Administrator rights are required for the server setup. Click Next to continue.
english.FinishedHeadingLabel=Installation Complete
english.FinishedLabel=[name] has been installed on your computer.[br][br]You can start it from the Start Menu.[br][br]Click Finish to close this wizard.

turkish.BeveledLabel=Bu sihirbaz, {#MyAppName} uygulamasını bilgisayarınıza kurar.
turkish.SetupWindowTitle={#MyAppName} Kurulumu
turkish.WelcomeLabel2=Bu sihirbaz [name] uygulamasını bilgisayarınıza kuracak.[br][br]Server kurulumu için yönetici hakları gereklidir. Devam etmek için İleri'ye tıklayın.
turkish.FinishedHeadingLabel=Kurulum Tamamlandı
turkish.FinishedLabel=[name] bilgisayarınıza kuruldu.[br][br]Uygulama Start Menu üzerinden başlatılabilir.[br][br]Kurulum sihirbazını kapatmak için Son'a tıklayın.

[CustomMessages]
; Custom Turkish strings referenced from above sections
CreateStartMenu=Start Menu kisayolu olustur

[Registry]
; Add an uninstall-friendly marker in HKLM\Software so IT admins can audit installs.
Root: HKLM; Subkey: "SOFTWARE\RdpVirtualBoxApp\Server"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
