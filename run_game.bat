
@echo off
title Pixel Empire Launcher

cd /d "%~dp0"

set "GODOT=%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
    echo ERROR: No se encuentra Godot.
    pause
    exit /b 1
)

if not exist "%~dp0project.godot" (
    echo ERROR: No se encuentra project.godot.
    pause
    exit /b 1
)

echo Iniciando Pixel Empire...
echo.

rem --path "." (the script already cd-ed here): "%~dp0" ends in a backslash that would
rem escape the closing quote. Game options go after "--", e.g. run_game.bat --mode=skirmish
"%GODOT%" --path "." -- %*

echo.
echo Godot finalizo.
pause
