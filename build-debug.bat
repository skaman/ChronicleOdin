@echo off

if not exist "%cd%\bin" mkdir "%cd%\bin"
call build-assets.bat
odin build . -debug -out:bin/chronicle_debug.exe
IF %ERRORLEVEL% NEQ 0 (echo Error: %ERRORLEVEL% && exit)