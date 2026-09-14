; Instalador de Windows de la app MODO YA (clientes, locales y administracion).
;
; Antes: compilar la version release y copiar el runtime de Visual C++ al lado
; del .exe (lo hace installer\armar_windows.ps1, que despues llama a este script).
;
; Instala por usuario (sin pedir administrador) en %LOCALAPPDATA%\Programs.

#define Nombre "MODO YA"
#define Version "1.0.0"
#define Exe "modo_ya.exe"
#define Origen "..\apps\modo_ya\build\windows\x64\runner\Release"

[Setup]
AppId={{6B0C2F4E-3E0B-4B7A-9C2D-4D6F0A1B8E21}
AppName={#Nombre}
AppVersion={#Version}
AppPublisher={#Nombre}
DefaultDirName={localappdata}\Programs\{#Nombre}
DefaultGroupName={#Nombre}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\instaladores
OutputBaseFilename=MODO_YA_Setup_{#Version}
SetupIconFile=..\apps\modo_ya\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Exe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#Origen}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Nombre}"; Filename: "{app}\{#Exe}"
Name: "{userdesktop}\{#Nombre}"; Filename: "{app}\{#Exe}"; Tasks: escritorio

[Run]
Filename: "{app}\{#Exe}"; Description: "Abrir {#Nombre}"; Flags: nowait postinstall skipifsilent
