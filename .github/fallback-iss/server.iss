; Fallback Server installer.
; CI copies this file to build\server.iss (repo root is ..).
; Compiling in place from .github\fallback-iss needs ..\..
#if FileExists("..\src\assets\icon.ico")
  #define FALLBACK_SOURCEDIR ".."
#elif FileExists("..\..\src\assets\icon.ico")
  #define FALLBACK_SOURCEDIR "..\.."
#else
  #define FALLBACK_SOURCEDIR ".."
#endif

[Setup]
AppId=8B6A8C2D-1234-5678-9012-RDPVB-SERVER1
AppName=Rdp Virtual Box App - Server
AppVersion=1.0.1
AppVerName=Rdp Virtual Box App - Server 1.0.1
AppPublisher=ferhatdeveloper
AppPublisherURL=https://github.com/ferhatdeveloper/VirtualAppRDP
AppSupportURL=https://github.com/ferhatdeveloper/VirtualAppRDP/issues
AppUpdatesURL=https://github.com/ferhatdeveloper/VirtualAppRDP/releases
AppCopyright=Copyright (C) 2026 Rdp Virtual Box App
DefaultDirName={autopf}\RdpVirtualBoxApp
DefaultGroupName=Rdp Virtual Box App - Server
DisableProgramGroupPage=yes
AllowNoIcons=yes
WizardStyle=modern
WizardSizePercent=120
PrivilegesRequired=admin
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SourceDir={#FALLBACK_SOURCEDIR}
OutputDir=build\output
OutputBaseFilename=RdpVirtualBoxApp-Server-v1.0.1
SetupIconFile=src\assets\icon.ico
WizardSmallImageFile=src\assets\server\server-wizard.bmp
WizardImageFile=src\assets\server\server-banner.bmp
LicenseFile=LICENSE
Compression=lzma2/ultra
SolidCompression=yes
VersionInfoVersion=1.0.1.0
VersionInfoCompany=ferhatdeveloper
VersionInfoDescription=Rdp Virtual Box App Server Setup
VersionInfoProductName=Rdp Virtual Box App Server
VersionInfoCopyright=Copyright (C) 2026 Rdp Virtual Box App
UninstallDisplayIcon={app}\Assets\icon.ico
UninstallDisplayName=Rdp Virtual Box App - Server

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "src\powershell\server\*"; DestDir: "{app}\PowerShell"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "src\config\server\*"; DestDir: "{app}\Config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "src\assets\icon.ico"; DestDir: "{app}\Assets"; Flags: ignoreversion
Source: "src\assets\server\*"; DestDir: "{app}\Assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "src\powershell\server\ServerSetupUI.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\RdpVirtualBoxApp"; Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Logs"; Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Config"; Permissions: users-modify
Name: "{commonappdata}\RdpVirtualBoxApp\Manifest"; Permissions: users-modify

[Icons]
Name: "{group}\Rdp Virtual Box App - Server"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\ServerSetupUI.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\icon.ico"
Name: "{group}\{cm:UninstallProgram,Rdp Virtual Box App - Server}"; Filename: "{uninstallexe}"; IconFilename: "{app}\Assets\icon.ico"
Name: "{autodesktop}\Rdp Virtual Box App - Server"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\ServerSetupUI.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\icon.ico"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\ServerSetupUI.ps1"""; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,Rdp Virtual Box App - Server}"; Flags: nowait postinstall skipifsilent runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{userappdata}\RdpVirtualBoxApp"
