@echo off
cd "%~dp0.."
cmd /c Tools\BT-Plan.cmd examples\BTRepository/BackupPlans/plan-example.BT-Plan %*
echo BT-Plan ERRORLEVEL: %ERRORLEVEL%
pause