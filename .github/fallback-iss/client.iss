[Setup]
AppId=9C7B8D3E-4321-8765-2109-RDPVB-CLIENT1
AppName=Rdp Virtual Box App
AppVersion=1.0.0
AppVerName=Rdp Virtual Box App 1.0.0
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
OutputBaseFilename=RdpVirtualBoxApp-Client-v1.0.0
Compression=lzma2/ultra64
SolidCompression=yes
VersionInfoVersion=1.0.0
VersionInfoCompany=Rdp Virtual Box App
VersionInfoDescription=Rdp Virtual Box App Client Setup
VersionInfoProductName=Rdp Virtual Box App Client
VersionInfoCopyright=Copyright (C) 2026 Rdp Virtual Box App
UninstallDisplayName=Rdp Virtual Box App

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]

[Dirs]
Name: "{userappdata}\RdpVirtualBoxApp"; Permissions: users-modify
Name: "{localappdata}\RdpVirtualBoxApp\Logs"; Permissions: users-modify
Name: "{userdocs}\RdpVirtualBoxApp"; Permissions: users-modify

[Icons]
Name: "{group}\Uninstall Rdp Virtual Box App"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{localappdata}\RdpVirtualBoxApp"
Type: filesandordirs; Name: "{userdocs}\RdpVirtualBoxApp"