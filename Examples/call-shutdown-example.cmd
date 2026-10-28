@echo off
cd "%~dp0.."
tools\BT-Shutdown.cmd Examples\BTRepository\BackupSystem\BT-Shutdown.example.ini
echo BT-Plan ERRORLEVEL: %ERRORLEVEL%
pause