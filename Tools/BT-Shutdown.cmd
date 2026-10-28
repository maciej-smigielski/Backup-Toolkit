@echo off
setlocal enabledelayedexpansion

REM -------------------------------
REM NAME: BT-Shutdown.cmd
REM AUTHOR: Maciej-Smigielski
REM VERSION: 26.10.28.0
REM -------------------------------

:: Check if parameters were provided
if "%~1"=="" (
    echo Usage: %~nx0 [ini_file]
    exit /b 1
)
set iniFile=%~1
:: echo iniFile: !iniFile!

:: Check if ini file exists
if not exist "%iniFile%" (
    echo File not exists: !iniFile!
    exit /b 1
)

:: Save current console codepage and switch to UTF-8 (iniFile is UTF-8)
for /f "tokens=2 delims=:" %%a in ('chcp') do set "old_cp=%%a"
set "old_cp=!old_cp: =!"
chcp 65001 >nul

set "section=Settings"

:: Check parameter logpath
set "key=logpath"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key!
    exit /b 1
)
set logpath=!value!
:: echo !key!: !logpath!

:: Get current datetime in format yyyymmddHHMMSS
for /f %%i in ('powershell -Command "(Get-Date).ToString(\"yyyyMMddHHmmss\")"') do set now=%%i
set yyyy=%now:~0,4%
set mm=%now:~4,2%
set dd=%now:~6,2%
set hh=%now:~8,2%
set min=%now:~10,2%
set ss=%now:~12,2%
set hour=%now:~8,2%
set nowDate=%now:~0,8%
set nowTime=%now:~8,6%

:: Create log file name
set logname=BT-Shutdown_%yyyy%-%mm%-%dd%_%hh%-%min%-%ss%.log
set fullpath=%logpath%%logname%

:: Check log dir
if not exist "%logpath%" (
    echo Log dir not exists: !logpath!
    exit /b 1
)

echo Execute: %~nx0 %iniFile% >> "%fullpath%"
echo iniFile: %iniFile% >> "%fullpath%"
echo logName: %logname% >> "%fullpath%"

:: Check parameter threshold_min
set "key=threshold_min"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key! >> "%fullpath%"
    goto end
)
set threshold_min=!value!
echo !key!: "!threshold_min!" >> "%fullpath%"

:: Check parameter start_hour
set "key=start_hour"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key! >> "%fullpath%"
    goto end
)
set start_hour=!value!
echo !key!: "!start_hour!" >> "%fullpath%"

:: Check parameter end_hour
set "key=end_hour"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key! >> "%fullpath%"
    goto end
)
set end_hour=!value!
echo !key!: "!end_hour!" >> "%fullpath%"

:: Check parameter shutdown_allow
set "key=shutdown_allow"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key! >> "%fullpath%"
    goto end
)
set shutdown_allow=!value!
echo !key!: "!shutdown_allow!" >> "%fullpath%"

:: Check parameter shutdown_delay
set "key=shutdown_delay"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
if "%value%"=="" (
    echo Empty parameter: !key! >> "%fullpath%"
    goto end
)
set shutdown_delay=!value!
echo !key!: "!shutdown_delay!" >> "%fullpath%"

:: Check parameter flag_path
set "key=flag_path"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
set flag_path=!value!
echo !key!: "!flag_path!" >> "%fullpath%"

:: Check parameter mail_to
set "key=mail_to"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
set mail_to=!value!
echo !key!: "!mail_to!" >> "%fullpath%"

:: Check parameter mail_credentials
set "key=mail_credentials"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
set mail_credentials=!value!
echo !key!: "!mail_credentials!" >> "%fullpath%"

:: Check parameter mail_prog
set "key=mail_prog"
set "value="
for /f "tokens=1,* delims==" %%A in ('findstr /i "%key%=" "%iniFile%" ^| findstr /v /b /c:"#"') do (
    set "value=%%B"
)
set mail_prog=!value!
echo !key!: "!mail_prog!" >> "%fullpath%"

:: Get last boot time
for /f %%i in ('powershell -Command "((Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString(\"yyyyMMddHHmmss\")"') do set boot=%%i
set bootDate=!boot:~0,8!
set bootTime=!boot:~8,6!

echo nowDate: %nowDate% %nowTime% >> "%fullpath%"
echo bootDate: %bootDate% %bootTime% >> "%fullpath%"

:: Convert both times to total minutes since midnight (approximation)
set "nowhh=%nowTime:~0,2%"
set "nowmm=%nowTime:~2,2%"
set /a nowhhnum=1%nowhh% - 100
set /a nowmmnum=1%nowmm% - 100
set /a nowTotalMin=nowhhnum*60 + nowmmnum
rem set /a nowTotalMin=1*!now:~8,2!*60 + 1*!now:~10,2!
set "boothh=%bootTime:~0,2%"
set "bootmm=%bootTime:~2,2%"
set /a boothhnum=1%boothh% - 100
set /a bootmmnum=1%bootmm% - 100
set /a bootTotalMin=boothhnum*60 + bootmmnum
rem set /a bootTotalMin=1*!boot:~8,2!*60 + 1*!boot:~10,2!

:: Calculate difference in minutes (same-day only)
set /a diffMin=!nowTotalMin! - !bootTotalMin!

:: If date changed (system booted yesterday), add 1440 minutes
if not "!nowDate!"=="!bootDate!" set /a diffMin+=1440

