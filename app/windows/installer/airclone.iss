; Airclone Windows installer (Inno Setup 6).
;
; Built by CI (release.yml Windows job) and locally with the same command:
;   ISCC /DAppVersion=<x.y.z> [/DSourceDir=<path to Release>] airclone.iss
; -> produces airclone-setup-x64.exe next to this script (OutputDir=.).
;
; Per-user by default (no UAC): lands in %LOCALAPPDATA%\Programs\Airclone, the same
; place the old portable zip was extracted to, so it upgrades cleanly. The Microsoft
; Store installs per-machine via /ALLUSERS (to Program Files) so its package
; validation finds the machine-wide Add/Remove Programs entry — a UAC prompt is
; explicitly allowed for Store installs. The user's config lives under
; %APPDATA%\app.airclone and is never touched by (un)install.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
; Default source = the `flutter build windows --release` output, resolved relative
; to this script: app\windows\installer -> app\build\windows\x64\runner\Release.
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#define AppName "Airclone"
#define AppPublisher "Gigaion, LLC"
#define AppExeName "airclone.exe"
#define AppUrl "https://github.com/GigaionLLC/Airclone"

[Setup]
; Stable AppId — NEVER change it (upgrade detection + the uninstall entry key off
; this GUID). The doubled brace escapes to a literal "{...}" AppId.
AppId={{A44FA56F-0F50-41B9-84FE-BE0085A5AF62}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
; Per-user by default (no admin); a running Airclone is closed for the upgrade.
; The Store passes /ALLUSERS to install per-machine (UAC allowed) so a machine-wide
; Add/Remove Programs entry is registered for its package validation.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
; {autopf} = Program Files when per-machine (/ALLUSERS), else {localappdata}\Programs
; — the latter is exactly the old per-user path, so existing installs still upgrade.
DefaultDirName={autopf}\Airclone
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=.
OutputBaseFilename=airclone-setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Release tree: airclone.exe + Flutter/plugin DLLs + data\ (and
; librclone.dll when the in-process engine was bundled).
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
