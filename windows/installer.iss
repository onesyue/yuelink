[Setup]
AppId={{2C7A4BEF-D5E9-4B1A-8F3C-9E2D8A1F6042}
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

; ── Additional Tasks (shown on wizard "Select Additional Tasks" page) ──────────
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

; ── Post-install launch (shown as checkbox on wizard Finish page) ──────────────
; Note: "postinstall" puts this on the Finish page, NOT the Additional Tasks page.
; It is intentionally independent of the desktopicon task above.
[Run]
Filename: "{app}\yuelink.exe"; Description: "{cm:LaunchProgram,YueLink}"; Flags: nowait postinstall skipifsilent
