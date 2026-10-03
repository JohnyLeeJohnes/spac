@echo off
rem Vytvori zastupce "Spac" s ikonou v nabidce Start a na plose.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Spac.ps1" -Install
pause
