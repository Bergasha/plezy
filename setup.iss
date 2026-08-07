#define Name "Plezy"
#define Version "1.2.3"
#define Publisher "edde746"
#define ExeName "plezy.exe"

[Setup]
AppId={{4213385e-f7be-4f2b-95f9-54082a28bb8f}
AppName={#Name}
AppVersion={#Version}
AppPublisher={#Publisher}
DefaultDirName={autopf}\{#Name}
DefaultGroupName={#Name}
AllowNoIcons=yes
OutputDir=.
OutputBaseFilename=plezy-windows-installer
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
; Needed for /ALLUSERS to take effect, which is how the elevated instance
; started by InitializeSetup below reaches an existing machine-wide install.
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ElevationRequired=Plezy is installed in %1, which requires administrator privileges to update.%n%nRe-run this installer using "Run as administrator", or download the latest installer from https://github.com/edde746/plezy/releases/latest

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "staging\x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Name}"; Filename: "{app}\{#ExeName}"
Name: "{group}\{cm:UninstallProgram,{#Name}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#Name}"; Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchProgram,{#Name}}"; Flags: nowait postinstall; Check: not IsNoRun

[Code]
const
  UninstallSubkey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{4213385e-f7be-4f2b-95f9-54082a28bb8f}_is1';
  WriteProbeName = 'plezy-write-probe.tmp';

function IsNoRun: Boolean;
begin
  Result := ExpandConstant('{param:NORUN|0}') = '1';
end;

function IsX64: Boolean;
begin
  Result := not IsArm64;
end;

{ Directory of an existing installation, or '' when none is registered.
  PrivilegesRequired=lowest pins Setup to non administrative install mode, so
  Inno's own UsePreviousAppDir lookup only ever consults HKCU. A copy that
  ended up machine-wide has to be found whichever mode registered it. }
function PreviousInstallDir: String;
var
  Dir: String;
begin
  Result := '';
  if RegQueryStringValue(HKCU, UninstallSubkey, 'Inno Setup: App Path', Dir) then
    Result := Dir
  else if RegQueryStringValue(HKLM, UninstallSubkey, 'Inno Setup: App Path', Dir) then
    Result := Dir;
end;

{ Whether this process could replace files in Path. Setup is manifested, so UAC
  file virtualization is off and a refused write really is refused. }
function PathIsWritable(const Path: String): Boolean;
var
  Dir, Probe: String;
begin
  Dir := RemoveBackslashUnlessRoot(Path);
  if not DirExists(Dir) then
    Dir := ExtractFileDir(Dir);
  if (Dir = '') or not DirExists(Dir) then begin
    { Nothing to overwrite; let Setup report any genuine failure itself. }
    Result := True;
    Exit;
  end;

  Probe := AddBackslash(Dir) + WriteProbeName;
  Result := SaveStringToFile(Probe, '', False);
  if Result then
    DeleteFile(Probe);
end;

function QuoteIfNeeded(const S: String): String;
begin
  if Pos(' ', S) > 0 then
    Result := '"' + S + '"'
  else
    Result := S;
end;

{ The documented parameters this instance was started with, minus the install
  mode and directory overrides the elevated instance is given explicitly. }
function ForwardedParams: String;
var
  I: Integer;
  P: String;
begin
  Result := '';
  for I := 1 to ParamCount do begin
    P := ParamStr(I);
    if (P <> '') and
       (CompareText(P, '/ALLUSERS') <> 0) and
       (CompareText(P, '/CURRENTUSER') <> 0) and
       (CompareText(Copy(P, 1, 5), '/DIR=') <> 0) then
      Result := Result + QuoteIfNeeded(P) + ' ';
  end;
end;

{ An installation living somewhere this user cannot write - typically
  C:\Program Files, inherited from an elevated run of an earlier installer -
  can only be updated in administrative install mode. Setup settles the install
  mode before any [Code] runs, so hand the work to a new elevated instance and
  pin it to the directory already in use. Without this the silent installer
  launched by the in-app updater fails to overwrite anything. }
function InitializeSetup: Boolean;
var
  PreviousDir, Params: String;
  ErrorCode: Integer;
begin
  Result := True;
  if IsAdminInstallMode or (ExpandConstant('{param:ELEVATED|0}') = '1') then
    Exit;

  PreviousDir := PreviousInstallDir;
  if (PreviousDir = '') or PathIsWritable(PreviousDir) then
    Exit;

  Params := ForwardedParams + '/ALLUSERS /ELEVATED=1 /DIR=' +
    QuoteIfNeeded(RemoveBackslashUnlessRoot(PreviousDir));

  { Either the elevated instance takes over, or elevation was refused and there
    is nothing this instance can usefully do. }
  Result := False;
  if ShellExec('runas', ExpandConstant('{srcexe}'), Params, '', SW_SHOW, ewNoWait, ErrorCode) then
    Exit;

  SuppressibleMsgBox(FmtMessage(CustomMessage('ElevationRequired'), [PreviousDir]),
    mbCriticalError, MB_OK, IDOK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  MarkerPath, PreviousDir, PreviousGroup: String;
begin
  if CurStep = ssPostInstall then
  begin
    MarkerPath := ExpandConstant('{app}\.winget');
    if ExpandConstant('{param:WINGET|0}') = '1' then
      SaveStringToFile(MarkerPath, '', False)
    else
      DeleteFile(MarkerPath);

    { A machine-wide install that took over a directory registered per-user
      leaves that user's uninstall entry and Start Menu group pointing at files
      this install now owns, listing Plezy twice in Apps & Features. }
    if IsAdminInstallMode then
    begin
      if RegQueryStringValue(HKCU, UninstallSubkey, 'Inno Setup: App Path', PreviousDir) and
         (CompareText(RemoveBackslashUnlessRoot(PreviousDir),
                      RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) = 0) then
      begin
        if not RegQueryStringValue(HKCU, UninstallSubkey, 'Inno Setup: Icon Group', PreviousGroup) then
          PreviousGroup := '';
        RegDeleteKeyIncludingSubkeys(HKCU, UninstallSubkey);
        if PreviousGroup <> '' then
          DelTree(ExpandConstant('{userprograms}') + '\' + PreviousGroup, True, True, True);
      end;
    end;
  end;
end;
