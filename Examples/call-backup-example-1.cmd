@echo off
cd "%~dp0.."
cmd /c Tools\BT-Backup.cmd examples\BTRepository\backupdata\backup-example-1\backup-example-1.bt-backup %*
echo BT-Backup ERRORLEVEL: %ERRORLEVEL%
pause