<#
.SYNOPSIS
    Manages per-user Windows file associations for Backup-Toolkit.

.DESCRIPTION
    Used during Backup-Toolkit installation to integrate supported file types with Windows Explorer.
    Provides an interactive menu to inspect, register and remove associations
    for .BT-Backup, .BT-Plan, .BT-Mail-Credentials, .BT-File-Credentials
    and .BT-Rclone-Config files with the corresponding CMD launchers.
    Changes apply to the current Windows user; elevation is normally not required.
    Registration does not override protected Windows default application choices.
    Removal also clears saved default and Open with choices for other applications
    for these extensions, after confirmation.

.EXAMPLE
    .\Tools\Admin\BT-File-Associations.cmd
    Opens the interactive file association menu from the toolkit root.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/Installation.md
#>

# try-catch block for handling unexpected exceptions
try {

# Script version
$ScriptVersion = "26.10.28.0"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolkitRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$toolsPath = Join-Path $toolkitRoot 'Tools'
$capabilitiesPath = 'Software\BackupToolkit\Capabilities'
$fileAssociationsPath = Join-Path $capabilitiesPath 'FileAssociations'
$associations = @(
    [pscustomobject]@{
        Extension = '.BT-Backup'
        ProgId = 'BackupToolkit.BTBackup'
        Description = 'Backup-Toolkit backup configuration'
        Wrapper = 'BT-Backup.cmd'
    }
    [pscustomobject]@{
        Extension = '.BT-Plan'
        ProgId = 'BackupToolkit.BTPlan'
        Description = 'Backup-Toolkit plan configuration'
        Wrapper = 'BT-Plan.cmd'
    }
    [pscustomobject]@{
        Extension = '.BT-Mail-Credentials'
        ProgId = 'BackupToolkit.BTMailCredentials'
        Description = 'Backup-Toolkit mail credentials'
        Wrapper = 'BT-Mail-Credentials.cmd'
    }
    [pscustomobject]@{
        Extension = '.BT-File-Credentials'
        ProgId = 'BackupToolkit.BTFileCredentials'
        Description = 'Backup-Toolkit file credentials'
        Wrapper = 'BT-File-Credentials.cmd'
    }
    [pscustomobject]@{
        Extension = '.BT-Rclone-Config'
        ProgId = 'BackupToolkit.BTRcloneConfig'
        Description = 'Backup-Toolkit rclone configuration'
        Wrapper = 'BT-Rclone-Config.cmd'
    }
)

function Get-CurrentUserRegistryValue {
    param(
        [string]$SubKey,
        [string]$Name
    )

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey)
    if ($null -eq $key) {
        return $null
    }

    try {
        return $key.GetValue($Name)
    } finally {
        $key.Dispose()
    }
}

function Get-ClassesRegistryValue {
    param(
        [string]$SubKey,
        [string]$Name
    )

    $key = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($SubKey)
    if ($null -eq $key) {
        return $null
    }

    try {
        return $key.GetValue($Name)
    } finally {
        $key.Dispose()
    }
}

function Set-CurrentUserRegistryValue {
    param(
        [string]$SubKey,
        [string]$Name,
        [string]$Value
    )

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKey)
    try {
        $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String)
    } finally {
        $key.Dispose()
    }
}

function Remove-CurrentUserRegistryValue {
    param(
        [string]$SubKey,
        [string]$Name,
        [string]$ExpectedValue
    )

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $true)
    if ($null -eq $key) {
        return
    }

    try {
        if ($key.GetValue($Name) -eq $ExpectedValue) {
            $key.DeleteValue($Name, $false)
        }
    } finally {
        $key.Dispose()
    }
}

function Remove-CurrentUserRegistryValueByName {
    param(
        [string]$SubKey,
        [string]$Name
    )

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $true)
    if ($null -eq $key) {
        return
    }

    try {
        if ($key.GetValueNames() -contains $Name) {
            $key.DeleteValue($Name, $false)
        }
    } finally {
        $key.Dispose()
    }
}

