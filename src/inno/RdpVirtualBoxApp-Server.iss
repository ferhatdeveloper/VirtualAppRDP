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
#define MyAppVersion    "1.0.0"
#define MyAppPublisher  "ferhatdeveloper"
#define MyAppURL        "https://github.com/ferhatdeveloper/VirtualAppRDP"
#define MyAppExeName    "ServerSetupUI.ps1"

[Setup]
; NOTE: AppId is a unique GUID identifying this product.
; Do NOT use the same AppId for different products.
AppId={{8B6A8C2D-1234-5678-9012-RDPVB-SERVER}
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
; Compression: lzma2 / ultra64
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=8
; Visual assets (placeholders - swap when real art is available)
SetupIconFile=..\assets\icon.ico
WizardSmallImageFile=..\assets\server\server-wizard.bmp
WizardImageFile=..\assets\server\server-banner.bmp
; Uninstaller
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Output
OutputDir=..\..\build\output
OutputBaseFilename=RdpVirtualBoxApp-Server-v{#MyAppVersion}
; Misc
ShowLanguageDetectionWarning=no
AppMutex=RdpVirtualBoxApp-Server-Setup-Mutex
; Min Windows version: Windows Server 2016 / Windows 10 1607
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenu";  Description: "{cm:CreateStartMenu}";  GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedenabled

[Files]
; PowerShell modules (Server-side)
Source: "..\powershell\server\*.ps1";                    DestDir: "{app}\PowerShell"; Flags: ignoreversion recursesubdirs createallsubdirs
; Config templates
Source: "..\config\server\*";                            DestDir: "{app}\Config";    Flags: ignoreversion recursesubdirs createallsubdirs
; Server assets (banners, icons)
Source: "..\assets\server\*";                            DestDir: "{app}\Assets";    Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\icon.ico";                            DestDir: "{app}\Assets";    Flags: ignoreversion
; Inno assets (so the wizard image sources are present at runtime too)
Source: "..\assets\server\server-wizard.bmp";            DestDir: "{app}\Assets";    Flags: ignoreversion
Source: "..\assets\server\server-banner.bmp";            DestDir: "{app}\Assets";    Flags: ignoreversion
; Optional helper scripts (Launch helper + README placeholder)
Source: "..\powershell\server\ServerSetupUI.ps1";        DestDir: "{app}";           Flags: ignoreversion

[Dirs]
Name: "{commondata}\RdpVirtualBoxApp";        Permissions: users-modify
Name: "{commondata}\RdpVirtualBoxApp\Logs";    Permissions: users-modify
Name: "{commondata}\RdpVirtualBoxApp\Config";  Permissions: users-modify
Name: "{commondata}\RdpVirtualBoxApp\Manifest";Permissions: users-modify

[Icons]
; Start Menu shortcuts
Name: "{group}\{#MyAppName}";                   Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; IconFilename: "{app}\Assets\icon.ico"; Comment: "Rdp Virtual Box App - Server Kurulum Sihirbazi"
Name: "{group}\Sunucu Klasoru";                 Filename: "{app}";            IconFilename: "{app}\Assets\icon.ico"; Comment: "Kurulan sunucu dosyalari"
Name: "{group}\Log Dosyalari";                  Filename: "{commondata}\RdpVirtualBoxApp\Logs"; Comment: "Kurulum log dosyalari"
Name: "{group}\Yardim / GitHub";                Filename: "{#MyAppURL}";      Comment: "Proje sayfasi"
; Desktop shortcut (optional task)
Name: "{autodesktop}\{#MyAppName}";              Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; IconFilename: "{app}\Assets\icon.ico"; Comment: "Rdp Virtual Box App - Server Kurulum"; Tasks: desktopicon

[Run]
; Optionally launch the wizard elevated at the end of installation
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\{#MyAppExeName}"""; Description: "{cm:LaunchProgram},{#MyAppName}"; Flags: nowait postinstall skipuserselected

[UninstallDelete]
; Optional: clean up %ProgramData%\RdpVirtualBoxApp entirely on uninstall.
Type: filesandordirs; Name: "{commondata}\RdpVirtualBoxApp"
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
begin
  if CurStep = ssPostInstall then
  begin
    // Touch a marker file so the wizard knows install completed cleanly
    SaveStringToFile(ExpandConstant('{commondata}\RdpVirtualBoxApp\installed.marker'),
                     Format('RdpVirtualBoxApp Server v%s installed on %s',
                            [ExpandConstant('{#MyAppVersion}'],
                             FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]),
                     False);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    // Optional: invoke a PowerShell cleanup script if the server modules
    // expose one. We keep it best-effort and never fail uninstall.
    Exec('powershell.exe',
         '-NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path ''{app}\PowerShell\Uninstall-Cleanup.ps1'') { & ''{app}\PowerShell\Uninstall-Cleanup.ps1'' | Out-Null }"',
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
; Custom Turkish messages for better localization of standard wizard pages.
WelcomeLabel2=Bu sihirbaz [name/] uygulamasini bilgisayariniza kuracak.[br][br]Server kurulumu icin yonetici haklari gereklidir. Devam etmek icin Ileri''ye tiklayin.
SelectDirLabel=Kurulum dizinini secin
SelectGroupLabel=Start Menu klasorunu secin
FinishedLabelLabel=[name] bilgisayariniza kuruldu. Uygulama Start Menu uzerinden baslatilabilir.

[CustomMessages]
; Custom Turkish strings referenced from above sections
CreateStartMenu=Start Menu kisayolu olustur

[Registry]
; Add an uninstall-friendly marker in HKLM\Software so IT admins can audit installs.
Root: HKLM; Subkey: "SOFTWARE\RdpVirtualBoxApp\Server"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey