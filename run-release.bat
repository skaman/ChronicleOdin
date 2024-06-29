@echo off

if not exist "%cd%\bin" mkdir "%cd%\bin"
call build-assets.bat
odin run . -out:bin/chronicle_release.exe -o:aggressive