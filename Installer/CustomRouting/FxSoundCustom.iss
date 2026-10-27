; Custom routing build, packaged separately from the official FxSound installation.
; Compile through Build-Installer.ps1 so all payloads are validated first.
#ifndef PayloadDir
  #error PayloadDir must identify the validated staging directory
#endif

[Setup]
AppId={{B3304B94-69CF-4FE4-835A-1B7ED3484EF9}
AppName=FxSound Custom
AppVersion=1.2.15-routing.1
AppPublisher=FxSound community custom build
AppPublisherURL=https://github.com/christianfurr/fxsound-app
AppSupportURL=https://github.com/fxsound2/fxsound-app/pull/665
AppUpdatesURL=https://github.com/christianfurr/fxsound-app/tree/feat/custom-routing-installer
DefaultDirName={autopf}\FxSound Custom
DefaultGroupName=FxSound Custom
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
PrivilegesRequired=admin
UninstallDisplayName=FxSound Custom (audio routing)
UninstallDisplayIcon={app}\FxSound.exe
OutputBaseFilename=FxSoundCustomSetup
VersionInfoVersion=1.2.15.1
LicenseFile={#PayloadDir}\LICENSE.txt
InfoBeforeFile={#PayloadDir}\INSTALL-NOTES.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\app\FxSound.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\app\Factsoft\*.fac"; DestDir: "{app}\Factsoft"; Flags: ignoreversion
Source: "{#PayloadDir}\app\*.ttf"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#PayloadDir}\app\*.otf"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#PayloadDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\SOURCE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\INSTALL-NOTES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\fxsound-official-1.2.16.exe"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\FxSound Custom"; Filename: "{app}\FxSound.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\FxSound Custom"; Filename: "{app}\FxSound.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\FxSound.exe"; WorkingDir: "{app}"; Description: "Launch FxSound Custom"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
const
  OfficialInstallerHash = '3e4c6aead03e1dd9f093de4ff9842b8d7ed9487f8b033a87c3ab83e5f65ca710';

function DriverInstalled: Boolean;
begin
  Result := RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\FXVAD');
end;

function FxSoundRunning(var Running: Boolean): Boolean;
var
  Locator, Services, Processes: Variant;
begin
  Result := False;
  Running := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('', 'root\CIMV2');
    Processes := Services.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''FxSound.exe''');
    Running := Processes.Count > 0;
    Result := True;
  except
    Log('Unable to inspect running FxSound processes: ' + GetExceptionMessage);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Running: Boolean;
  OfficialInstaller: String;
  ExitCode: Integer;
begin
  Result := '';
  if not FxSoundRunning(Running) then
  begin
    Result := 'Windows could not inspect running applications. Close FxSound and try again.';
    Exit;
  end;
  if Running then
  begin
    Result := 'Exit FxSound from its icon near the Windows clock, then click Retry.';
    Exit;
  end;

  if not DriverInstalled then
  begin
    if WizardSilent then
    begin
      Result := 'The official FxSound driver is required. Run this installer interactively to install it.';
      Exit;
    end;
    ExtractTemporaryFile('fxsound-official-1.2.16.exe');
    OfficialInstaller := ExpandConstant('{tmp}\fxsound-official-1.2.16.exe');
    if CompareText(GetSHA256OfFile(OfficialInstaller), OfficialInstallerHash) <> 0 then
    begin
      Result := 'The bundled official installer failed its integrity check.';
      Exit;
    end;
    if not Exec(OfficialInstaller, '', ExpandConstant('{tmp}'), SW_SHOWNORMAL, ewWaitUntilTerminated, ExitCode) then
    begin
      Result := 'The official FxSound installer could not be started.';
      Exit;
    end;
    if (ExitCode = 3010) or (ExitCode = 1641) then
    begin
      NeedsRestart := True;
      Result := 'The FxSound driver installation requires a restart. Restart Windows and run this setup again.';
      Exit;
    end;
    if ExitCode <> 0 then
    begin
      Result := 'The official FxSound installer returned error ' + IntToStr(ExitCode) + '. Complete that installation and try again.';
      Exit;
    end;
    if not DriverInstalled then
    begin
      Result := 'The FxSound driver was not detected. Complete the official installation, then click Retry.';
      Exit;
    end;
    if not FxSoundRunning(Running) then
    begin
      Result := 'The driver is installed, but Windows could not inspect running applications. Close FxSound and try again.';
      Exit;
    end;
    if Running then
      Result := 'The driver is installed. Exit the official FxSound app from its tray icon, then click Retry to install FxSound Custom.';
  end;
end;

function InitializeUninstall: Boolean;
var
  Running: Boolean;
begin
  Result := FxSoundRunning(Running);
  if Result then
    Result := not Running;
  if not Result then
    MsgBox('Exit FxSound from its tray icon before uninstalling FxSound Custom.', mbInformation, MB_OK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  StartupValue, CustomExecutable: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  CustomExecutable := ExpandConstant('{app}\FxSound.exe');
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'FxSound', StartupValue) then
    if (CompareText(StartupValue, CustomExecutable) = 0) or
       (CompareText(StartupValue, '"' + CustomExecutable + '"') = 0) then
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'FxSound');
  { The official application, signed driver, and shared user presets remain installed. }
end;
