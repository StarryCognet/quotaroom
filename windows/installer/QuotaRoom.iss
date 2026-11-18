; QuotaRoom Windows installer (Inno Setup 6+).
; Build with:
;   ISCC.exe /DMyAppVersion=2.2.1 /DSourceDir=<Release dir> /DOutputDir=<dist dir> QuotaRoom.iss
; The version and paths are supplied by tool/package_windows.ps1.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define MyAppName "QuotaRoom"
#define MyAppPublisher "StarryCognet"
#define MyAppURL "https://github.com/StarryCognet/quotaroom"
#define MyAppExeName "QuotaRoom.exe"

[Setup]
AppId={{9D6C2F7A-3B5E-4C1D-8F2A-7E6B5C4D3A21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
AppCopyright=Copyright (C) 2026 StarryCognet
DefaultDirName={autopf}\QuotaRoom
DefaultGroupName=QuotaRoom
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
OutputDir={#OutputDir}
OutputBaseFilename=QuotaRoom-v{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
LicenseFile=..\..\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=QuotaRoom desktop installer
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes
UsePreviousAppDir=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
chinesesimp.StartWithWindows=开机时启动 QuotaRoom
english.StartWithWindows=Start QuotaRoom with Windows
chinesesimp.UninstallShortcut=卸载 QuotaRoom
english.UninstallShortcut=Uninstall QuotaRoom

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallShortcut}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--hidden"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
