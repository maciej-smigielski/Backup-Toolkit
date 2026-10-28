@echo off

REM -------------------------------
REM NAME: Start-ExamplesShell.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.10.28.0
REM -------------------------------

setlocal
cd /d "%~dp0.."
set "PATH=%CD%\Tools;%CD%\Tools\Utilities\Rclone;%PATH%"
echo Backup-Toolkit command shell for examples
echo Home directory: %CD%
echo Added to PATH for this shell: Tools, Tools\Utilities\Rclone
echo.
echo Warning: All configuration files in Examples use paths relative to Backup-Toolkit home.
echo.
echo Run backup examples 1-4:
echo   Examples\call-backup-example-1.cmd
echo   Examples\call-backup-example-2.cmd
echo   Examples\call-backup-example-3.cmd
echo   Examples\call-backup-example-4.cmd
echo   Examples\call-backup-example-1.cmd -ValidateOnly
echo Optional flags for any backup example: -ValidateOnly, -DryRun, -NoMail, -NoPause, -Debug
echo.
echo Run backup plan example:
echo   Examples\call-plan-example.cmd
echo   Examples\call-plan-example.cmd -ValidateOnly
echo   Examples\call-plan-example.cmd -ValidateJobs
echo Optional flags for the plan example: -RunAll, -RunJob, -ValidateOnly, -ValidateJobs, -DryRun, -NoMail, -NoPause, -Debug
echo.
echo Run shutdown example:
echo   Examples\call-shutdown-example.cmd
echo.
echo Configure the example rclone remote:
echo   Tools\BT-Rclone-Config.cmd Examples\BTRepository\Config\example-rclone.BT-Rclone-Config
echo.
echo Read the examples guide: Examples\README.md
echo.

cmd /k
