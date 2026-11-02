@echo off

REM -------------------------------
REM NAME: BT-Rclone-Config.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.11.02.0
REM -------------------------------

call powershell -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
exit /b %ERRORLEVEL%
