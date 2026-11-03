@echo off
rem Multiplayer smoke test on this PC: a host, a client that plays and leaves,
rem then the same client rejoining. Opens game windows; each prints PASS/FAIL.
set G="%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
start "PixelEmpire host" /b %G% --path "%~dp0." -- --mp=host --smoke=mp
timeout /t 3 /nobreak >nul
%G% --path "%~dp0." -- --mp=client --smoke=mp || exit /b 1
timeout /t 4 /nobreak >nul
%G% --path "%~dp0." -- --mp=rejoin --smoke=mp || exit /b 1
echo MULTIPLAYER CHECKS PASSED (see the host window output for its own result)
