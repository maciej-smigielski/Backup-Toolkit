@echo off

REM -------------------------------
REM NAME: BT-Mail-Send.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.11.01.2
REM -------------------------------

call powershell -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
exit /b %ERRORLEVEL%
