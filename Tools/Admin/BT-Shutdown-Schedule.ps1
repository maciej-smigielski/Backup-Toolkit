<#
.SYNOPSIS
    Interactively manages a repeating Windows scheduled task for shutdown checks.

.DESCRIPTION
    Provides menus to create, delete, inspect, run, enable and disable a task.
    The task runs Tools/BT-Shutdown.cmd through cmd.exe with the selected configuration.
    Its first trigger is today at midnight plus StartOffsetMinutes; it repeats indefinitely.
    BT-Shutdown.cmd evaluates shutdown conditions, not this task manager.
    Initial settings normally come from BT-Shutdown-Schedule.cmd; menu changes are session-only.
    Creating and deleting tasks require elevation. Creation prompts for the current user's password.
    Running the task may shut down the computer when its configuration permits it.

.PARAMETER TaskName
    Name of the Windows scheduled task to create or manage.

.PARAMETER Description
    Optional description stored with the task.

.PARAMETER StartOffsetMinutes
    Required for creation. Minutes after midnight for the first trigger, from 0 to 1439.

.PARAMETER IntervalMinutes
    Required for creation. Minutes between repeated runs, from 1 to 1440.

.PARAMETER ConfigFilePath
    Required for creation. Full path to an existing BT-Shutdown INI configuration file.

.PARAMETER BTPath
    Required for creation. Toolkit root containing Tools; also the task working directory.

.EXAMPLE
    .\Tools\Admin\BT-Shutdown-Schedule.cmd
    Opens the menu with wrapper defaults. For testing, use shutdown_allow=0 in the configuration.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Shutdown-Schedule.md
#>

# Script parameters configured in BT-Shutdown-Schedule.cmd
param(
    # Name of the scheduled task.
    [string]$TaskName,
    # Description stored with the scheduled task.
    [string]$Description,
    # Offset in minutes after midnight for the first run (0-1439).
    [string]$StartOffsetMinutes,
    # Interval between runs in minutes (1-1440).
    [string]$IntervalMinutes,
    # Full path to the BT-Shutdown configuration file.
    [string]$ConfigFilePath,
    # Path to BackupToolkitHome, the toolkit installation directory.
    [string]$BTPath
)

# try-catch block for handling unexpected exceptions
try {

# Script version
$ScriptVersion = "26.10.28.0"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Console encoding to UTF-8
cmd /c "chcp 65001 >nul"
$OutputEncoding = [System.Text.Encoding]::UTF8

# Check whether PowerShell has the full path to the currently running script
if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
    throw "PSCommandPath is empty."
}

# Task configuration parameters
$ProgramPath = $env:ComSpec
$TaskUser = "$env:USERDOMAIN\$env:USERNAME"
$CurrentPrincipal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdministrator = $CurrentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

function Test-ConfiguredFilePaths {
    $pathsAreValid = $true

    foreach ($pathParameter in @('ConfigFilePath', 'BTPath')) {
        $path = Get-Variable -Name $pathParameter -ValueOnly -Scope Script

        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $path = [System.Environment]::ExpandEnvironmentVariables($path)

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "ERROR: Invalid file path for '$pathParameter': $path"
            $pathsAreValid = $false
            continue
        }

        $normalizedPath = [System.IO.Path]::GetFullPath($path)
        Set-Variable -Name $pathParameter -Value $normalizedPath -Scope Script
    }

    return $pathsAreValid
}

function Test-RequiredTaskParameters {
    $parametersAreValid = $true

    foreach ($parameterName in @('TaskName', 'StartOffsetMinutes', 'IntervalMinutes', 'ConfigFilePath', 'BTPath')) {
        $parameterValue = Get-Variable -Name $parameterName -ValueOnly -Scope Script

        if ([string]::IsNullOrWhiteSpace($parameterValue)) {
            Write-Host "ERROR: Required parameter '$parameterName' is empty."
            $parametersAreValid = $false
        }
    }

    $startOffsetValue = 0
    if (-not [string]::IsNullOrWhiteSpace($StartOffsetMinutes) -and
        (-not [int]::TryParse($StartOffsetMinutes, [ref]$startOffsetValue) -or $startOffsetValue -lt 0 -or $startOffsetValue -gt 1439)) {
        Write-Host "ERROR: 'StartOffsetMinutes' must be an integer between 0 and 1439."
        $parametersAreValid = $false
    }

    $intervalValue = 0
    if (-not [string]::IsNullOrWhiteSpace($IntervalMinutes) -and
        (-not [int]::TryParse($IntervalMinutes, [ref]$intervalValue) -or $intervalValue -lt 1 -or $intervalValue -gt 1440)) {
        Write-Host "ERROR: 'IntervalMinutes' must be an integer between 1 and 1440."
        $parametersAreValid = $false
    }

    return $parametersAreValid
}

