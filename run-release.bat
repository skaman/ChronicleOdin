@echo off

call build-release.bat
pushd bin
chronicle_release.exe
popd
