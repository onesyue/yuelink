[Setup]
AppName=YueLink
AppVersion={#MyAppVersion}
AppPublisher=Yue.to
AppPublisherURL=https://yue.to
DefaultDirName={autopf}\YueLink
DefaultGroupName=YueLink
OutputDir=.
OutputBaseFilename=YueLink-Windows-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\yuelink.exe
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
; Force-close any running YueLink instance before installing/upgrading.
; Shows a dialog listing the running processes and asks the user to close them
; (or closes them automatically in silent installs).
CloseApplications=yes
CloseApplicationsFilter=yuelink.exe
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\YueLink"; Filename: "{app}\yuelink.exe"
Name: "{group}\{cm:UninstallProgram,YueLink}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\YueLink"; Filename: "{app}\yuelink.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Run]
Filename: "{app}\yuelink.exe"; Description: "{cm:LaunchProgram,YueLink}"; Flags: nowait postinstall skipifsilent