function Test-AdministratorPrivileges {
    if ($IsAdministrator) {
        return $true
    }

    Write-Host "ERROR: Administrator privileges are required to create or delete scheduled tasks." -ForegroundColor Yellow
    $null = Read-Host "Press Enter to continue"
    return $false
}

function New-ScheduledTaskActions {
    if (-not (Test-AdministratorPrivileges)) {
        return
    }

    Write-Host "Creating task '$TaskName'..."

    if ((Test-RequiredTaskParameters)) {
        $Password = Read-Host "Enter the password for user $TaskUser" -AsSecureString

        $ScriptPath = Join-Path $BTPath "tools\BT-Shutdown.cmd"
        $TaskArgument = @(
            '/c'
            ('""{0}"' -f $ScriptPath)
            ('"{0}""' -f $ConfigFilePath)
        ) -join ' '

        $Action = New-ScheduledTaskAction `
            -Execute $ProgramPath `
            -Argument $TaskArgument `
            -WorkingDirectory $BTPath

        $startAt = [datetime]::Today.AddMinutes([int]$StartOffsetMinutes)

        $Trigger = New-ScheduledTaskTrigger `
            -Once `
            -At $startAt

        $repetitionClass = Get-CimClass `
            -Namespace 'root/Microsoft/Windows/TaskScheduler' `
            -ClassName 'MSFT_TaskRepetitionPattern'
        $repetition = New-CimInstance `
            -CimClass $repetitionClass `
            -Property @{
                Interval = [System.Xml.XmlConvert]::ToString([timespan]::FromMinutes([int]$IntervalMinutes))
                StopAtDurationEnd = $false
            } `
            -ClientOnly
        $Trigger.Repetition = $repetition

        $TaskSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable

        try {
            Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $Action `
                -Trigger $Trigger `
                -User $TaskUser `
                -Password ([System.Net.NetworkCredential]::new("", $Password).Password) `
                -Settings $TaskSettings `
                -Force `
                -Description $Description |
                Out-Host
        } catch {
            Write-Host "Unable to register scheduled task '$TaskName': $($_.Exception.Message)"
        }
    }

    Read-Host "Press Enter to continue"
}

function Remove-ScheduledTaskActions {
    if (-not (Test-AdministratorPrivileges)) {
        return
    }

    Write-Host "Removing task '$TaskName'..."

    $confirm = Read-Host "Are you sure you want to remove the task? (Y/N)"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false |
                Out-Host
        } catch {
            Write-Host "Unable to unregister scheduled task '$TaskName': $($_.Exception.Message)"
        }
    } else {
        Write-Host "Operation cancelled."
    }

    Read-Host "Press Enter to continue"
}

function Get-ScheduledTaskStatusActions {
    Write-Host "Task status '$TaskName'..."

    try {
        Get-ScheduledTask -TaskName $TaskName | ForEach-Object {
            $TaskInfo = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath

            [pscustomobject]@{
                TaskName           = $_.TaskName
                State              = $_.State
                LastRunTime        = $TaskInfo.LastRunTime
                NextRunTime        = $TaskInfo.NextRunTime
                LastTaskResult     = $TaskInfo.LastTaskResult
                NumberOfMissedRuns = $TaskInfo.NumberOfMissedRuns
                Description        = $_.Description
            }
        } |
            Format-Table -AutoSize |
            Out-Host
    } catch {
        Write-Host "Unable to get scheduled task '$TaskName': $($_.Exception.Message)"
    }

    $null = Read-Host "Press Enter to continue"
}

function Start-ScheduledTaskActions {
    Write-Host "Running task '$TaskName'..."

    try {
        Start-ScheduledTask -TaskName $TaskName |
            Out-Host
    } catch {
        Write-Host "Unable to start scheduled task '$TaskName': $($_.Exception.Message)"
    }

    Read-Host "Press Enter to continue"
}

