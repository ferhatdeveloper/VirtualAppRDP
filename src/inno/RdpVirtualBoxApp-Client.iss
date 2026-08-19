; =====================================================================
;  RdpVirtualBoxApp-Client.iss
;  Inno Setup script for the CLIENT setup of "Rdp Virtual Box App".
;
;  This installer extracts the PowerShell wizard, config templates and
;  assets to a per-user folder (no admin required) and creates Start
;  Menu / Quick Launch shortcuts. A pre-flight check validates the host
;  operating system, .NET Framework and PowerShell version before the
;  wizard is launched.
;
;  Build: ISCC.exe RdpVirtualBoxApp-Client.iss
;  Output: build\output\RdpVirtualBoxApp-Client-v1.0.0.exe (~5-8 MB)
; =====================================================================

#define MyAppName            "Rdp Virtual Box App"
#define MyAppShortName        "RdpVirtualBoxApp"
#define MyAppVersion          "1.0.1"
#define MyAppPublisher        "Rdp Virtual Box App"
#define MyAppURL              "https://github.com/ferhatdeveloper/VirtualAppRDP"
#define MyAppSupportURL       "https://github.com/ferhatdeveloper/VirtualAppRDP/issues"
#define MyAppUpdatesURL       "https://github.com/ferhatdeveloper/VirtualAppRDP/releases"
#define MyAppExeName          "SetupUI.ps1"
#define MyAppCopyright        "Copyright (C) 2026 Rdp Virtual Box App"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId for other Inno Setup installers.
AppId=9C7B8D3E-4321-8765-2109-RDPVB-CLIENT1
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppUpdatesURL}
AppCopyright={#MyAppCopyright}

; Per-user install: %LocalAppData%\Programs\RdpVirtualBoxApp
; Falls back to %ProgramFiles% if running elevated.
DefaultDirName={autopf}\{#MyAppShortName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; User experience
AllowNoIcons=yes
WizardStyle=modern
WizardSizePercent=120
WindowVisible=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Minimum Windows version (Windows 10 1809 build 17763 / Windows 11)
MinVersion=10.0

; Architecture
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Output (CI uses ISCC default ./Output; the workflow moves it)
OutputBaseFilename=RdpVirtualBoxApp-Client-v1.0.1
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\assets\icon.ico
UninstallDisplayName={#MyAppName}

; Compression
Compression=lzma2/ultra64
SolidCompression=yes

; Optional licence / version metadata
LicenseFile=..\LICENSE
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Client Setup
VersionInfoProductName={#MyAppName} Client
VersionInfoCopyright={#MyAppCopyright}

; Optional code-signing (comment in if a certificate is available).
; SignTool=signtool /f $qcertfile /p $qpassword /t http://timestamp.digicert.com $f

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish";  MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; PowerShell wizard and helper modules
Source: "..\powershell\client\*"; DestDir: "{app}\powershell"; Flags: ignoreversion recursesubdirs createallsubdirs

; Configuration templates (apps, rdp, web)
Source: "..\config\client\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs

; Icons, banner, wizard images
Source: "..\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
; Per-user working folders created up-front so the wizard can write to them.
Name: "{userappdata}\{#MyAppShortName}"; Permissions: users-modify
Name: "{localappdata}\{#MyAppShortName}\Logs"; Permissions: users-modify
Name: "{userdocs}\{#MyAppShortName}"; Permissions: users-modify

[Icons]
; Start Menu shortcuts
Name: "{group}\{#MyAppName} Setup"; Filename: "{app}\powershell\{#MyAppExeName}"; Comment: "{cm:LaunchSetupComment}"; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\{#MyAppName} README"; Filename: "{app}\assets\README.url"; Tasks: ; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"; IconFilename: "{app}\assets\icon.ico"

; Quick Launch
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppShortName}"; Filename: "{app}\powershell\{#MyAppExeName}"; Tasks: ; IconFilename: "{app}\assets\icon.ico"; Comment: "{cm:LaunchSetupComment}"

; Optional desktop shortcut
Name: "{autodesktop}\{#MyAppName} Setup"; Filename: "{app}\powershell\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\assets\icon.ico"

[Run]
Filename: "{app}\powershell\{#MyAppExeName}"; Description: "{cm:LaunchSetup}"; Flags: nowait postinstall skipifsilent runhidden; Parameters: "-ExecutionPolicy Bypass -File ""{app}\powershell\{#MyAppExeName}"""

[UninstallDelete]
; Per-user data and logs
Type: filesandordirs; Name: "{userappdata}\{#MyAppShortName}"
Type: filesandordirs; Name: "{userlocalappdata}\{#MyAppShortName}"
Type: filesandordirs; Name: "{userdocs}\{#MyAppShortName}"

; Registry entries the wizard may create
Type: regkey; Key: "HKCU\Software\{#MyAppShortName}"

[Messages]
; English custom messages (also act as the default fallback).
english.BeveledLabel=This wizard installs the {#MyAppName} client on your computer.
english.SetupWindowTitle={#MyAppName} Setup
english.WelcomeLabel2=This will install [name] on your computer.[br][br]The setup runs a 4-step wizard that connects to a Remote Desktop server, lists the published applications and creates the matching .rdp shortcuts. No administrator rights are required.[br][br]Click Next to continue.
english.FinishedHeadingLabel=Installation Complete
english.FinishedLabel=[name] has been installed on your computer.[br][br]You can launch the wizard from the Start Menu or use the desktop shortcut.[br][br]Click Finish to close this wizard.
english.LaunchSetup=Launch the Setup Wizard now
english.LaunchSetupComment=Start the {#MyAppName} setup wizard
english.UninstallProgram=Uninstall {#MyAppName}
english.CreateDesktopIcon=Create a desktop shortcut
english.AdditionalIcons=Additional shortcuts:

; Turkish custom messages - shown when the user picks "turkish" at the
; language selector. All strings match the labels rendered by SetupUI.ps1.
turkish.BeveledLabel=Bu sihirbaz, {#MyAppName} istemcisini bilgisayarınıza kurar.
turkish.SetupWindowTitle={#MyAppName} Kurulumu
turkish.WelcomeLabel2=Bu sihirbaz, [name] uygulamasını bilgisayarınıza kuracak.[br][br]Kurulum, 4 adımlı bir sihirbaz çalıştırır: sunucuya bağlanır, yayınlanan uygulamaları listeler ve eşleşen .rdp kısayollarını oluşturur. Yönetici hakları gerektirmez.[br][br]Devam etmek için İleri'ye tıklayın.
turkish.FinishedHeadingLabel=Kurulum Tamamlandı
turkish.FinishedLabel=[name] bilgisayarınıza kuruldu.[br][br]Sihirbazı Başlat menüsünden veya masaüstü kısayolundan çalıştırabilirsiniz.[br][br]Kurulum sihirbazını kapatmak için Son'a tıklayın.
turkish.LaunchSetup=Kurulum Sihirbazını Şimdi Başlat
turkish.LaunchSetupComment={#MyAppName} kurulum sihirbazını başlat
turkish.UninstallProgram={#MyAppName}'i Kaldır
turkish.CreateDesktopIcon=Masaüstü kısayolu oluştur
turkish.AdditionalIcons=Ek kısayollar:

[CustomMessages]
; English fallbacks for compile-time replacement ({cm:...})
english.LaunchSetup=Launch the Setup Wizard now
english.LaunchSetupComment=Start the {#MyAppName} setup wizard

turkish.LaunchSetup=Kurulum Sihirbazını Şimdi Başlat
turkish.LaunchSetupComment={#MyAppName} kurulum sihirbazını başlat

[Code]
// ---------------------------------------------------------------------
//  Pre-flight checks: Windows 10 1809+, .NET Framework 4.7.2+ and
//  PowerShell 5.1+ are required to run the wizard. Anything older is
//  reported to the user as a blocking error.
// ---------------------------------------------------------------------

const
  RequiredBuildNumber   = 17763;     // Windows 10 1809
  RequiredDotNetRelease = 461814;    // .NET 4.7.2 release key
  RequiredPSMajor       = 5;
  RequiredPSMinor       = 1;

function IsWindowsVersionOK: Boolean;
var
  VersionInfo: TWindowsVersion;
begin
  VersionInfo := GetWindowsVersion;
  // Major >= 10 means Windows 10 / 11 / Server 2016+.
  Result := (VersionInfo.Major > 10) or
            ((VersionInfo.Major = 10) and (VersionInfo.Build >= RequiredBuildNumber));
end;

function IsDotNetVersionOK: Boolean;
var
  ReleaseKey: Cardinal;
begin
  Result := False;
  if RegQueryDWordValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', ReleaseKey) then
    Result := ReleaseKey >= RequiredDotNetRelease;
end;

function IsPowerShellVersionOK: Boolean;
var
  Major, Minor: Cardinal;
begin
  Result := False;
  // PowerShell 5.1 ships with Windows Management Framework 5.1.
  if RegQueryDWordValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine', 'PowerShellVersion', Major) then
  begin
    RegQueryDWordValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine', 'PowerShellVersion_Minor', Minor);
    Result := (Major > RequiredPSMajor) or
              ((Major = RequiredPSMajor) and (Minor >= RequiredPSMinor));
  end;
end;

function InitializeSetup: Boolean;
var
  Missing: String;
begin
  Result := True;
  Missing := '';

  if not IsWindowsVersionOK then
    Missing := Missing +
      '  - Windows 10 1809 (build 17763) or later is required.' + #13#10;

  if not IsDotNetVersionOK then
    Missing := Missing +
      '  - .NET Framework 4.7.2 or later is required.' + #13#10;

  if not IsPowerShellVersionOK then
    Missing := Missing +
      '  - PowerShell 5.1 or later is required.' + #13#10;

  if Missing <> '' then
  begin
    MsgBox('The setup cannot continue because the following prerequisites are missing:' + #13 + #10 + #13 + #10 + Missing + #13 + #10 + 'Please update Windows or install the missing components and try again.', mbCriticalError, MB_OK);
    Result := False;
  end;
end;

// ---------------------------------------------------------------------
//  Wizard UI tweaks: heading labels stay in English for both languages
//  (the brand is "Rdp Virtual Box App"), but the descriptive text is
//  localised through the [Messages] block above.
// ---------------------------------------------------------------------

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Reserved for future per-step hooks (e.g. logging, telemetry opt-in).
end;