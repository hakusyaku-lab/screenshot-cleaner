@echo off
chcp 65001 >nul
echo スクショ整理をインストールします...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ScreenshotCleaner.ps1" -Install
echo.
pause