function Enable-ScheduledTaskActions {
    Write-Host "Enabling task '$TaskName'..."

    try {
        Enable-ScheduledTask -TaskName $TaskName |
            Out-Host
    } catch {
        Write-Host "Unable to enable scheduled task '$TaskName': $($_.Exception.Message)"
    }

    Read-Host "Press Enter to continue"
}

function Disable-ScheduledTaskActions {
    Write-Host "Disabling task '$TaskName'..."

    $confirm = Read-Host "Are you sure you want to disable the task? (Y/N)"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        try {
            Disable-ScheduledTask -TaskName $TaskName |
                Out-Host
        } catch {
            Write-Host "Unable to disable scheduled task '$TaskName': $($_.Exception.Message)"
        }
    } else {
        Write-Host "Operation cancelled."
    }

    Read-Host "Press Enter to continue"
}

function Show-TaskInfo {

    if (-not (Test-ConfiguredFilePaths)) {
        Read-Host "Press Enter to continue"
    }

    Write-Host "Parameters"
    if ($IsAdministrator) {
        Write-Host "Privileges:     Running with administrator privileges." -ForegroundColor Green
    } else {
        Write-Host "Privileges:     Running without administrator privileges; Create/Delete actions cannot be performed." -ForegroundColor Yellow
    }
    Write-Host "ScriptVersion:  $ScriptVersion"
    Write-Host "TaskName:       $TaskName"
}

function Set-TaskParameters {
    Write-Host "Press Enter to keep the current value."

    $value = Read-Host "TaskName [$TaskName]"
    if ($value) { $script:TaskName = $value }

    Read-Host "Press Enter to continue"
}

function Set-CreateTaskParameters {
    Write-Host "Press Enter to keep the current value."

    $value = Read-Host "TaskName [$TaskName]"
    if ($value) { $script:TaskName = $value }

    $value = Read-Host "Description [$Description]"
    if ($value) { $script:Description = $value }

    $value = Read-Host "StartOffsetMinutes [$StartOffsetMinutes]"
    if ($value) { $script:StartOffsetMinutes = $value }

    $value = Read-Host "IntervalMinutes [$IntervalMinutes]"
    if ($value) { $script:IntervalMinutes = $value }

    $value = Read-Host "ConfigFilePath [$ConfigFilePath]"
    if ($value) { $script:ConfigFilePath = $value }

    $value = Read-Host "BTPath [$BTPath]"
    if ($value) { $script:BTPath = $value }

    Read-Host "Press Enter to continue"
}

function Show-CreateTaskInfo {
    Write-Host ""
    Write-Host "Create Parameters"
    Write-Host "TaskName:       $TaskName"
    Write-Host "Description:    $Description"
    Write-Host "First run:      midnight + $StartOffsetMinutes min"
    Write-Host "Interval:       every $IntervalMinutes minutes"
    Write-Host "ConfigFilePath: $ConfigFilePath"
    Write-Host "BTPath:         $BTPath"
    Write-Host "TaskUser:       $TaskUser"
}

function Show-CreateMenu {
    Write-Host ""
    Write-Host "P. Parameters"
    Write-Host "C. Create"
    Write-Host "Q. Quit"
}

function Invoke-CreateMenu {
    do {
        Show-CreateTaskInfo
        Show-CreateMenu
        $createChoice = Read-Host "Select an option"

        switch ($createChoice) {
            "P" { Set-CreateTaskParameters }
            "C" { New-ScheduledTaskActions }
            "Q" { Write-Host "Finished create menu." }
            default { Write-Host "Invalid choice." }
        }
    } while ($createChoice -ne "Q")
}

function Show-Menu {
    Write-Host ""
    Write-Host "P. Parameters"
    Write-Host "C. Create"
    Write-Host "D. Delete"
    Write-Host "S. Status"
    Write-Host "R. Run"
    Write-Host "E. Enable"
    Write-Host "X. Disable"
    Write-Host "Q. Quit"
}

do {
    Show-TaskInfo
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "P" { Set-TaskParameters }
        "C" { Invoke-CreateMenu }
        "D" { Remove-ScheduledTaskActions }
        "S" { Get-ScheduledTaskStatusActions }
        "R" { Start-ScheduledTaskActions }
        "E" { Enable-ScheduledTaskActions }
        "X" { Disable-ScheduledTaskActions }
        "Q" { Write-Host "Finished." }
        default { Write-Host "Invalid choice." }
    }
    } while ($choice -ne "Q")


} catch {
    # Display an unhandled exception if one occurred in the try-catch block
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