function Remove-CurrentUserRegistryKey {
    param([string]$SubKey)

    $path = "HKCU:\$SubKey"
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

function Remove-CurrentUserRegistrySubKeyTree {
    param(
        [string]$ParentSubKey,
        [string]$ChildName
    )

    $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($ParentSubKey, $true)
    if ($null -eq $parentKey) {
        return
    }

    $userChoiceSubKey = "$ParentSubKey\$ChildName\UserChoice"
    $userChoiceRights = [System.Security.AccessControl.RegistryRights]::ReadPermissions -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions
    $userChoiceKey = $null
    $originalSecurity = $null
    $securityChanged = $false

    try {
        $userChoiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            $userChoiceSubKey,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            $userChoiceRights
        )

        if ($null -ne $userChoiceKey) {
            $originalSecurity = $userChoiceKey.GetAccessControl()
            $updatedSecurity = $userChoiceKey.GetAccessControl()
            $currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $denyRules = @(
                foreach ($rule in $updatedSecurity.Access) {
                    if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Deny -or
                        ($rule.RegistryRights -band [System.Security.AccessControl.RegistryRights]::SetValue) -eq 0) {
                        continue
                    }

                    try {
                        $ruleSid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
                    } catch {
                        continue
                    }

                    if ($ruleSid -eq $currentUserSid) {
                        $rule
                    }
                }
            )

            foreach ($denyRule in $denyRules) {
                $updatedSecurity.RemoveAccessRuleSpecific($denyRule)
            }

            if ($denyRules.Count -gt 0) {
                $securityChanged = $true
                $userChoiceKey.SetAccessControl($updatedSecurity)
            }

            $userChoiceKey.Dispose()
            $userChoiceKey = $null
        }

        if ($parentKey.GetSubKeyNames() -contains $ChildName) {
            $parentKey.DeleteSubKeyTree($ChildName, $false)
        }
    } catch {
        $removalError = $_

        if ($securityChanged -and $null -ne $originalSecurity) {
            try {
                $userChoiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
                    $userChoiceSubKey,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    $userChoiceRights
                )
                if ($null -ne $userChoiceKey) {
                    $userChoiceKey.SetAccessControl($originalSecurity)
                    $userChoiceKey.Dispose()
                    $userChoiceKey = $null
                }
            } catch {
                Write-Warning ("Could not restore the original UserChoice permissions for {0}: {1}" -f $ChildName, $_.Exception.Message)
            }
        }

        throw $removalError
    } finally {
        if ($null -ne $userChoiceKey) {
            $userChoiceKey.Dispose()
        }
        $parentKey.Dispose()
    }
}

function Remove-ToolkitApplicationRegistration {
    param($Association)

    $applicationKey = "Software\Classes\Applications\$($Association.Wrapper)"
    $commandKey = "$applicationKey\shell\open\command"
    $registeredCommand = Get-CurrentUserRegistryValue -SubKey $commandKey -Name ''
    $wrapperPath = [System.IO.Path]::GetFullPath((Join-Path $toolsPath $Association.Wrapper))
    $expectedCommand = '"{0}" "%1"' -f $wrapperPath

    if ($registeredCommand -ieq $expectedCommand) {
        Remove-CurrentUserRegistryKey -SubKey $applicationKey
    }
}

function Remove-EmptyCurrentUserRegistryKey {
    param([string]$SubKey)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey)
    if ($null -eq $key) {
        return $false
    }

    try {
        $isEmpty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
    } finally {
        $key.Dispose()
    }

    if (-not $isEmpty) {
        return $false
    }

    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($SubKey, $false)
    return $true
}

function Get-UserChoiceProgId {
    param([string]$Extension)

    $userChoiceKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
    return Get-CurrentUserRegistryValue -SubKey $userChoiceKey -Name 'ProgId'
}

