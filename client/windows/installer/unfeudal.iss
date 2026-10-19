#define AppVersion GetEnv("UNFEUDAL_VERSION")
#if AppVersion == ""
  #error UNFEUDAL_VERSION is not set
#endif

[Setup]
AppId={{8E0F2D6A-4C1B-4E57-9A3D-6F2B1C7E5A90}
AppName=Unfeudal
AppVersion={#AppVersion}
AppPublisher=Unfeudal contributors
DefaultDirName={autopf}\Unfeudal
DefaultGroupName=Unfeudal
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\LICENSE
OutputDir=..\..\dist
OutputBaseFilename=Unfeudal-{#AppVersion}-windows-x64-setup
UninstallDisplayIcon={app}\unfeudal.exe
Compression=lzma2
SolidCompression=yes

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Unfeudal"; Filename: "{app}\unfeudal.exe"

[Run]
Filename: "{app}\unfeudal.exe"; Flags: nowait postinstall skipifsilent
