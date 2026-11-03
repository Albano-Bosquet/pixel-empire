@echo off
rem Builds build\installer\PixelEmpire_Setup_<version>.exe:
rem icon -> game pack + runtime (build_exe) -> Inno Setup.
cd /d "%~dp0"
set "G=tools\godot\Godot_v4.7.2-stable_win64_console.exe"
set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
    echo ERROR: No se encuentra Inno Setup 6. Instalalo con: winget install JRSoftware.InnoSetup
    pause
    exit /b 1
)
if not exist build mkdir build
"%G%" --headless --path "." --import
"%G%" --headless --path "." -s res://tools/art/make_icon.gd || exit /b 1
python installer\make_ico.py || exit /b 1
"%G%" --headless --path "." --export-pack "Windows Desktop" build/PixelEmpire.pck || exit /b 1
copy /y "tools\godot\Godot_v4.7.2-stable_win64.exe" "build\PixelEmpire.exe" >nul
"%ISCC%" installer\pixel_empire.iss || exit /b 1
echo.
echo Listo: instalador en build\installer