function Test-UserChoiceMatchesWrapper {
    param($Association)

    $userChoiceProgId = Get-UserChoiceProgId -Extension $Association.Extension
    if ([string]::IsNullOrWhiteSpace([string]$userChoiceProgId)) {
        return $false
    }

    if ($userChoiceProgId -eq $Association.ProgId) {
        return $true
    }

    $commandKey = "$userChoiceProgId\shell\open\command"
    $userChoiceCommand = Get-ClassesRegistryValue -SubKey $commandKey -Name ''
    $wrapperPath = [System.IO.Path]::GetFullPath((Join-Path $toolsPath $Association.Wrapper))
    $expectedCommand = '"{0}" "%1"' -f $wrapperPath

    return $userChoiceCommand -ieq $expectedCommand
}

function Show-Associations {
    Write-Host 'File associations for the current user:'

    foreach ($association in $associations) {
        $extensionKey = "Software\Classes\$($association.Extension)"
        $registeredProgId = Get-CurrentUserRegistryValue -SubKey $extensionKey -Name ''
        $userChoiceProgId = Get-UserChoiceProgId -Extension $association.Extension
        $effectiveProgId = if ([string]::IsNullOrWhiteSpace([string]$userChoiceProgId)) {
            $registeredProgId
        } else {
            $userChoiceProgId
        }

        $command = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$effectiveProgId)) {
            $commandKey = "$effectiveProgId\shell\open\command"
            $command = Get-ClassesRegistryValue -SubKey $commandKey -Name ''
        }

        Write-Host "  $($association.Extension)"
        Write-Host "    Registered default: $(if ($registeredProgId) { $registeredProgId } else { '(not registered)' })"
        Write-Host "    Windows default:    $(if ($userChoiceProgId) { $userChoiceProgId } else { '(uses registered default)' })"
        Write-Host "    Open command:       $(if ($command) { $command } else { '(not available)' })"
    }
}

function Register-Associations {
    foreach ($association in $associations) {
        $wrapperPath = Join-Path $toolsPath $association.Wrapper
        if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
            throw "Required command wrapper was not found: $wrapperPath"
        }
    }

    $blockedExtensions = [System.Collections.Generic.List[string]]::new()

    foreach ($association in $associations) {
        $extensionKey = "Software\Classes\$($association.Extension)"
        $progIdKey = "Software\Classes\$($association.ProgId)"
        $wrapperPath = Join-Path $toolsPath $association.Wrapper
        $command = '"{0}" "%1"' -f $wrapperPath

        Set-CurrentUserRegistryValue -SubKey $extensionKey -Name '' -Value $association.ProgId
        Set-CurrentUserRegistryValue -SubKey $progIdKey -Name '' -Value $association.Description
        Set-CurrentUserRegistryValue -SubKey "$progIdKey\shell" -Name '' -Value 'open'
        Set-CurrentUserRegistryValue -SubKey "$progIdKey\shell\open\command" -Name '' -Value $command
        Set-CurrentUserRegistryValue -SubKey $fileAssociationsPath -Name $association.Extension -Value $association.ProgId

        $userChoiceProgId = Get-UserChoiceProgId -Extension $association.Extension
        if (-not [string]::IsNullOrWhiteSpace([string]$userChoiceProgId) -and -not (Test-UserChoiceMatchesWrapper -Association $association)) {
            $blockedExtensions.Add($association.Extension)
        }

        Write-Host ("Registered {0} to {1}" -f $association.Extension, $association.Wrapper)
    }

    Set-CurrentUserRegistryValue -SubKey $capabilitiesPath -Name 'ApplicationName' -Value 'Backup-Toolkit'
    Set-CurrentUserRegistryValue -SubKey $capabilitiesPath -Name 'ApplicationDescription' -Value 'Backup-Toolkit configuration files'
    Set-CurrentUserRegistryValue -SubKey 'Software\RegisteredApplications' -Name 'Backup-Toolkit' -Value $capabilitiesPath

    if ($blockedExtensions.Count -gt 0) {
        Write-Warning ("Windows already has a protected default app selection for: {0}." -f ($blockedExtensions -join ', '))
        Write-Host 'Select Backup-Toolkit under Settings > Apps > Default apps to make it the default.'
        Start-Process 'ms-settings:defaultapps'
    }
}

