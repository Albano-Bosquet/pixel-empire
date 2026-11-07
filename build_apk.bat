@echo off
rem Builds build\PixelEmpire.apk (Android, arm64, release template) with the same
rem game data as the PC build, so both can play together online.
rem Needs: Godot export templates 4.7.2, JDK 17 and the Android SDK set in
rem Godot (Editor Settings > Export > Android) and a debug keystore.
rem It is signed with the debug keystore on purpose: phones only upgrade over an
rem APK signed with the same key. The release template runs GDScript faster.
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
set "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%APPDATA%\Godot\keystores\debug.keystore"
set "GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey"
for /f tokens^=2^ delims^=^" %%p in ('findstr /c:"debug_keystore_pass" "%APPDATA%\Godot\editor_settings-4.7.tres"') do set "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=%%p"
"%G%" --headless --path "." --export-release "Android" build/PixelEmpire.apk || exit /b 1
echo.
echo Listo: build\PixelEmpire.apk
pause
