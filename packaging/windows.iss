#ifndef AppVersion
  #define AppVersion "0.6.0"
#endif
[Setup]
AppId={{668848B0-7AE7-4DB8-A82E-564F7C45F53B}
AppName=Sayqalchi
AppVersion={#AppVersion}
AppPublisher=Sayqalchi contributors
AppPublisherURL=https://github.com/abduraufdev77/Sayqalchi
DefaultDirName={localappdata}\Programs\Sayqalchi
DefaultGroupName=Sayqalchi
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\dist
OutputBaseFilename=Sayqalchi-{#AppVersion}-windows-x64
SetupIconFile=..\windows\Sayqalchi.Windows\Assets\Sayqalchi.ico
UninstallDisplayIcon={app}\Sayqalchi.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
[Files]
Source: "..\dist\windows-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Sayqalchi"; Filename: "{app}\Sayqalchi.exe"
Name: "{autodesktop}\Sayqalchi"; Filename: "{app}\Sayqalchi.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\Sayqalchi.exe"; Description: "Open Sayqalchi"; Flags: nowait postinstall skipifsilent
