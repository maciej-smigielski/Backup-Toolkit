@echo off

REM -------------------------------
REM NAME: BT-Mail-Credentials.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.11.01.1
REM -------------------------------

call powershell -WindowStyle Minimized -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
exit /b %ERRORLEVEL%
