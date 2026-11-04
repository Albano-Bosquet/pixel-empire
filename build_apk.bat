@echo off
rem Builds build\PixelEmpire.apk (Android, arm64, debug-signed) with the same
rem game data as the PC build, so both can play together online.
rem Needs: Godot export templates 4.7.2, JDK 17 and the Android SDK set in
rem Godot (Editor Settings > Export > Android) and a debug keystore.
rem Install on a phone with USB debugging:  adb install -r build\PixelEmpire.apk
cd /d "%~dp0"
set "G=tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%G%" (
    echo ERROR: No se encuentra Godot en tools\godot.
    pause
    exit /b 1
)
if not exist build mkdir build
"%G%" --headless --path "." --import
"%G%" --headless --path "." --export-debug "Android" build/PixelEmpire.apk || exit /b 1
echo.
echo Listo: build\PixelEmpire.apk
pause
