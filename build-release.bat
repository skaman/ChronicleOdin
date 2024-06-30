@echo off

if not exist "%cd%\bin" mkdir "%cd%\bin"
call build-assets.bat
odin build . -out:bin/chronicle_release.exe -o:aggressive