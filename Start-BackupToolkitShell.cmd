@echo off

REM -------------------------------
REM NAME: Start-BackupToolkitShell.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.10.28.0
REM -------------------------------

setlocal
cd /d "%~dp0"
set "PATH=%~dp0Tools;%~dp0Tools\Utilities\Rclone;%PATH%"
echo Backup-Toolkit command shell
echo Home directory: %CD%
echo Added to PATH for this shell: Tools, Tools\Utilities\Rclone
echo.
cmd /k