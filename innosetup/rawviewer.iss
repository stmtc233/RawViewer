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
Root: HKCU; Subkey: "Software\Classes\.arw"; ValueType: string; ValueName: ""; ValueData: "RawViewer.arw"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cr2"; ValueType: string; ValueName: ""; ValueData: "RawViewer.cr2"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cr3"; ValueType: string; ValueName: ""; ValueData: "RawViewer.cr3"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.dng"; ValueType: string; ValueName: ""; ValueData: "RawViewer.dng"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.nef"; ValueType: string; ValueName: ""; ValueData: "RawViewer.nef"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.orf"; ValueType: string; ValueName: ""; ValueData: "RawViewer.orf"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.raf"; ValueType: string; ValueName: ""; ValueData: "RawViewer.raf"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.rw2"; ValueType: string; ValueName: ""; ValueData: "RawViewer.rw2"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.srw"; ValueType: string; ValueName: ""; ValueData: "RawViewer.srw"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.jpg"; ValueType: string; ValueName: ""; ValueData: "RawViewer.jpg"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.jpeg"; ValueType: string; ValueName: ""; ValueData: "RawViewer.jpeg"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.png"; ValueType: string; ValueName: ""; ValueData: "RawViewer.png"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.webp"; ValueType: string; ValueName: ""; ValueData: "RawViewer.webp"; Flags: uninsdeletevalue
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
