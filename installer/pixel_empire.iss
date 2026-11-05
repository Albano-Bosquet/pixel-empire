; Inno Setup script for Pixel Empire. Build with build_installer.bat
; (exports the game first, then compiles this script with ISCC).

#define AppName "Pixel Empire"
#define AppVersion "1.5.3"
#define AppExe "PixelEmpire.exe"

[Setup]
AppId={{6F1B2C4A-8D3E-4B7A-9C51-3E2A7D9B4F10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Pixel Empire
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Installs per user by default (no admin needed); the dialog allows all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=PixelEmpire_Setup_{#AppVersion}
SetupIconFile=..\build\icon.ico
UninstallDisplayIcon={app}\PixelEmpire.ico
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\PixelEmpire.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\icon.ico"; DestDir: "{app}"; DestName: "PixelEmpire.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\PixelEmpire.ico"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\PixelEmpire.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
