@echo off
rem Scenario Installer launcher (fallback for ScenarioInstaller.exe)
rem Keep this file next to Install-Scenario.ps1
cd /d "%~dp0"
if not exist "%~dp0Install-Scenario.ps1" (
  echo Install-Scenario.ps1 was not found next to this .bat file.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-Scenario.ps1" %*
if errorlevel 1 pause
