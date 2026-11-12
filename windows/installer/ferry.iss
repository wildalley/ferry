; Compile through scripts/package-windows.ps1, which supplies these values.
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppBuild
  #error AppBuild is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
; Keep this ID stable so future installers upgrade the same installation.
AppId=com.wildalley.ferry
AppName=渡 Ferry
AppVersion={#AppVersion}
AppPublisher=WildAlley
AppPublisherURL=https://github.com/wildalley/ferry
AppSupportURL=https://github.com/wildalley/ferry/issues
AppUpdatesURL=https://github.com/wildalley/ferry/releases
VersionInfoVersion={#AppVersion}.{#AppBuild}
DefaultDirName={localappdata}\Programs\Ferry
DefaultGroupName=渡 Ferry
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Match the runner's single-instance mutex, including its legacy name.
AppMutex=Local\WildAlley.SingBoxClient
CloseApplications=no
RestartApplications=no
UninstallDisplayIcon={app}\ferry.exe
SetupIconFile=..\runner\resources\app_icon.ico
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=ferry-windows-x64-{#AppVersion}-{#AppBuild}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; App-local VC++ runtime DLLs are staged alongside Flutter and the core.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\渡 Ferry"; Filename: "{app}\ferry.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\渡 Ferry"; Filename: "{app}\ferry.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\ferry.exe"; Description: "{cm:LaunchProgram,渡 Ferry}"; Flags: nowait postinstall skipifsilent

; No UninstallDelete entries: settings, credentials and user-created files
; must survive uninstall. Inno removes only files it installed.
