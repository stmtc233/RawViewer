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
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\packaged\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "RawViewer"; ValueData: "Software\RawViewer\Capabilities"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\RawViewer\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Raw Viewer"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "RAW and standard image viewer"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".arw"; ValueData: "RawViewer.arw"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".cr2"; ValueData: "RawViewer.cr2"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".cr3"; ValueData: "RawViewer.cr3"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".dng"; ValueData: "RawViewer.dng"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".nef"; ValueData: "RawViewer.nef"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".orf"; ValueData: "RawViewer.orf"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".raf"; ValueData: "RawViewer.raf"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".rw2"; ValueData: "RawViewer.rw2"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".srw"; ValueData: "RawViewer.srw"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpg"; ValueData: "RawViewer.jpg"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpeg"; ValueData: "RawViewer.jpeg"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".png"; ValueData: "RawViewer.png"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\RawViewer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".webp"; ValueData: "RawViewer.webp"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.arw"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr2"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr3"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.dng"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.nef"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.orf"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.raf"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.rw2"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.srw"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpg"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpeg"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.png"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.webp"; ValueType: string; ValueName: ""; ValueData: "Raw Viewer image"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.arw\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr2\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr3\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.dng\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.nef\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.orf\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.raf\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.rw2\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.srw\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpg\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpeg\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.png\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.webp\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.arw\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr2\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.cr3\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.dng\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.nef\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.orf\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.raf\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.rw2\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.srw\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpg\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.jpeg\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.png\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\RawViewer.webp\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
