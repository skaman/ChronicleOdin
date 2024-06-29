@echo off

if not exist "%cd%\bin" mkdir "%cd%\bin"
call build-assets.bat
odin run . -debug -out:bin/chronicle_debug.exe