@echo off

REM -------------------------------
REM NAME: BT-Plan-Schedule-example.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.10.28.0
REM -------------------------------

rem ===== BEGIN: User-customizable settings =====
rem For customization, copy this script to the BackupRepository/Admin directory.
rem You can rename the copied script.

rem Required: name of the scheduled task.
rem You can change it in the script before managing or creating the task.
set "TaskName=BT-Plan"

rem Required: path to the Backup-Toolkit installation directory
rem It cannot be changed while the script is running.
rem BTPath is the BackupToolkitHome path.
rem WARNING: BTPath must not end with a backslash
rem NOTE: Customized launcher for testing; uses relative paths.
set "BTPath=%~dp0..\..\..\.."

rem Scheduled task settings
rem Optional: description of the scheduled task.
rem You can change it in the script before creating the task.
set "Description=Backup-Toolkit daily planned backups"

rem Required: start time for the scheduled task.
rem You can change it in the script before creating the task.
rem If left empty, the script checks it before creating the task.
set "StartTime=0:20"

rem Required: path to the BT-Plan configuration file used by the scheduled task.
rem You can change it in the script before creating the task.
rem If left empty, the script checks it before creating the task.
rem NOTE: Customized config path for testing; uses a relative path.
set "ConfigFilePath=Examples/BTRepository/BackupPlans/plan-example.BT-Plan"

rem ===== END: User-customizable settings =====

rem Change to the Backup-Toolkit home directory
cd "%BTPath%"
echo Home directory: %CD%
echo.

rem The PowerShell command below is a standard part of the script.
rem Do not modify it when customizing the settings above.
call powershell -ExecutionPolicy Bypass -File "%BTPath%\tools\admin\BT-Plan-Schedule.ps1" ^
	-TaskName "%TaskName%" ^
	-Description "%Description%" ^
	-StartTime "%StartTime%" ^
	-ConfigFilePath "%ConfigFilePath%" ^
	-BTPath "%BTPath%" %*
exit /b %ERRORLEVEL%
