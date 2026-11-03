@echo off
rem Builds build\PixelEmpire.exe: the game packed in PixelEmpire.pck next to the
rem Godot runtime, which loads a .pck with its own name automatically.
cd /d "%~dp0"
set "G=tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%G%" (
    echo ERROR: No se encuentra Godot en tools\godot.
    pause
    exit /b 1
)
if not exist build mkdir build
"%G%" --headless --path "." --import
"%G%" --headless --path "." --export-pack "Windows Desktop" build/PixelEmpire.pck || exit /b 1
copy /y "tools\godot\Godot_v4.7.2-stable_win64.exe" "build\PixelEmpire.exe" >nul
copy /y "tools\godot\Godot_v4.7.2-stable_win64_console.exe" "build\PixelEmpire_console.exe" >nul
echo.
echo Listo: build\PixelEmpire.exe (necesita PixelEmpire.pck en la misma carpeta)
pause
