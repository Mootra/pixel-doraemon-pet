@echo off
start "Pixel Doraemon Companion V2" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0plugins\pixel-doraemon-companion\scripts\start-companion.ps1" -Profile v2
exit /b 0
