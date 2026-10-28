@echo off
cd "%~dp0.."
cmd /c Tools\BT-Backup.cmd examples\BTRepository\backupdata\backup-example-2\backup-example-2.bt-backup %*
echo BT-Backup ERRORLEVEL: %ERRORLEVEL%
pause