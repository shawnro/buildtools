@if "%_echo%" neq "on" echo off
setlocal

:Run
powershell -NoProfile -ExecutionPolicy unrestricted -Command "%~dpn0.ps1 -- %*"
exit /b %ERRORLEVEL%