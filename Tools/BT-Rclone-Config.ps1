<#
.SYNOPSIS
    BT-Rclone-Config.ps1 - Uruchamina rclone w trybie config lub gui dla zaszyfrowanego pliku konfiguracyjnego rclone.

.DESCRIPTION
    Skrypt uruchamia rclone w trybie config lub gui,
    poprzez menu pozwala wybrać opcje pracy,
    pobiera credentials z pliku BT-Mail-Credentials.xml.

.EXAMPLE
    .\BT-Rclone-Config.ps1 -ConfigFile config.BT-Rclone-Config
    Uruchamia skrypt w trybie standardowym.

.EXAMPLE
    .\BT-Rclone-Config.ps1 -ConfigFile config.BT-Rclone-Config -Debug
    Uruchamia skrypt w trybie debugowania.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Rclone-Config.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-Rclone-Config (standardowo zaszyfrowany plik rclone.conf)
    [Parameter(Position = 0)]
    [string]$ConfigFile
)

# try-catch blok do obsługi nieprzewidzianych wyjątków
try {

# Wersja skryptu
$ScriptVersion = "26.10.28.0"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Kodowanie konsoli na UTF-8
cmd /c "chcp 65001 >nul"
$OutputEncoding = [System.Text.Encoding]::UTF8

# Sprawdzenie i zapamietanie trybu debug
$DebugMode = $PSBoundParameters.ContainsKey('Debug')

# Czy PowerShell ma pełną ścieżkę do aktualnie uruchomionego skryptu
if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
    throw "PSCommandPath is empty."
}

