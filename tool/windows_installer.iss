; ClashGo Windows installer (Inno Setup 6).
; Build: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" tool\windows_installer.iss
; Source tree comes from flutter build windows --release, which already stages
; core/mihomo.exe and core/geodata next to the exe.
#define AppName "ClashGo"
#define AppVersion "1.2.0"
#define AppExe "clash_go.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{3F1B9A6E-7C2D-4B8A-9E51-6D0F2C4A7B13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=ClashGo
VersionInfoVersion=1.2.0.0
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=..\build\release
OutputBaseFilename=ClashGo-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
