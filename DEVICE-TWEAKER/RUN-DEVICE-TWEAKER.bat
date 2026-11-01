@echo off
setlocal EnableExtensions
set "SCRIPT=%~dp0DEVICE-TWEAKER-UPDATE-2026-LLG-X-LLC-UPDATED.ps1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%SCRIPT%" (
  echo [ERROR] PowerShell script not found:
  echo         "%SCRIPT%"
  pause
  exit /b 5
)
fsutil dirty query %SystemDrive% >nul 2>&1
if not errorlevel 1 goto :RunScript
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA 2^>nul') do set "LUA=%%A"
if not defined LUA set "LUA=0x1"
if /i "%LUA%"=="0x0" goto :ElevationImpossible
if "%LUA%"=="0" goto :ElevationImpossible
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -Verb RunAs -ArgumentList '/c ""%~f0""' -WindowStyle Hidden" >nul 2>&1
exit /b 0

:ElevationImpossible
echo [ERROR] Admin rights required but UAC is disabled (EnableLUA=0).
echo         Run this .bat from an administrator account.
pause
exit /b 1

:RunScript
start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b 0
