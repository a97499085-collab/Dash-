@echo off
rem  A small wrapper so that the compiler machine can be reached as
rem  'dash build program.dh' from any folder.
setlocal
set DCM=%~dp0bin\dcm_main.exe
if not exist "%DCM%" (
    echo dash: the DCM is not built yet. Run: gprbuild -P dash.gpr
    exit /b 1
)
"%DCM%" %*
endlocal
