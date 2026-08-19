; Fallback Client installer.
; CI copies this file to build\client.iss (repo root is ..).
; Compiling in place from .github\fallback-iss needs ..\..
#if FileExists("..\src\assets\icon.ico")
  #define FALLBACK_SOURCEDIR ".."
#elif FileExists("..\..\src\assets\icon.ico")
  #define FALLBACK_SOURCEDIR "..\.."
#else
  #define FALLBACK_SOURCEDIR ".."
#endif

[Setup]
AppId=9C7B8D3E-4321-8765-2109-RDPVB-CLIENT1
AppName=Rdp Virtual Box App
AppVersion=1.0.1
AppVerName=Rdp Virtual Box App 1.0.1
AppPublisher=Rdp Virtual Box App
AppPublisherURL=https://github.com/ferhatdeveloper/VirtualAppRDP
AppSupportURL=https://github.com/ferhatdeveloper/VirtualAppRDP/issues
AppUpdatesURL=https://github.com/ferhatdeveloper/VirtualAppRDP/releases
AppCopyright=Copyright (C) 2026 Rdp Virtual Box App
DefaultDirName={autopf}\RdpVirtualBoxApp
DefaultGroupName=Rdp Virtual Box App
DisableProgramGroupPage=yes
AllowNoIcons=yes
WizardStyle=modern
WizardSizePercent=120
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SourceDir={#FALLBACK_SOURCEDIR}
OutputDir=build\output
OutputBaseFilename=RdpVirtualBoxApp-Client-v1.0.1
SetupIconFile=src\assets\icon.ico
LicenseFile=LICENSE
Compression=lzma2/ultra
SolidCompression=yes
VersionInfoVersion=1.0.1.0
VersionInfoCompany=Rdp Virtual Box App
VersionInfoDescription=Rdp Virtual Box App Client Setup
VersionInfoProductName=Rdp Virtual Box App Client
VersionInfoCopyright=Copyright (C) 2026 Rdp Virtual Box App
UninstallDisplayIcon={app}\assets\icon.ico
UninstallDisplayName=Rdp Virtual Box App

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "src\powershell\client\*"; DestDir: "{app}\powershell"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "src\config\client\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "src\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
Name: "{userappdata}\RdpVirtualBoxApp"; Permissions: users-modify
Name: "{localappdata}\RdpVirtualBoxApp\Logs"; Permissions: users-modify
Name: "{userdocs}\RdpVirtualBoxApp"; Permissions: users-modify

[Icons]
Name: "{group}\Rdp Virtual Box App Setup"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\powershell\SetupUI.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\Rdp Virtual Box App README"; Filename: "{app}\assets\README.url"; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\{cm:UninstallProgram,Rdp Virtual Box App}"; Filename: "{uninstallexe}"; IconFilename: "{app}\assets\icon.ico"
Name: "{autodesktop}\Rdp Virtual Box App Setup"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\powershell\SetupUI.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\icon.ico"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\powershell\SetupUI.ps1"""; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,Rdp Virtual Box App}"; Flags: nowait postinstall skipifsilent runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{localappdata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{userdocs}\RdpVirtualBoxApp"
