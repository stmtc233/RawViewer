#define MyAppName "rawviewer"
#ifndef MyAppVersion
  #define MyAppVersion "dev"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "rawviewer"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "rawviewer.exe"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "rawviewer-windows-setup"
#endif

[Setup]
AppId={{D95E4549-9D92-4286-A624-A1FF0CF6F23A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
OutputDir=..
OutputBaseFilename={#MyOutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\packaged\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
