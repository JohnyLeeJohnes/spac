@echo off
rem Spusti Space bez instalace. Zastupce s ikonou vytvori install.cmd.
start "" conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Spac.ps1"
