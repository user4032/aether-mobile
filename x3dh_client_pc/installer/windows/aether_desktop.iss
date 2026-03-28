#define MyAppName "Aether Messenger"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Aether"
#define MyAppExeName "x3dh_client_pc.exe"

[Setup]
AppId={{D0C8CF40-2B52-4E72-B714-8E1380EFA1A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Aether Messenger
DefaultGroupName=Aether Messenger
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=AetherMessengerSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Aether Messenger"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Aether Messenger"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Aether Messenger"; Flags: nowait postinstall skipifsilent