:: Compare with threshold_min
if !diffMin! GEQ !threshold_min! (
    echo Threshold check PASSED: current uptime: !diffMin! minutes required !threshold_min! >> "%fullpath%"
    set Threshold_passed=true
) else (
    echo Threshold check NOT-PASSED: current uptime: !diffMin! minutes required !threshold_min! >> "%fullpath%"
    set Threshold_passed=false
)

:: Remove leading zero
if "!hour:~0,1!"=="0" set hour=!hour:~1!

:: Handle overnight range (e.g. 22-2)
set execute=false
if %start_hour% LEQ %end_hour% (
    :: Range within same day (e.g. 10–18)
    if !hour! GEQ %start_hour% if !hour! LSS %end_hour% set execute=true
) else (
    :: Range spans midnight (e.g. 22–2)
    if !hour! GEQ %start_hour% set execute=true
    if !hour! LSS %end_hour% set execute=true
)

:: Compare allowed time range
if "!execute!"=="true" (
    echo Allowed time check PASSED: inside allowed time range, current hour: !hour! range %start_hour%-%end_hour% >> "%fullpath%"
    set Allowed_time_passed=true
) else (
    echo Allowed time check NOT-PASSED: outside allowed time range, current hour: !hour! range %start_hour%-%end_hour% >> "%fullpath%"
    set Allowed_time_passed=false
)

:: Get users
set count_users=0
echo Logged users list: >> "%fullpath%"
for /f "skip=1 tokens=*" %%A in ('quser 2^>nul') do (
    echo %%A >> "%fullpath%"
    set /a count_users+=1
)
echo Logged users count: !count_users! >> "%fullpath%"

:: Check users
if "!count_users!"=="0" (
    echo Users check PASSED: no logged users>> "%fullpath%"
    set Users_passed=true
) else (
    echo Users check NOT-PASSED: logged users>> "%fullpath%"
    set Users_passed=false
)

:: Check flags
if "!flag_path!"=="" (
    echo Flags/Locks check PASSED: skip check >> "%fullpath%"
    set Flags_passed=true
) else (

    echo Flags/Locks files list: >> "%fullpath%"
    :: Get flags and locks files
    set count_flags=0
    for %%F in ("%flag_path%*.flg" "%flag_path%*.lock") do (
        if exist "%%~F" (
            echo %%~nxF >> "%fullpath%"
            set /a count_flags+=1
        )
    )
    echo Flags/Locks files count: !count_flags! >> "%fullpath%"

    :: Check flags count
    if "!count_flags!"=="0" (
        echo Flags/Locks check PASSED: no flag/locks files>> "%fullpath%"
        set Flags_passed=true
    ) else (
        echo Flags/Locks check NOT-PASSED: found flag/locks files>> "%fullpath%"
        set Flags_passed=false
    )

)

:: Check skip shutdown param
if "!shutdown_allow!"=="1" (
    echo Allow shutdown check PASSED: param %shutdown_allow% >> "%fullpath%"
    set Shutdown_live_mode=true
) else (
    echo Allow shutdown check SIMULATION MODE: param %shutdown_allow% >> "%fullpath%"
    set Shutdown_live_mode=false
)

set all_checks_passed=%Threshold_passed%_%Allowed_time_passed%_%Users_passed%_%Flags_passed%
echo %all_checks_passed%

:: Start Executing Shutdown
if "!all_checks_passed!"=="true_true_true_true" (
    echo All checks PASSED: Start Executing Shutdown>> "%fullpath%"

    set execute_sendmail=0
    if not "!mail_to!"=="" (
        if not "!mail_credentials!"=="" (
            if not "!mail_prog!"=="" (
                set execute_sendmail=1
            )
        )
    )
    if "!execute_sendmail!" == "0" (
        echo Skip Send Mail >> "%fullpath%"
    ) else (
        set subject="Shutdown on %COMPUTERNAME%"
        set body="Shutdown initiated at !nowDate! !nowTIME! on %COMPUTERNAME%, uptime: !diffMin! minutes"

        echo Execute: !mail_prog! "!mail_credentials!" "!mail_to!" !subject! !body! >> "%fullpath%"
        call !mail_prog! "!mail_credentials!" "!mail_to!" !subject! !body! >> "%fullpath%"
        if "!ERRORLEVEL!" == "0" (
            echo Mail sent executeed successfully >> "%fullpath%"
        ) else (
            echo Mail sent completed with Error: !ERRORLEVEL! >> "%fullpath%"
        )
    )

    echo Execute: shutdown /s /t %shutdown_delay% /c "Shutdown in %shutdown_delay% seconds" >> "%fullpath%"
    if "!Shutdown_live_mode!"=="true" (
        shutdown /s /t %shutdown_delay% /c "Shutdown in %shutdown_delay% seconds" >> "%fullpath%" 2>&1
        if "!ERRORLEVEL!" == "0" (
            echo Shutdown executeed successfully >> "%fullpath%"
        ) else (
            echo Shutdown completed with Error: !ERRORLEVEL! >> "%fullpath%"
        )
    ) else (
        echo Skip Shutdown: SIMULATION MODE >> "%fullpath%"
    )
) else (
    echo All checks NOT-PASSED: Skip Executing Shutdown>> "%fullpath%"
)

:end
:: Restore original console codepage
if defined old_cp chcp !old_cp! >nul

:: Show log
type "%fullpath%"

endlocal
