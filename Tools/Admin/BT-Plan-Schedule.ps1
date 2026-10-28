<#
.SYNOPSIS
    Interactively manages a daily Windows scheduled task for a Backup-Toolkit plan.

.DESCRIPTION
    Provides menus to create, delete, inspect, run, enable and disable a task.
    The task runs Tools/BT-Plan.ps1 with the selected .BT-Plan configuration.
    Initial settings normally come from BT-Plan-Schedule.cmd.
    Menu changes apply only to the current session.
    Creating and deleting tasks require elevation. Creation prompts for the current user's password.

.PARAMETER TaskName
    Name of the Windows scheduled task to create or manage.

.PARAMETER Description
    Optional description stored with the task.

.PARAMETER StartTime
    Required for creation. Daily start time accepted by New-ScheduledTaskTrigger -At.

.PARAMETER ConfigFilePath
    Required for creation. Full path to an existing .BT-Plan configuration file.

.PARAMETER BTPath
    Required for creation. Toolkit root containing Tools; also the task working directory.

.EXAMPLE
    .\Tools\Admin\BT-Plan-Schedule.cmd
    Opens the menu with wrapper defaults; review creation settings before confirming.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Plan-Schedule.md
#>

# Script parameters configured in BT-Plan-Schedule.cmd
param(
    # Name of the scheduled task.
    [string]$TaskName,
    # Description stored with the scheduled task.
    [string]$Description,
    # Daily trigger time for the scheduled task.
    [string]$StartTime,
    # Full path to the BT-Plan configuration file.
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
$ProgramPath = "powershell.exe"
$PSArgument = '-ExecutionPolicy Bypass -NonInteractive -File'
$ScriptArgument = '--NoPause'
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

    foreach ($parameterName in @('TaskName', 'StartTime', 'ConfigFilePath', 'BTPath')) {
        $parameterValue = Get-Variable -Name $parameterName -ValueOnly -Scope Script

        if ([string]::IsNullOrWhiteSpace($parameterValue)) {
            Write-Host "ERROR: Required parameter '$parameterName' is empty."
            $parametersAreValid = $false
        }
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

        $ScriptPath = Join-Path $BTPath "tools\BT-Plan.ps1"

        $TaskArgument = @(
            $PSArgument
            ('"{0}"' -f $ScriptPath)
            ('"{0}"' -f $ConfigFilePath)
            $ScriptArgument
        ) -join ' '

        $Action = New-ScheduledTaskAction `
            -Execute $ProgramPath `
            -Argument $TaskArgument `
            -WorkingDirectory $BTPath

        $Trigger = New-ScheduledTaskTrigger `
            -Daily `
            -At $StartTime

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

    $value = Read-Host "StartTime [$StartTime]"
    if ($value) { $script:StartTime = $value }

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
    Write-Host "StartTime:      $StartTime"
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
