@echo off

call build-debug.bat
pushd bin
chronicle_debug.exe
popd
