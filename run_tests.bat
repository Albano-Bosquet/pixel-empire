@echo off
rem Full verification: compile check, unit tests, in-game smoke tests (opens a window).
set G="%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe"
%G% --headless --path "%~dp0." --import
%G% --headless --path "%~dp0." -s res://tests/check_scripts.gd || exit /b 1
%G% --headless --path "%~dp0." -s res://tests/run_tests.gd || exit /b 1
%G% --path "%~dp0." -- --smoke --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=combat --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=ai --mode=skirmish --difficulty=hard --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=lang --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=audio --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=features --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=work --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=occlusion --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=display --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=cancel --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=ghost --mode=skirmish --map=coast --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=touch --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=layout --mode=skirmish --seed=4242 || exit /b 1
%G% --path "%~dp0." -- --smoke=terrain --mode=skirmish --map=continental --seed=4242 --nofog || exit /b 1
%G% --path "%~dp0." -- --smoke=terrain --mode=skirmish --map=coast --seed=4242 --nofog || exit /b 1
%G% --path "%~dp0." -- --smoke=terrain --mode=skirmish --map=desert --seed=4242 --nofog || exit /b 1
echo ALL CHECKS PASSED