# Dane wywołanego skryptu 
$Script = [PSCustomObject]@{
    # Komenda skryptu
    CommandPath = $PSCommandPath
    # Ścieżka do katalogu skryptu
    HomeDir = $PSScriptRoot
    # Pobierz nazwę pliku skryptu
    Name = [System.IO.Path]::GetFileName($PSCommandPath)
    # Pobierz nazwę pliku skryptu bez rozszerzenia
    BaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Importuje moduł BT.Common
try {
    Import-Module "$PSScriptRoot\Modules\BT.Common\BT.Common.psd1" -Force -ErrorAction Stop
}
catch {
    throw
}

# Inicjalizacja modułu BT.Common
$null = Initialize-BTCommon -DebugMode:$DebugMode -DebugToConsole:$true -ApplicationTitle:$Script.BaseName

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów
$ExitDefinitions = @{
    Success = @{ Code = 0; Message = "Completed successfully" }                     # Zakończono pomyślnie
    Unhandled = @{ Code = 1; Message = "Unhandled exception" }                      # Nieobsłużony wyjątek, proces zatrzymany, w write-error wartość Code i Message wpisane jawnie 
    General = @{ Code = 101; Message = "General error, process stopped" }           # Ogólny błąd, proces zatrzymany
    Read = @{ Code = 121; Message = "Read error" }                                  # Błąd odczytu
    Write = @{ Code = 122; Message = "Write error" }                                # Błąd zapisu
    Rclone = @{ Code = 123; Message = "Rclone error" }                              # Błąd rclone
}

# Domyślne wartości dla katalogów i prefiksów
$default_rclone_config_prefix = "NoName"
$default_rclone_config_extension = "BT-Rclone-Config"         # rozszerzenie pliku konfiguracyjnego rclone
$default_credentials_extension = "BT-File-Credentials"        # rozszerzenie pliku file-credentials

# Ogólne ustawienia dla konfiguracji rclone config
$RcloneConfigGeneral = [PSCustomObject]@{
    RcloneProgPath = $null
    RcloneGetPasswordPath = $null
}

$RcloneConfigEmptyData = [PSCustomObject]@{
    # Dane pliku rclone config
    ConfigFile = [PSCustomObject]@{
        # Ścieżka do katalogu pliku rclone config
        DirectoryName = ""
        # Nazwa pliku rclone config
        FileName = ""
        # Nazwa pliku rclone config bez rozszerzenia
        BaseName = ""
        # Nazwa pliku rclone config bez rozszerzenia obcięta do pierwszej kropki
        BaseNamePrefix = ""
        # Rozszerzenie pliku rclone config
        Extension = ""
        # Informacja, czy plik rclone config jest zaszyfrowany
        IsEncrypted = $false
    }
    # Ścieżka do istniejącego pliku rclone config
    ConfigFilePath = $null
    # Nazwa hosta i użytkownika
    HostName = "$env:COMPUTERNAME"
    UserName = "$env:USERNAME"
    # Dane pliku rclone credentials, nazwa pliku credentials jest tworzona na podstawie nazwy pliku config, nazwy komputera i nazwy użytkownika
    CredentialsFile = [PSCustomObject]@{
        # Ścieżka do katalogu pliku rclone credentials
        DirectoryName = ""
        # Nazwa pliku rclone credentials
        FileName = ""
        # Ścieżka do pliku rclone credentials
        FullPath = ""
    }
    # Czy plik rclone credentials istnieje
    IsCredentialsFile = $false
    # Ścieżka do istniejącego pliku rclone credentials
    CredentialsFilePath = $null
}

$RcloneConfigFileName = $null
$RcloneConfigFileData = $null

# Script information
Write-Log -LogLine ("Script.CommandPath: >$($Script.CommandPath)<") -DebugLevel:$true
Write-Log -LogLine ("Script.HomeDir: >$($Script.HomeDir)<") -DebugLevel:$true
Write-Log -LogLine ("Script.Name: >$($Script.Name)<") -DebugLevel:$true
Write-Log -LogLine ("Script.BaseName: >$($Script.BaseName)<") -DebugLevel:$true

# Versions
Write-Log -LogLine ("Script Version: >$($ScriptVersion)<") -DebugLevel:$true

# Arguments
Write-Log -LogLine ("Arg.ConfigFile: >$($ConfigFile)<") -DebugLevel:$true
Write-Log -LogLine ("Arg.DebugMode: >$($DebugMode)<") -DebugLevel:$true


# Initialize BT-Rclone-Config environment, on error stop the script
function Initialize-RcloneConfigEnvironment {

    # czy istnieje rclone_prog
    try {
        $RcloneConfigGeneral.RcloneProgPath = Get-Item "$PSScriptRoot\Utilities\Rclone\rclone.exe" -ErrorAction Stop
    } catch {
        $ExitResult_local=$ExitDefinitions.General
        Write-LogError -LogMessage "Check RcloneProgPath." -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        Exit $($ExitResult_local.Code)
    }
    Write-Log -LogLine ("RcloneProgPath: >$($RcloneConfigGeneral.RcloneProgPath)<") -DebugLevel:$true

    # Sprawdza istnienie BT-File-Get-Password
    try {
        $RcloneConfigGeneral.RcloneGetPasswordPath = Get-Item "$PSScriptRoot\BT-File-Get-Password.cmd" -ErrorAction Stop
    } catch {
        $ExitResult_local=$ExitDefinitions.General
        Write-LogError -LogMessage "Check RcloneGetPasswordPath." -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        Exit $($ExitResult_local.Code)
    }
    Write-Log -LogLine ("RcloneGetPasswordPath: >$($RcloneConfigGeneral.RcloneGetPasswordPath)<") -DebugLevel:$true

    return $null
}

function Initialize-RcloneConfigFile {
    param(
        [Parameter(Mandatory)]
        [string]$CRName,                    # RcloneConfigFileName
        [bool]$CreateOrOverwrite = $false   # Jeżeli true to plik konfiguracji Rclone zostanie utworzony lub jeśli już istnieje zostanie nadpisany,
                                            # nie pyta użytkownika, tylko automatycznie tworzy lub nadpisuje plik
    )

    # Initialize a copy of the empty Rclone config data structure
    $CRData = $RcloneConfigEmptyData.PSObject.Copy()

    # Extract the components of the Rclone config file path
    try {
        $CRData.ConfigFile.DirectoryName = [System.IO.Path]::GetDirectoryName($CRName)
        Write-Log -LogLine ("ConfigFile.DirectoryName: >$($CRData.ConfigFile.DirectoryName)<") -DebugLevel:$true

        $CRData.ConfigFile.FileName = [System.IO.Path]::GetFileName($CRName)
        Write-Log -LogLine ("ConfigFile.FileName: >$($CRData.ConfigFile.FileName)<") -DebugLevel:$true

        $CRData.ConfigFile.BaseName = [System.IO.Path]::GetFileNameWithoutExtension($CRName)
        Write-Log -LogLine ("ConfigFile.BaseName: >$($CRData.ConfigFile.BaseName)<") -DebugLevel:$true

        $CRData.ConfigFile.BaseNamePrefix = $CRData.ConfigFile.BaseName.Split('.')[0]
        Write-Log -LogLine ("ConfigFile.BaseNamePrefix: >$($CRData.ConfigFile.BaseNamePrefix)<") -DebugLevel:$true

        $CRData.ConfigFile.Extension = [System.IO.Path]::GetExtension($CRName)
        Write-Log -LogLine ("ConfigFile.Extension: >$($CRData.ConfigFile.Extension)<") -DebugLevel:$true
    } catch {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Check ConfigFile >$CRName<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    # Sprawdzenie BaseName, nazwa pliku config bez rozszerzenia, nie moze być pusta
    if ([string]::IsNullOrWhiteSpace($($CRData.ConfigFile.BaseName))) {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("BaseName in ConfigFile >$CRName< is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    # Sprawdzenie rozszerzenia, musi być równa nazwie skryptu $default_rclone_config_extension
    # porównanie w wersji uppercase, aby zaakceptować różne wielkości liter
    if ($($CRData.ConfigFile.Extension).ToUpperInvariant() -ne (("."+$($default_rclone_config_extension)).ToUpperInvariant())) {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Extension in ConfigFile >$CRName< must be >.$default_rclone_config_extension<.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    # Tworzenie lub nadpisanie pliku konfiguracji Rclone, jeśli ustawiono $CreateOrOverwrite
    if ($CreateOrOverwrite) {
        Write-Log -LogLine ("Create or overwrite Rclone config file: >$CRName<") -DebugLevel:$true
        try {
            $CRData.ConfigFilePath = New-Item -Path $CRName -ItemType File -Force -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Write
            Write-LogError -LogMessage ("Unable to create ConfigFile >$CRName<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            return $null
        }
    } else {
        # Sprawdzenie istnienia pliku konfiguracji Rclone, jeśli nie ustawiono $CreateOrOverwrite
        try {
            $CRData.ConfigFilePath = Get-Item $CRName -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Read
            Write-LogError -LogMessage ("Check ConfigFile >$CRName<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            return $null
        }

        # Sprawdzenie czy podana ścieżka do pliku rclone config wskazuje na plik (a nie katalog)
        if ($CRData.ConfigFilePath.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Read
            Write-LogError -LogMessage ("Parameter ConfigFile >$($CRData.ConfigFilePath)< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            return $null
        }
    }
    Write-Log -LogLine ("ConfigFilePath: >$($CRData.ConfigFilePath)<") -DebugLevel:$true

    # Sprawdzenie czy plik rclone config jest zaszyfrowany
    try {
        $EncryptionHeaderMatches = @(Select-String -LiteralPath $($CRData.ConfigFilePath) -Pattern '^RCLONE_ENCRYPT_V\d+:' -ErrorAction Stop)
        $CRData.ConfigFile.IsEncrypted = ($EncryptionHeaderMatches.Count -eq 1)
    } catch {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Unable to check encryption of ConfigFile >$CRName<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }
    Write-Log -LogLine ("ConfigFilePath.IsEncrypted: >$($CRData.ConfigFile.IsEncrypted)<") -DebugLevel:$true

    # Ustawienie ścieżki do pliku credentials na podstawie katalogu i nazwy pliku konfiguracji Rclone
    $CRData.CredentialsFile.DirectoryName = [System.IO.Path]::GetDirectoryName($($CRData.ConfigFilePath))
    $CRData.CredentialsFile.FileName = "$($CRData.ConfigFile.BaseNamePrefix).$($CRData.HostName).$($CRData.UserName).$($default_credentials_extension)"
    $CRData.CredentialsFile.FullPath = Join-Path -Path $($CRData.CredentialsFile.DirectoryName) -ChildPath $($CRData.CredentialsFile.FileName)
    Write-Log -LogLine ("CredentialsFile.FullPath: >$($CRData.CredentialsFile.FullPath)<") -DebugLevel:$true

    # Sprawdza czy istnieje plik BT-File-Credentials
    try {
        $CRData.CredentialsFilePath = Get-Item $CRData.CredentialsFile.FullPath -ErrorAction Stop
        $CRData.IsCredentialsFile = $true
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Log -LogLine ("Credentials File: >$($CRData.CredentialsFile.FileName)< Not Exist") -DebugLevel:$true
    } catch {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Unable to check existence of Credentials File: >$($CRData.CredentialsFile.FileName)<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    return $CRData
}

function Update-RcloneConfigFile {
    # Sprawdzenie czy plik rclone config jest zaszyfrowany
    try {
        $EncryptionHeaderMatches = @(Select-String -LiteralPath $($RcloneConfigFileData.ConfigFilePath) -Pattern '^RCLONE_ENCRYPT_V\d+:' -ErrorAction Stop)
        $RcloneConfigFileData.ConfigFile.IsEncrypted = ($EncryptionHeaderMatches.Count -eq 1)
    } catch {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Unable to check encryption of ConfigFile >$RcloneConfigFileData.ConfigFilePath<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -WriteToHost:$true
    }
    Write-Log -LogLine ("ConfigFilePath.IsEncrypted: >$($RcloneConfigFileData.ConfigFile.IsEncrypted)<") -DebugLevel:$true
}
function Invoke-EncryptConfigAction {
    Write-Log -LogLine ("Action-Encrypt") -WriteToHost:$true
    if (-not $RcloneConfigFileData.IsCredentialsFile) {
        Write-Log -LogLine ("Credentials File is not existing, encryption cannot be applied.") -WriteToHost:$true
    } else {

        # Buduje argumenty wywołania rclone version
        $RcloneCommandArgs = @()
        $RcloneCommandArgs += "--config"
        $RcloneCommandArgs += "$RcloneConfigFileName"
        $RcloneCommandArgs += "config"
        $RcloneCommandArgs += "encryption"
        $RcloneCommandArgs += "set"
        $RcloneCommandArgs += "--ask-password=false"
        $RcloneCommandArgs += "--password-command"
        $PasswordCommand = '\"{0}\" \"{1}\"' -f $($RcloneConfigGeneral.RcloneGetPasswordPath.FullName), $($RcloneConfigFileData.CredentialsFilePath)
        $RcloneCommandArgs += $PasswordCommand

        Write-Log -LogLine ("RcloneCommandArgs: >$($RcloneCommandArgs)<") -DebugLevel:$true
        
        try {
        & "$($RcloneConfigGeneral.RcloneProgPath)" @RcloneCommandArgs
        } catch {
                $ExitResult_local=$ExitDefinitions.Rclone
                Write-LogError -LogMessage "Execute rclone config encryption set action." -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                    -WriteToHost:$true
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Log -LogLine "Rclone executed successfully." -WriteToHost:$true
        } else {
            Write-Log -LogLine ("Rclone execution failed with exit code: $LASTEXITCODE") -WriteToHost:$true
        }
    }
}

function Invoke-DecryptConfigAction {
    Write-Log -LogLine ("Action-Decrypt") -WriteToHost:$true
    if (-not $RcloneConfigFileData.IsCredentialsFile) {
        Write-Log -LogLine ("Credentials File is not existing, decryption cannot be applied.") -WriteToHost:$true
    } else {

        $RcloneCommandArgs = @()
        $RcloneCommandArgs += "--config"
        $RcloneCommandArgs += "$RcloneConfigFileName"
        $RcloneCommandArgs += "config"
        $RcloneCommandArgs += "encryption"
        $RcloneCommandArgs += "remove"
        $RcloneCommandArgs += "--ask-password=false"
        $RcloneCommandArgs += "--password-command"
        $PasswordCommand = '\"{0}\" \"{1}\"' -f $($RcloneConfigGeneral.RcloneGetPasswordPath.FullName), $($RcloneConfigFileData.CredentialsFilePath)
        $RcloneCommandArgs += $PasswordCommand

        Write-Log -LogLine ("RcloneCommandArgs: >$($RcloneCommandArgs)<") -DebugLevel:$true

        try {
        & "$($RcloneConfigGeneral.RcloneProgPath)" @RcloneCommandArgs
        } catch {
                $ExitResult_local=$ExitDefinitions.Rclone
                Write-LogError -LogMessage "Execute rclone config encryption remove action." -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                    -WriteToHost:$true
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Log -LogLine "Rclone executed successfully." -WriteToHost:$true
        } else {
            Write-Log -LogLine ("Rclone execution failed with exit code: $LASTEXITCODE") -WriteToHost:$true
        }
    }
}

function Invoke-ConfigAction {
    Write-Log -LogLine ("Action-Config") -WriteToHost:$true

    # Buduje argumenty wywołania rclone version
    $RcloneCommandArgs = @()
    $RcloneCommandArgs += "--config"
    $RcloneCommandArgs += "$RcloneConfigFileName"
    $RcloneCommandArgs += "config"
    $RcloneCommandArgs += "--ask-password=false"
    if ($RcloneConfigFileData.IsCredentialsFile) {
        $RcloneCommandArgs += "--password-command"
        $PasswordCommand = '\"{0}\" \"{1}\"' -f $($RcloneConfigGeneral.RcloneGetPasswordPath.FullName), $($RcloneConfigFileData.CredentialsFilePath)
        $RcloneCommandArgs += $PasswordCommand
    }

    Write-Log -LogLine ("RcloneCommandArgs: >$($RcloneCommandArgs)<") -DebugLevel:$true
    
    try {
    & "$($RcloneConfigGeneral.RcloneProgPath)" @RcloneCommandArgs
    } catch {
            $ExitResult_local=$ExitDefinitions.Rclone
            Write-LogError -LogMessage "Execute rclone config action." -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -WriteToHost:$true
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Log -LogLine "Rclone executed successfully." -WriteToHost:$true
    } else {
        Write-Log -LogLine ("Rclone execution failed with exit code: $LASTEXITCODE") -WriteToHost:$true
    }
}

function Invoke-GuiAction {
    Write-Log -LogLine ("Action-Gui") -WriteToHost:$true
    if (Show-ConfirmationDialog -Title:$BTCommon.ApplicationTitle -Message:"The tool will open a web GUI in your browser and keep running after you close the browser tab. You will need to press Ctrl+C in the terminal to stop the tool. Continue?") {

        # Buduje argumenty wywołania rclone version
        $RcloneCommandArgs = @()
        $RcloneCommandArgs += "--config"
        $RcloneCommandArgs += "$RcloneConfigFileName"
        $RcloneCommandArgs += "gui"
        $RcloneCommandArgs += "--ask-password=false"
        if ($RcloneConfigFileData.IsCredentialsFile) {
            $RcloneCommandArgs += "--password-command"
            $PasswordCommand = '\"{0}\" \"{1}\"' -f $($RcloneConfigGeneral.RcloneGetPasswordPath.FullName), $($RcloneConfigFileData.CredentialsFilePath)
            $RcloneCommandArgs += $PasswordCommand
        }

        Write-Log -LogLine ("RcloneCommandArgs: >$($RcloneCommandArgs)<") -DebugLevel:$true
        
        try {
        & "$($RcloneConfigGeneral.RcloneProgPath)" @RcloneCommandArgs
        } catch {
                $ExitResult_local=$ExitDefinitions.Rclone
                Write-LogError -LogMessage "Execute rclone GUI action." -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                    -WriteToHost:$true
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Log -LogLine "Rclone executed successfully." -WriteToHost:$true
        } else {
            Write-Log -LogLine ("Rclone execution failed with exit code: $LASTEXITCODE") -WriteToHost:$true
        }

    }
}

function Invoke-ViewAction {
    Write-Log -LogLine ("Action-View") -WriteToHost:$true

    more $RcloneConfigFileName

    if ($LASTEXITCODE -eq 0) {
        Write-Log -LogLine "View executed successfully." -WriteToHost:$true
    } else {
        Write-Log -LogLine ("View execution failed with exit code: $LASTEXITCODE") -WriteToHost:$true
    }
}

function Show-Menu {
    Write-Host "Select an option"
    Write-Host "c) Config"
    Write-Host "e) Encrypt"
    Write-Host "d) Decrypt"
    Write-Host "g) Gui"
    Write-Host "v) View"
    Write-Host "q) Quit"
}

function Show-RcloneConfigFileSummary {
    Write-Log -LogLine ("Config directory: $([System.IO.Path]::GetDirectoryName($($RcloneConfigFileData.ConfigFilePath)))") -WriteToHost:$true
    if ($RcloneConfigFileData.ConfigFile.IsEncrypted) {
        Write-Log -LogLine ("Config file: $($RcloneConfigFileData.ConfigFile.FileName) (encrypted)") -WriteToHost:$true -Color Note
    } else {
        Write-Log -LogLine ("Config file: $($RcloneConfigFileData.ConfigFile.FileName) (not encrypted)") -WriteToHost:$true -Color Warning
    }
    if ($RcloneConfigFileData.IsCredentialsFile) {
        Write-Log -LogLine ("Credentials file: $($RcloneConfigFileData.CredentialsFile.FileName) (exists)") -WriteToHost:$true -Color Note
    } else {
        Write-Log -LogLine ("Credentials file: $($RcloneConfigFileData.CredentialsFile.FileName) (does not exist)") -WriteToHost:$true -Color Warning
    }
}

### Main script execution starts here

# Initialize the BT-Rclone-Config environment before proceeding with the main script execution
$null = Initialize-RcloneConfigEnvironment

# Jeżeli podano plik konfiguracyjny, próba jego otwarcia
if (-not ([string]::IsNullOrWhiteSpace($ConfigFile))) {
    $RcloneConfigFileName = $ConfigFile
    Write-Log -LogLine ("Initialize RcloneConfigFileName: >$RcloneConfigFileName<") -DebugLevel:$true
    $RcloneConfigFileData = Initialize-RcloneConfigFile -CRName $RcloneConfigFileName
    if ($null -eq $RcloneConfigFileData) {
        $RcloneConfigFileName = $null
    }
}

# Loop until a valid Rclone configuration file is selected or created, or the user cancels
$StopApp = $False
while (-not $StopApp -and [string]::IsNullOrWhiteSpace($RcloneConfigFileName)) {
    # Obsługa wyboru
    switch (Select-NewOrOpenFile -Title $Script.basename -Prompt "Select BT-Rclone-Config configuration file.") {
        "New" {
            Write-Log -LogLine ("Info: Option New selected") -DebugLevel:$true

            $RcloneConfigFileName = Show-SaveFileDialog `
                -Title "Create new BT-Rclone-Config file" `
                -Filter "Rclone config files (*.$default_rclone_config_extension)|*.$default_rclone_config_extension|All files (*.*)|*.*" `
                -DefaultFileName ($default_rclone_config_prefix)
            if (-not ([string]::IsNullOrWhiteSpace($RcloneConfigFileName))) {
                Write-Log -LogLine ("New RcloneConfigFileName: >$RcloneConfigFileName<") -DebugLevel:$true
                $RcloneConfigFileData = Initialize-RcloneConfigFile -CRName $RcloneConfigFileName -CreateOrOverwrite $true
                if ($null -eq $RcloneConfigFileData) {
                    $RcloneConfigFileName = $null
                }
            } else {
                Write-Log -LogLine ("Info: File New canceled") -DebugLevel:$true
            }

        }
        "Open" {
            Write-Log -LogLine ("Info: Option Open selected") -DebugLevel:$true

            $RcloneConfigFileName = Show-OpenFileDialog `
                -Title "Open BT-Rclone-Config file" `
                -Filter "Rclone config files (*.$default_rclone_config_extension)|*.$default_rclone_config_extension|All files (*.*)|*.*"
            if (-not ([string]::IsNullOrWhiteSpace($RcloneConfigFileName))) {
                Write-Log -LogLine ("Open RcloneConfigFileName: >$RcloneConfigFileName<") -DebugLevel:$true
                $RcloneConfigFileData = Initialize-RcloneConfigFile -CRName $RcloneConfigFileName
                if ($null -eq $RcloneConfigFileData) {
                    $RcloneConfigFileName = $null
                }
            } else {
                Write-Log -LogLine ("Info: File Open canceled") -DebugLevel:$true
            }
        }
        default {
            Write-Log -LogLine ("Info: Ask New/Open canceled") -DebugLevel:$true
            $StopApp = $True
        }
    }
}

# Main application loop
if (-not $StopApp) {
    do {
        $null = Show-RcloneConfigFileSummary
        Write-Log -LogLine ("") -WriteToHost:$true

        Show-Menu
        $choice = Read-Host "c/e/d/g/v/q"
        switch ($choice) {
            "c" { Invoke-ConfigAction }
            "e" { Invoke-EncryptConfigAction }
            "d" { Invoke-DecryptConfigAction }
            "g" { Invoke-GuiAction }
            "v" { Invoke-ViewAction }
            "q" { break }
            default { Write-Host "Invalid option." }
        }
        $null = Update-RcloneConfigFile
        Write-Log -LogLine ("") -WriteToHost:$true
    } while ($choice -ne "q")
}

write-Log -LogLine ("Script completed successfully.") -WriteToHost:$true
return $($ExitDefinitions.Success).Code

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
