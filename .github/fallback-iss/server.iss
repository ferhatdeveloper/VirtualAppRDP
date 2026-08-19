[Setup]
AppId=8B6A8C2D-1234-5678-9012-RDPVB-SERVER1
AppName=Rdp Virtual Box App - Server
AppVersion=1.0.0
AppVerName=Rdp Virtual Box App - Server 1.0.0
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
OutputDir=output
OutputBaseFilename=RdpVirtualBoxApp-Server-v1.0.0
Compression=lzma2/ultra64
SolidCompression=yes
VersionInfoVersion=1.0.0
VersionInfoCompany=ferhatdeveloper
VersionInfoDescription=Rdp Virtual Box App Server Setup
VersionInfoProductName=Rdp Virtual Box App Server
VersionInfoCopyright=Copyright (C) 2026 Rdp Virtual Box App
UninstallDisplayName=Rdp Virtual Box App - Server

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]

[Dirs]
Name: "{commondata}\RdpVirtualBoxApp"; Permissions: users-modify
Name: "{commondata}\RdpVirtualBoxApp\Logs"; Permissions: users-modify

[Icons]
Name: "{group}\Uninstall Rdp Virtual Box App - Server"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{commondata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{userappdata}\RdpVirtualBoxApp"