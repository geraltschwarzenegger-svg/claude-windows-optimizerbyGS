@echo off
setlocal EnableExtensions
title EXOVANCE Device Tweaker v2
set "SCRIPT=%~dp0Exovance-DeviceTweaker-v2.ps1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%SCRIPT%" exit /b 5
if /i "%~1"=="/check" goto Check
"%PS%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXOVANCE_EXIT=%ERRORLEVEL%"
if not "%EXOVANCE_EXIT%"=="0" pause
exit /b %EXOVANCE_EXIT%
:Check
"%PS%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%" -Check
exit /b %ERRORLEVEL%