function Unregister-Associations {
    $extensionList = ($associations | ForEach-Object { $_.Extension }) -join ', '
    Write-Warning 'This also removes all current-user default and Open With choices for these extensions, including choices for other apps.'
    $confirmation = Read-Host ("Remove all per-user file association data for {0}? (Y/N)" -f $extensionList)
    if ($confirmation -notin @('Y', 'y')) {
        Write-Host 'Operation cancelled.'
        return
    }

    $failedExtensions = [System.Collections.Generic.List[string]]::new()

    foreach ($association in $associations) {
        $extensionKey = "Software\Classes\$($association.Extension)"
        $progIdKey = "Software\Classes\$($association.ProgId)"
        $openWithProgIdsKey = "$extensionKey\OpenWithProgids"
        $fileExtsParentKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'

        Remove-CurrentUserRegistryValue -SubKey $extensionKey -Name '' -ExpectedValue $association.ProgId
        Remove-CurrentUserRegistryValueByName -SubKey $openWithProgIdsKey -Name $association.ProgId
        Remove-CurrentUserRegistryValueByName -SubKey $openWithProgIdsKey -Name "Applications\$($association.Wrapper)"
        Remove-EmptyCurrentUserRegistryKey -SubKey $openWithProgIdsKey | Out-Null
        Remove-EmptyCurrentUserRegistryKey -SubKey $extensionKey | Out-Null

        Remove-ToolkitApplicationRegistration -Association $association
        Remove-CurrentUserRegistryKey -SubKey $progIdKey
        Remove-CurrentUserRegistryValue -SubKey $fileAssociationsPath -Name $association.Extension -ExpectedValue $association.ProgId

        try {
            Remove-CurrentUserRegistrySubKeyTree -ParentSubKey $fileExtsParentKey -ChildName $association.Extension
            Write-Host ("Removed per-user file type data for {0}" -f $association.Extension)
        } catch {
            $failedExtensions.Add($association.Extension)
            Write-Warning ("Could not completely remove per-user data for {0}: {1}" -f $association.Extension, $_.Exception.Message)
        }
    }

    Remove-CurrentUserRegistryValue -SubKey 'Software\RegisteredApplications' -Name 'Backup-Toolkit' -ExpectedValue $capabilitiesPath
    Remove-CurrentUserRegistryKey -SubKey $capabilitiesPath

    if ($failedExtensions.Count -gt 0) {
        Write-Warning ("Some per-user file type data remains for: {0}." -f ($failedExtensions -join ', '))
    }
}

$exitMenu = $false
do {
    Write-Host ''
    Write-Host ("BT-File-Associations v{0}: .BT-Backup, .BT-Plan, .BT-Mail-Credentials, .BT-File-Credentials, .BT-Rclone-Config" -f $ScriptVersion)
    Write-Host 'S. Show'
    Write-Host 'A. Add associations'
    Write-Host 'R. Remove associations'
    Write-Host 'Q. Exit'
    $choice = (Read-Host 'Select an option').Trim().ToUpperInvariant()

    try {
        switch ($choice) {
            'S' { Show-Associations }
            'A' { Register-Associations }
            'R' { Unregister-Associations }
            'Q' { $exitMenu = $true }
            default { Write-Host 'Invalid choice.' }
        }
    } catch {
        Write-Host ("ERROR: {0}" -f $_.Exception.Message)
    }
} while (-not $exitMenu)

} catch {
    # Display an unhandled exception if one occurred in the try-catch block
    Write-Error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}