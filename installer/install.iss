; RustDesk Zero-Touch — Inno Setup 6
#define MyAppName    "RustDesk Zero-Touch"
#define MyAppVersion "1.0.0"

#ifndef flavor
  #define flavor "public"
#endif
#ifndef rdVersion
  #define rdVersion "0"
#endif
#ifndef permanentPassword
  #define permanentPassword "ChangeMe-Now-1234"
#endif
#ifndef rsServer
  #define rsServer ""
#endif
#ifndef rsKey
  #define rsKey ""
#endif
#ifndef meshDomain
  #define meshDomain ""
#endif
#ifndef meshId
  #define meshId ""
#endif
#ifndef ntfyTopic
  #define ntfyTopic ""
#endif
#ifndef tgToken
  #define tgToken ""
#endif
#ifndef tgChat
  #define tgChat ""
#endif

[Setup]
AppId={{9C4B2A11-7E3D-4F6A-9B21-5D8E0C7A3F44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=RustDesk Zero-Touch
DefaultDirName={autopf}\RustDeskZeroTouch
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=out
OutputBaseFilename=RustDesk-ZeroTouch-{#flavor}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=no
RestartApplications=no
MinVersion=10.0.17763
UninstallDisplayName={#MyAppName}

[Languages]
Name: "uk"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "payload\RustDesk.exe";           DestDir: "{app}";        Flags: ignoreversion
Source: "postinstall.ps1";               DestDir: "{app}";        Flags: ignoreversion
Source: "watchdog.ps1";                  DestDir: "{app}";        Flags: ignoreversion
Source: "..\config\RustDesk2.toml.tmpl"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\config\RustDesk.toml.tmpl";  DestDir: "{app}\config"; Flags: ignoreversion

[INI]
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "flavor";    String: "{#flavor}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "password";  String: "{#permanentPassword}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "server";    String: "{#rsServer}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "key";       String: "{#rsKey}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "meshdomain";String: "{#meshDomain}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "meshid";    String: "{#meshId}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "ntfytopic"; String: "{#ntfyTopic}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "tgtoken";   String: "{#tgToken}"
Filename: "{tmp}\rz-setup.ini"; Section: "params"; Key: "tgchat";    String: "{#tgChat}"

[Run]
Filename: "{app}\RustDesk.exe"; Parameters: "--silent-install"; \
  StatusMsg: "RustDesk..."; Flags: runhidden waituntilterminated
Filename: "{app}\RustDesk.exe"; Parameters: "--install-service"; \
  StatusMsg: "Service..."; Flags: runhidden waituntilterminated
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\postinstall.ps1"" -Ini ""{tmp}\rz-setup.ini"""; \
  StatusMsg: "Config..."; Flags: runhidden waituntilterminated
Filename: "{app}\RustDesk.exe"; Parameters: "--password ""{#permanentPassword}"""; \
  Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "{app}\RustDesk.exe"; Parameters: "--uninstall-service"; Flags: runhidden; RunOnceId: "rdsvc"
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""RustDeskZeroTouchWatchdog"" /F"; Flags: runhidden; RunOnceId: "rdwd"
