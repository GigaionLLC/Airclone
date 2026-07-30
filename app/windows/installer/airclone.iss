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
; `force` (not `yes`): close a running Airclone — and any rclone.exe still
; holding a file in {app} — WITHOUT prompting. A prompt is invisible in the
; Store's silent install/uninstall, and an un-closed process leaves undeletable
; files behind in {app}, which fails Store policy 10.2.7 (clean removal).
CloseApplications=force
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

[UninstallDelete]
; CLEAN REMOVAL (Microsoft Store policy 10.2.7). Inno only deletes what it logged
; at install time, so anything that appears in {app} afterwards is left behind —
; and certification failed us on exactly that, finding files still in
; C:\Program Files\Airclone (report 2026-07-29). Sweep the whole install
; directory so nothing can survive, whatever put it there. The running
; uninstaller's own unins000.* are skipped here (locked) and removed by Inno's
; normal self-delete, which then drops the now-empty directory.
; NOTE: {app} only — user data lives outside it and is handled in [Code] below.
Type: filesandordirs; Name: "{app}"

[Code]
// Offer to remove Airclone's OWN data too, so an uninstall can be complete.
// Deliberately opt-IN and narrowly scoped to two dirs: the app-support one
// (userappdata: the managed engine dir, config backups, shared_preferences) and
// the cache one (localappdata: on-disk thumbnail/preview cache). Both are
// path_provider's <CompanyName>\<ProductName> dirs, taken from the exe's version
// info (see windows/runner/Runner.rc).
// It NEVER touches %APPDATA%\rclone\rclone.conf: that file is rclone's own, is
// shared with the rclone CLI, and holds the user's remotes + OAuth tokens.
// SuppressibleMsgBox returns the IDNO default under /SILENT and /VERYSILENT, so
// the Store's silent uninstall keeps user data untouched and never blocks; only
// an interactive uninstall is asked.
// (Line comments, not brace comments: a brace comment would be terminated early
// by the closing brace of any Inno constant named in it.)
procedure RemoveUserDataIfConfirmed;
var
  Support, Cache: String;
begin
  Support := ExpandConstant('{userappdata}\{#AppPublisher}\{#AppName}');
  Cache := ExpandConstant('{localappdata}\{#AppPublisher}\{#AppName}');
  if not (DirExists(Support) or DirExists(Cache)) then
    exit;
  if SuppressibleMsgBox(
       'Also remove Airclone''s own settings and cached thumbnails?' + #13#10#13#10 +
       'Your rclone remotes (rclone.conf) are NOT touched — keep this data if you '
       + 'plan to reinstall.',
       mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) <> IDYES then
    exit;
  DelTree(Support, True, True, True);
  DelTree(Cache, True, True, True);
  // Drop the now-empty publisher folder as well; a no-op if anything else is in
  // it (another Gigaion app).
  RemoveDir(ExpandConstant('{userappdata}\{#AppPublisher}'));
  RemoveDir(ExpandConstant('{localappdata}\{#AppPublisher}'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveUserDataIfConfirmed;
end;
