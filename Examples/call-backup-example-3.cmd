@echo off
cd "%~dp0.."
cmd /c Tools\BT-Backup.cmd examples\BTRepository\backupdata\backup-example-3\backup-example-3.bt-backup %*
echo BT-Backup ERRORLEVEL: %ERRORLEVEL%
pause