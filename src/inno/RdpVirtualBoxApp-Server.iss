; =============================================================================
;  RdpVirtualBoxApp-Server.iss
;  Inno Setup Script - Server-Side Installer
;  Product: Rdp Virtual Box App - Server
;  Author : Ajan S4
;  Notes  : Requires admin rights, installs PowerShell modules to
;           %ProgramFiles%\RdpVirtualBoxApp and config/logs under
;           %ProgramData%\RdpVirtualBoxApp.
; =============================================================================

#define MyAppName      "EXFIN RemoteAPP - Server"
#define MyAppShortName  "RdpVirtualBoxApp-Server"
#define MyAppVersion    "1.1.5"
#define MyAppPublisher  "ferhatdeveloper"
#define MyAppURL        "https://github.com/ferhatdeveloper/VirtualAppRDP"
#define MyAppExeName    "ServerSetupUI.ps1"
; 32-bit Setup.exe + 64-bit install mode: never rely on PATH for powershell.exe
#define PowerShellExe   "{sys}\WindowsPowerShell\v1.0\powershell.exe"

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
; dialog + SetupLdr extract, RDS oturumunda TEMP=...\Temp\N iken
; "The system cannot find the path specified" (baslik: Setup) uretir.
AllowNoIcons=yes
; Tek dosya kurucu (UseSetupLdr=no .exe + .bin ayirir). x64 loader RDS/WOW64 yol sorunlarini azaltir.
UseSetupLdr=x64
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
OutputBaseFilename=EXFIN-RemoteAPP-Server-v1.1.5
VersionInfoVersion=1.1.5.0
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
UsedUserAreasWarning=no

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
; React dashboard (Open File / uygulama secimi)
Source: "src\dashboard\dist\*"; DestDir: "{app}\Dashboard"; Flags: ignoreversion recursesubdirs createallsubdirs
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
Name: "{group}\{#MyAppName}";                   Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\{#MyAppExeName}"""; WorkingDir: "{app}\PowerShell"; IconFilename: "{app}\Assets\icon.ico"; Comment: "EXFIN RemoteAPP - Server Kurulum Sihirbazi"
Name: "{group}\RemoteApp Indirme Portali";      Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\Open-DownloadPortal.ps1"""; WorkingDir: "{app}\PowerShell"; IconFilename: "{app}\Assets\icon.ico"; Comment: "Musteri .rdp indirme sayfasi (8001 / 8444)"
Name: "{group}\Probe REST API Durumu";          Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\Start-ProbeApiHost.ps1"" -Mode Status"; WorkingDir: "{app}\PowerShell"; IconFilename: "{app}\Assets\icon.ico"; Comment: "Probe REST API dinleme durumu"
Name: "{group}\Sunucu Klasoru";                 Filename: "{app}";            IconFilename: "{app}\Assets\icon.ico"; Comment: "Kurulan sunucu dosyalari"
Name: "{group}\Log Dosyalari";                  Filename: "{commonappdata}\RdpVirtualBoxApp\Logs"; Comment: "Kurulum log dosyalari"
Name: "{group}\Yardim / GitHub";                Filename: "{#MyAppURL}";      Comment: "Proje sayfasi"
; Desktop shortcut (optional task)
Name: "{autodesktop}\{#MyAppName}";              Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\{#MyAppExeName}"""; WorkingDir: "{app}\PowerShell"; IconFilename: "{app}\Assets\icon.ico"; Comment: "EXFIN RemoteAPP - Server Kurulum"; Tasks: desktopicon

[Run]
; First-run: detect LAN/WAN/VPN, seed ProgramData (only if missing), firewall, Probe 8444+webPort, Caddy 8445
Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\Install-ServerRuntime.ps1"""; WorkingDir: "{app}\PowerShell"; StatusMsg: "Sunucu API, portal ve Caddy SSL kuruluyor..."; Flags: runhidden waituntilterminated 64bit
; Optionally launch the wizard at the end of installation
Filename: "{#PowerShellExe}"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\PowerShell\{#MyAppExeName}"""; WorkingDir: "{app}\PowerShell"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent runhidden 64bit

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
function GetPowerShellExe(): String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

function InitializeSetup(): Boolean;
var
  PsExe: String;
  OldRedir: Boolean;
begin
  if not IsWin64 then
  begin
    MsgBox('Bu kurulum yalnizca 64-bit Windows Server (2016/2019/2022) ve Windows 10/11 sistemlerinde desteklenir.',
           mbError, MB_OK);
    Result := False;
    exit;
  end;

  OldRedir := EnableFsRedirection(False);
  try
    PsExe := GetPowerShellExe();
    if not FileExists(PsExe) then
    begin
      MsgBox('Windows PowerShell 5 bulunamadi:' + #13#10 + PsExe + #13#10#13#10 +
             'Lutfen Windows Management Framework''u kurun.',
             mbError, MB_OK);
      Result := False;
      exit;
    end;
  finally
    EnableFsRedirection(OldRedir);
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
    Cleanup := ExpandConstant('{app}\PowerShell\Start-ProbeApiHost.ps1');
    Exec(GetPowerShellExe(),
         '-NoProfile -ExecutionPolicy Bypass -File "' + Cleanup + '" -Mode Uninstall',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\schtasks.exe'),
         '/End /TN "RdpVirtualBoxApp-Caddy"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{sys}\schtasks.exe'),
         '/Delete /TN "RdpVirtualBoxApp-Caddy" /F',
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
