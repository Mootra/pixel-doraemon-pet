@echo off
start "Pixel Doraemon Companion" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0plugins\pixel-doraemon-companion\scripts\start-companion.ps1"
exit /b 0
