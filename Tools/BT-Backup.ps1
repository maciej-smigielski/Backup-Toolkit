<#
.SYNOPSIS
    BT-Backup.ps1 - Narzędzie do tworzenia backupów przy użyciu rclone.

.DESCRIPTION
    Skrypt wykorzystuje rclone do tworzenia i synchronizacji kopii zapasowych.

.PARAMETER ConfigFile
    (Required) Ścieżka do pliku konfiguracyjnego. Musi wskazywać plik konfiguracyjny (*.BT-Backup).

.PARAMETER LogPath
    (Optional) Ścieżka do katalogu logów. Jeżeli nie podany, używany jest domyślny katalog logów.

.PARAMETER ValidateOnly
    (Optional) Przełącznik uruchamiający skrypt w trybie walidacji, nie wykonuje rclone sync i nie wysyła maila.

.PARAMETER DryRun
    (Optional) Przełącznik powoduje wywołanie rclone w trybie dry-run, nie wykonuje faktycznych zmian.

.PARAMETER NoMail
    (Optional) Przełącznik wyłączający wysyłanie maila po wykonaniu backupu.

.PARAMETER FromPlan
    (Optional) Przełącznik wskazujący, że backup został uruchomiony z poziomu planu BT-Plan.
    Wyświetla na output zawartość maila.
    Włącza NoPause.

.PARAMETER NoPause
    (Optional) Przełącznik wyłączający pauzę na końcu wykonania.

.PARAMETER Debug
    (Optional) Włącza tryb debugowania i dodatkowe informacje diagnostyczne.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup
    Uruchamia skrypt w trybie standardowym.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -LogPath C:\Logs
    Uruchamia skrypt w trybie standardowym, z określonym katalogiem logów.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -ValidateOnly
    Uruchamia skrypt w trybie walidacji, nie wykonuje rclone sync i nie wysyła maila.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -DryRun
    Uruchamia rclone w trybie dry-run, nie wykonuje faktycznych zmian.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -NoMail
    Uruchamia skrypt w trybie standardowym, bez wysyłania maila po wykonaniu backupu.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -NoPause
    Uruchamia skrypt w trybie standardowym, bez pauzy na końcu.

.EXAMPLE
    .\BT-Backup.ps1 -ConfigFile config.BT-Backup -Debug
    Uruchamia skrypt w trybie debugowania.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Backup.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-Backup
    [Parameter(Position = 0)]
    [string]$ConfigFile,

    # Katalog logów, jeżeli nie podany, to używa katalogu logs w katalogu pliku konfiguracyjnego
    [Parameter(Position = 1)]
    [string]$LogPath,

    # Opcjonalny przełącznik ValidateOnly, nie wykonuje rclone sync i nie wysyła maila
    [switch]$ValidateOnly,

    # Opcjonalny przełącznik DryRun, uruchamina rclone w trybie dry-run, nie wykonuje faktycznych zmian
    [switch]$DryRun,

    # Opcjonalny przełącznik NoMail, wyłącza wysyłanie maila po wykonaniu backupu
    [switch]$NoMail,

    # Opcjonalny przełącznik FromPlan, wskazujący, że backup został uruchomiony z poziomu planu BT-Plan
    [switch]$FromPlan,

    # Opcjonalny przełącznik NoPause
    [switch]$NoPause
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

# Importuje moduł BT.Common
try {
    Import-Module "$PSScriptRoot\Modules\BT.Common\BT.Common.psd1" -Force -ErrorAction Stop
}
catch {
    throw
}

# Unblock biblioteki PSToml.dll, dla modułu PSToml
try {
    Unblock-File "$PSScriptRoot\Modules\PSToml\bin\net472\PSToml.dll" -ErrorAction Stop
} catch {
    throw
}   

# Importuje moduł PSToml
try {
    Import-Module "$PSScriptRoot\Modules\PSToml\PSToml.psd1" -Force -ErrorAction Stop
} catch {
    throw
}

# Inicjalizacja modułu BT.Common
$null = Initialize-BTCommon -NoPause:($NoPause -or $FromPlan) -DebugMode:$DebugMode

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów
$ExitDefinitions = @{
    Success = @{ Code = 0; Message = "Completed successfully" }                         # Zakończono pomyślnie, w podsumowaniu wartość Message wpisane jawnie
    Unhandled = @{ Code = 1; Message = "Unhandled exception" }                          # Nieobsłużony wyjątek, proces zatrzymany, w write-error wartość Code i Message wpisane jawnie 
    General = @{ Code = 101; Message = "General validation error, process stopped" }    # Ogólny błąd walidacji, proces zatrzymany, nie powstaje plik log
    Param = @{ Code = 102; Message = "Configuration parameter error, process failed" }
    ParamRead = @{ Code = 103; Message = "Unable to read config file, process failed" }
    ParamShow = @{ Code = 104; Message = "Unable to show content of config file, process failed" }
    ParamParse = @{ Code = 105; Message = "Unable to parse config file, process failed" }
    ParamDest = @{ Code = 106; Message = "Destination parameter error, process failed" }
    RcloneConfigCredentials = @{ Code = 106; Message = "Rclone configuration credentials error, process failed" }
    Multiple = @{ Code = 111; Message = "Multiple execution errors" }
    RcloneVersion = @{ Code = 121; Message = "Rclone version check failed" }
    RcloneListing = @{ Code = 122; Message = "Rclone listing failed" }
    RcloneSync = @{ Code = 123; Message = "Rclone execution failed" }
    StatsArchive = @{ Code = 131; Message = "Archive statistics collection failed" }
    StatsRcloneLog = @{ Code = 132; Message = "Rclone log statistics collection failed" }
    MailAttachement = @{ Code = 141; Message = "Mail attachement preparation failed" }
    MailCredentials = @{ Code = 142; Message = "Mail credentials failed" }
    MailSend = @{ Code = 143; Message = "Send mail failed" }
}

# Zbiór kodów wyjścia i komunikatów błędów
$ExitResults = @{}
$ExitResults_displayed = 0

# Domyślne wartości dla katalogów i prefiksów
$default_storage_archive_dir = "archive"        # katalog archiwum, w nim są tworzone podkatalogi dla sesji rclone --backup-dir
$default_storage_current_dir = "current"        # katalog bieżącej kopii zapasowej, rclone dest-path
$default_log_dir = "logs"                       # katalog log, w nim są tworzone pliki log dla sesji skryptu i rclone
$default_storage_archive_prefix = "archive"     # prefix katalogu archiwum dla sesji rclone --backup-dir
$default_rclone_log_prefix = "rclone"           # prefix pliku log rclone dla sesji
$default_script_log_prefix = "BT-Backup"        # prefix pliku log skryptu dla sesji
$default_lock_prefix = "BT-Backup"              # prefix pliku lock dla sesji
$default_config_extension = "BT-Backup"         # rozszerzenie pliku konfiguracyjnego backup
$default_filter_extension = "BT-Filter"         # rozszerzenie pliku konfiguracyjnego filter rclone

# Pobranie aktualnej daty i czasu
$DT = Get-Date
$DTSTR = "$($DT.ToString("yyyy-MM-dd_HH-mm-ss"))"

# Script information
Write-Log -LogLine ("Script.CommandPath: >$($Script.CommandPath)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Script.HomeDir: >$($Script.HomeDir)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Script.Name: >$($Script.Name)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Script.BaseName: >$($Script.BaseName)<") -DebugLevel:$true -WriteToHost:$true

# Versions
Write-Log -LogLine ("Script Version: >$($ScriptVersion)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Module BT.Common Version: >$((Get-Module BT.Common).Version.ToString())<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Module PSToml Version: >$((Get-Module PSToml).Version.ToString())<") -DebugLevel:$true -WriteToHost:$true

# User and current directory information
Write-Log -LogLine ("Env.User: >$($env:USERNAME)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Env.CD: >$((Get-Location).Path)<") -DebugLevel:$true -WriteToHost:$true

# Arguments
Write-Log -LogLine ("Arg.ConfigFile: >$($ConfigFile)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.LogPath: >$($LogPath)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.ValidateOnly: >$($ValidateOnly)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.DryRun: >$($DryRun)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.NoMail: >$($NoMail)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.FromPlan: >$($FromPlan)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.NoPause: >$($NoPause)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.Debug: >$($DebugMode)<") -DebugLevel:$true -WriteToHost:$true

# Sprawdzenie parametrów, plik ConfigFile musi być podany i nie może być pusty
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Parameter Arg.ConfigFile is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# Sprawdzenie istnienia pliku ConfigFile
try {
    $ConfigFilePath = Get-Item $ConfigFile -ErrorAction Stop
} catch {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Check parameter Arg.ConfigFile >$ConfigFile<") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}
Write-Log -LogLine ("ConfigFilePath: >$ConfigFilePath<") -DebugLevel:$true -WriteToHost:$true

# Sprawdzenie czy podana ścieżka do pliku ConfigFile wskazuje na plik (a nie katalog)
if ($ConfigFilePath.PSIsContainer) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Parameter ConfigFilePath >$ConfigFilePath< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# Dane pliku config
$ConfigFileInfo = [PSCustomObject]@{
    # Ścieżka do katalogu w którym jest plik konfiguracyjny
    HomeDir = $ConfigFilePath.DirectoryName
    # Ścieżka do katalogu nadrzędnego w którym jest plik konfiguracyjny
    ParentDir = Split-Path -Path $ConfigFilePath.DirectoryName
    # Nazwa katalogu bazowego w którym jest plik konfiguracyjny
    BaseDir = Split-Path -Path $ConfigFilePath.DirectoryName -Leaf
    # Nazwa pliku konfiguracyjnego bez rozszerzenia
    BaseName = $ConfigFilePath.BaseName
    # Rozszerzenie pliku konfiguracyjnego
    Extension = $ConfigFilePath.Extension
}

# Flagi podsumowujące stan wykonania backup (Archived, Transferred, Deleted, Renamed)
$SummaryFlags = [PSCustomObject]@{
    # Flaga Archived X/N/A
    SummaryFlagArchived = "X"
    # Flaga Transferred X/N/T
    SummaryFlagTransferred = "X"
    # Flaga Deleted X/N/D
    SummaryFlagDeleted = "X"
    # Flaga Renamed X/N/R
    SummaryFlagRenamed = "X"
}

# Wyświetla informacje o pliku config
Write-Log -LogLine ("ConfigFileInfo.HomeDir: >$($ConfigFileInfo.HomeDir)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("ConfigFileInfo.ParentDir: >$($ConfigFileInfo.ParentDir)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("ConfigFileInfo.BaseDir: >$($ConfigFileInfo.BaseDir)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("ConfigFileInfo.BaseName: >$($ConfigFileInfo.BaseName)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("ConfigFileInfo.Extension: >$($ConfigFileInfo.Extension)<") -DebugLevel:$true -WriteToHost:$true

# Sprawdzenie BaseName, nazwa pliku config bez rozszerzenia, nie moze być pusta
if ([string]::IsNullOrWhiteSpace($($ConfigFileInfo.BaseName))) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("BaseName in ConfigFilePath >$ConfigFilePath< is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# Sprawdzenie BaseName, nazwa pliku config nie może zawierać spacji
if ($($ConfigFileInfo.BaseName) -match ' ') {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("BaseName in ConfigFilePath >$ConfigFilePath< cannot contain spaces.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# Sprawdzenie rozszerzenia, musi być równa nazwie skryptu $default_config_extension
# porównanie w wersji uppercase, aby zaakceptować różne wielkości liter
if ($($ConfigFileInfo.Extension).ToUpperInvariant() -ne (("."+$($default_config_extension)).ToUpperInvariant())) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Extension in ConfigFilePath >$ConfigFilePath< must be >.$($default_config_extension)<.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# jeżeli podano katalog logów
if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    # Sprawdza czy istnieje katalog $LogPath
    try {
        $BTCommon.LogDir = Get-Item $LogPath -ErrorAction Stop
    } catch {
        $ExitResult_local=$ExitDefinitions.General
        Write-LogError -LogMessage ("Check parameter Arg.LogPath >$LogPath<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -WriteToHost:$true
        Exit-Pause -ExitCode:$($ExitResult_local.Code)
    }
} else {
    # Sprawdza czy istnieje katalog log
    try {
        $BTCommon.LogDir = Get-Item (Join-Path -Path $($ConfigFileInfo.HomeDir) -ChildPath $default_log_dir) -ErrorAction Stop
    } catch {
        $ExitResult_local=$ExitDefinitions.General
        Write-LogError -LogMessage ("Check $default_log_dir directory") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -WriteToHost:$true
        Exit-Pause -ExitCode:$($ExitResult_local.Code)
    }
}

# Sprawdzenie czy podana ścieżka do katalogu log wskazuje na katalog (a nie plik)
if (-not $BTCommon.LogDir.PSIsContainer) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Parameter BTCommon.LogDir >$($BTCommon.LogDir)< points to a file, not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}

# Tworzy plik log skryptu
try {
    $BTCommon.LogFile = New-Item -Path (Join-Path -Path $BTCommon.LogDir -ErrorAction Stop -ChildPath ($default_script_log_prefix+"_"+$($ConfigFileInfo.BaseName)+"_$DTSTR"+"_$PID"+".log")) -ItemType File -ErrorAction Stop
} catch {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage ("Create BTCommon.LogFile") -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit-Pause -ExitCode:$($ExitResult_local.Code)
}
Write-Log -LogLine ("BTCommon.LogFile: >$($BTCommon.LogFile)<") -DebugLevel:$true -WriteToHost:$true

# Konfiguracja mailowa sesji
$MailConfig = [PSCustomObject]@{
    SendMail = $false                # czy wysyłać mail
    MailTo = ""                      # adres wysyłki mail, obiekt zawierający adresy odbiorców
    MailCredentialsFileData = ""     # mail credentials odczytane z BT-Mail-Credentials
    Subject = ""                     # tytuł maila
    AttachLog = $false               # czy dołączać log do maila
    Attachement = ""                 # załącznik do maila, ścieżka do pliku
}

# Parametry backupu
$ConfigFileParameters = [PSCustomObject]@{
    backup_name = [string]$null                     # nazwa backupu, musi istnieć i być stringiem
    backup_data = [string]$null                     # katalog backup_data, musi istnieć i być stringiem
    backup_data_expanded = [string]$null            # katalog backup_data z rozwiniętymi zmiennymi środowiskowymi
    BackupDataPath = ""                             # katalog backup_data, ustawiane po walidacji
    #
    temp_path = [string]$null                       # katalog tymczasowy, jeżeli istnieje, musi być stringiem
    temp_path_expanded = [string]$null              # katalog tymczasowy z rozwiniętymi zmiennymi środowiskowymi
    lock_path = [string]$null                       # katalog gdzie tworzony jest plik blokady, jeżeli istnieje, musi być stringiem
    lock_path_expanded = [string]$null              # katalog gdzie tworzony jest plik blokady z rozwiniętymi zmiennymi środowiskowymi
    #
    mail_to = [string]$null                         # adres wysyłki mail, jeżeli istnieje, musi być stringiem
    mail_credentials = [string]$null                # plik z danymi uwierzytelniającymi mail, jeżeli istnieje, musi być stringiem
    mail_credentials_expanded = [string]$null       # plik z danymi uwierzytelniającymi mail z rozwiniętymi zmiennymi środowiskowymi
    mail_attach_log = [boolean]$false               # czy dołączać log do maila, jeżeli istnieje, musi być booleanem
    #
    source_system = [string]$null                   # nazwa systemu źródłowego, jeżeli istnieje, musi być stringiem
    source_path = [string]$null                     # katalog źródłowy, jeżeli istnieje, musi być stringiem
    source_path_expanded = [string]$null            # katalog źródłowy z rozwiniętymi zmiennymi środowiskowymi
    source_filter = [boolean]$false                 # czy jest plik filter, jeżeli istnieje, musi być booleanem
    source_renames = [boolean]$false                # czy właczona opcja track renames, jeżeli istnieje, musi być booleanem
    source_iphotos = [boolean]$false                # czy włączona opcja iPhoto, jeżeli istnieje, musi być booleanem
    #
    destination_system = [string]$null              # nazwa systemu na którym znajduje się storage, jeżeli istnieje, musi być stringiem
    destination_storage = [string]$null             # katalog storage, jeżeli istnieje, musi być stringiem
    destination_storage_expanded = [string]$null    # katalog storage z rozwiniętymi zmiennymi środowiskowymi
    destination_posix = [boolean]$true              # czy ścieżki w systemie docelowym są w formacie POSIX (używają /), interpretowany tylko gdy destination_system podany, musi być booleanem
    destination_fc = [boolean]$true                 # wymusza zmianę wielkości liter w nazwach na docelowym, aby pasowały do źródła, włącza parametr rclone --fix-case
    destination_cesd = [boolean]$true               # tworzy na docelowym puste katalogi obecne w źródle, włącza parametr rclone --create-empty-src-dirs
    destination_de = [boolean]$true                 # usuwa z docelowego pliki wykluczone filtrami, włącza parametr rclone --delete-excluded
    #
    rclone_prog = [string]$null = "$PSScriptRoot\Utilities\Rclone\rclone.exe"   # ścieżka do programu rclone, jeżeli istnieje, musi być stringiem
    rclone_prog_expanded = [string]$null            # ścieżka do programu rclone z rozwiniętymi zmiennymi środowiskowymi
    rclone_config = [string]$null                   # plik z konfiguracją rclone, jeżeli istnieje, musi być stringiem
    rclone_config_expanded = [string]$null          # plik z konfiguracją rclone z rozwiniętymi zmiennymi środowiskowymi
    rclone_credentials = [string]$null              # plik z danymi uwierzytelniającymi rclone, jeżeli istnieje, musi być stringiem
    rclone_credentials_expanded = [string]$null     # plik z danymi uwierzytelniającymi rclone z rozwiniętymi zmiennymi środowiskowymi}
}

# Konfiguracja wspólna sesji backupu
$SessionConfig = [PSCustomObject]@{
    RcloneExecuted = $false                 # czy rclone został uruchomiony
    RcloneExecutedSuccesfully = $false      # czy rclone zakończył się pomyślnie
    RcloneProgPath = ""                     # program rclone
    RcloneConfigFile = ""                   # parametr wywołania rclone config
    RcloneConfigPassword = $false           # czy hasło rclone config jest dostępne
    RcloneConfigPlainTextPassword = ""      # hasło rclone config w postaci tekstu, odczytane z pliku credentials
    RcloneLogFile = ""                      # parametr wywołania rclone, log-file, plik log rclone dla tej sesji
    RcloneLogFilePath = $null               # ścieżka do pliku rclone log-file dla tej sesji, ustawiana podczas analizy logu, obiekt System.IO.FileInfo
    RcloneSourcePath = ""                   # parametr wywołania rclone source-path, format source_system:source_path
    RcloneFilterFile = ""                   # parametr wywołania rclone filter-from
    RcloneTrackRenames = $false             # parametr wywołania rclone track-renames
    RcloneServiceiphotos = $false           # parametr wywołania rclone iclouddrive-service photos
    RcloneStoragePath = ""                  # katalog storage, format destination_system:destination_storage, jak puste to przyjmowany lokalny BackupDataPath
    RcloneStorageLocal = $true              # czy storage jest lokalny
    RcloneStoragePOSIX = $false             # czy ścieżki w systemie docelowym są w formacie POSIX (używają /), jeżeli storage lokalny to $false
    RcloneStorageFC = $true                 # wymusza zmianę wielkości liter w nazwach na docelowym, aby pasowały do źródła, włącza parametr rclone --fix-case
    RcloneStorageCESD = $true               # tworzy na docelowym puste katalogi obecne w źródle, włącza parametr rclone --create-empty-src-dirs
    RcloneStorageDE = $true                 # usuwa z docelowego pliki wykluczone filtrami, włącza parametr rclone --delete-excluded
    RcloneStorageCurrentPath = ""           # parametr wywołania rclone dest-path, katalog w którym przechowywane są aktualne dane backup
    RcloneStorageArchivePath = ""           # katalog storage archive w którym są przechowywane dane sesji backup, format destination_system:destination_storage
    RcloneStorageArchiveSessionPath = ""    # parametr wywołania rclone backup-path, katalog storage archive dla tej sesji
}

# Wczytuje i waliduje konfigurację backupu, inicjalizuje raportowanie mailowe
function ProcessParamOrIssue {

    Write-Log -LogLine ("Start backup $($ConfigFileInfo.BaseName)"+": $DTSTR"+"_$PID") -WriteToMail:$true -MailSegment:"Header" -WriteToHost:$true

    # Versions
    Write-Log -LogLine ("Script $($Script.BaseName) Version: >$ScriptVersion<") -WriteToHost:$false
    Write-Log -LogLine ("Module BT.Common Version: >$((Get-Module BT.Common).Version.ToString())<") -WriteToHost:$false
    Write-Log -LogLine ("Module PSToml Version: >$((Get-Module PSToml).Version.ToString())<") -WriteToHost:$false

    # User and current directory information
    Write-Log -LogLine ("Env.User: >$($env:USERNAME)<") -WriteToHost:$false
    Write-Log -LogLine ("Env.CD: >$((Get-Location).Path)<") -WriteToHost:$false

    # Context
    Write-Log -LogLine ("Ctx.ConfigFilePath: >$ConfigFilePath<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.LogDir: >$($BTCommon.LogDir)<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.ValidateOnly: >$ValidateOnly<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.DryRun: >$DryRun<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.NoMail: >$NoMail<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.FromPlan: >$($FromPlan)<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.NoPause: >$($BTCommon.NoPause)<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.DebugMode: >$($BTCommon.DebugMode)<") -WriteToHost:$false

    # Wczytuje parametry konfiguracyjne z pliku ConfigFile w formacie TOML
    try {
        $ConfigFileContent = ConvertFrom-Toml (Get-Content -Encoding UTF8 $ConfigFilePath -Raw)
    } catch {
        $ExitResult_local=$ExitDefinitions.ParamRead
        Write-LogError -LogMessage ("Read content ConfigFilePath >$ConfigFilePath<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Wyświetla zawartość odczytanego pliku ConfigFile w formacie TOML
    $TomlCount = 0
    try {
        (ConvertTo-Toml -Depth 3 -InputObject $ConfigFileContent) -split "`r?`n" | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_)) {
                Write-Log -LogLine ("ConfigFileContent: $_") -WriteToHost:$false -DebugLevel:$true
                $TomlCount++
            }
        }
    }
    catch {
        $ExitResult_local=$ExitDefinitions.ParamShow
        Write-LogError -LogMessage ("Show content ConfigFilePath >$ConfigFilePath<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    Write-Log -LogLine ("ConfigFileContent.count: >$TomlCount<") -WriteToHost:$false -DebugLevel:$true

    ### Waliduje ConfigFileContent i ustawia parametry ConfigFileParameters

    # Walidacja bt-backup, czy istnieje i jest być OrderedDictionary
    if ( (-not ($ConfigFileContent.Contains('bt-backup'))) -or
         ( ($ConfigFileContent['bt-backup'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) ) {
        # ConfigFileParameters.bt-backup: does not exist
        # ConfigFileParameters.bt-backup: exists and is of valid type
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.bt-backup must exists and be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja bt-backup.backup_name, musi istniec i być stringiem
    if ( ($ConfigFileContent['bt-backup'].Contains('backup_name')) -and ($ConfigFileContent['bt-backup']['backup_name'] -is [string]) ) {
        $ConfigFileParameters.backup_name = $ConfigFileContent['bt-backup'].backup_name
        Write-Log -LogLine ("ConfigFileParameters.backup_name: >"+$ConfigFileParameters.backup_name+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.bt-backup.backup_name must exists and be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja bt-backup.backup_data, musi istniec i być stringiem
    if ( ($ConfigFileContent['bt-backup'].Contains('backup_data')) -and ($ConfigFileContent['bt-backup']['backup_data'] -is [string]) ) {
        $ConfigFileParameters.backup_data = $ConfigFileContent['bt-backup'].backup_data
        Write-Log -LogLine ("ConfigFileParameters.backup_data: >"+$ConfigFileParameters.backup_data+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.bt-backup.backup_data must exists and be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja runtime, jeżeli istnieje to musi być OrderedDictionary
    if ($ConfigFileContent.Contains('runtime')) {
        # ConfigFileParameters.runtime: exist
        if ( ($ConfigFileContent['runtime'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) {
            # ConfigFileParameters.runtime: exists and is of valid type
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.runtime if it exists must be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    # Walidacja runtime.temp_path, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('runtime'))) -or (-not ($ConfigFileContent['runtime'].Contains('temp_path'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.temp_path: >"+$ConfigFileParameters.temp_path+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['runtime']['temp_path'] -is [string]) ) {
        $ConfigFileParameters.temp_path = $ConfigFileContent['runtime'].temp_path
        Write-Log -LogLine ("ConfigFileParameters.temp_path: >"+$ConfigFileParameters.temp_path+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.runtime.temp_path if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja runtime.lock_path, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('runtime'))) -or (-not ($ConfigFileContent['runtime'].Contains('lock_path'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.lock_path: >"+$ConfigFileParameters.lock_path+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['runtime']['lock_path'] -is [string]) ) {
        $ConfigFileParameters.lock_path = $ConfigFileContent['runtime'].lock_path
        Write-Log -LogLine ("ConfigFileParameters.lock_path: >"+$ConfigFileParameters.lock_path+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.runtime.lock_path if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja mail, jeżeli istnieje to musi być OrderedDictionary
    if ($ConfigFileContent.Contains('mail')) {
        # ConfigFileParameters.mail: exist
        if ( ($ConfigFileContent['mail'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) {
            # ConfigFileParameters.mail: exists and is of valid type
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.mail if it exists must be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    # Walidacja mail.mail_to, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('mail'))) -or (-not ($ConfigFileContent['mail'].Contains('mail_to'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.mail_to: >"+$ConfigFileParameters.mail_to+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['mail']['mail_to'] -is [string]) ) {
        $ConfigFileParameters.mail_to = $ConfigFileContent['mail'].mail_to
        Write-Log -LogLine ("ConfigFileParameters.mail_to: >"+$ConfigFileParameters.mail_to+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.mail.mail_to if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja mail.mail_credentials, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('mail'))) -or (-not ($ConfigFileContent['mail'].Contains('mail_credentials'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.mail_credentials: >"+$ConfigFileParameters.mail_credentials+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['mail']['mail_credentials'] -is [string]) ) {
        $ConfigFileParameters.mail_credentials = $ConfigFileContent['mail'].mail_credentials
        Write-Log -LogLine ("ConfigFileParameters.mail_credentials: >"+$ConfigFileParameters.mail_credentials+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.mail.mail_credentials if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja mail.mail_attach_log, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('mail'))) -or (-not ($ConfigFileContent['mail'].Contains('mail_attach_log'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.mail_attach_log: >"+$ConfigFileParameters.mail_attach_log+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['mail']['mail_attach_log'] -is [boolean]) ) {
        $ConfigFileParameters.mail_attach_log = $ConfigFileContent['mail'].mail_attach_log
        Write-Log -LogLine ("ConfigFileParameters.mail_attach_log: >"+$ConfigFileParameters.mail_attach_log+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.mail.mail_attach_log if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja source, jeżeli istnieje to musi być OrderedDictionary
    if ($ConfigFileContent.Contains('source')) {
        # ConfigFileParameters.source: exist
        if ( ($ConfigFileContent['source'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) {
            # ConfigFileParameters.source: exists and is of valid type
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.source if it exists must be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    # Walidacja source.source_system, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('source'))) -or (-not ($ConfigFileContent['source'].Contains('source_system'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.source_system: >"+$ConfigFileParameters.source_system+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['source']['source_system'] -is [string]) ) {
        $ConfigFileParameters.source_system = $ConfigFileContent['source'].source_system
        Write-Log -LogLine ("ConfigFileParameters.source_system: >"+$ConfigFileParameters.source_system+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.source.source_system if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja source.source_path, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('source'))) -or (-not ($ConfigFileContent['source'].Contains('source_path'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.source_path: >"+$ConfigFileParameters.source_path+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['source']['source_path'] -is [string]) ) {
        $ConfigFileParameters.source_path = $ConfigFileContent['source'].source_path
        Write-Log -LogLine ("ConfigFileParameters.source_path: >"+$ConfigFileParameters.source_path+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.source.source_path if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja source.source_filter, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('source'))) -or (-not ($ConfigFileContent['source'].Contains('source_filter'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.source_filter: >"+$ConfigFileParameters.source_filter+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['source']['source_filter'] -is [boolean]) ) {
        $ConfigFileParameters.source_filter = $ConfigFileContent['source'].source_filter
        Write-Log -LogLine ("ConfigFileParameters.source_filter: >"+$ConfigFileParameters.source_filter+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.source.source_filter if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja source.source_renames, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('source'))) -or (-not ($ConfigFileContent['source'].Contains('source_renames'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.source_renames: >"+$ConfigFileParameters.source_renames+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['source']['source_renames'] -is [boolean]) ) {
        $ConfigFileParameters.source_renames = $ConfigFileContent['source'].source_renames
        Write-Log -LogLine ("ConfigFileParameters.source_renames: >"+$ConfigFileParameters.source_renames+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.source.source_renames if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja source.source_iphotos, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('source'))) -or (-not ($ConfigFileContent['source'].Contains('source_iphotos'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.source_iphotos: >"+$ConfigFileParameters.source_iphotos+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['source']['source_iphotos'] -is [boolean]) ) {
        $ConfigFileParameters.source_iphotos = $ConfigFileContent['source'].source_iphotos
        Write-Log -LogLine ("ConfigFileParameters.source_iphotos: >"+$ConfigFileParameters.source_iphotos+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.source.source_iphotos if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination, jeżeli istnieje to musi być OrderedDictionary
    if ($ConfigFileContent.Contains('destination')) {
        # ConfigFileParameters.destination: exist
        if ( ($ConfigFileContent['destination'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) {
            # ConfigFileParameters.destination: exists and is of valid type
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.destination if it exists must be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    # Walidacja destination.destination_system, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_system'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_system: >"+$ConfigFileParameters.destination_system+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_system'] -is [string]) ) {
        $ConfigFileParameters.destination_system = $ConfigFileContent['destination'].destination_system
        Write-Log -LogLine ("ConfigFileParameters.destination_system: >"+$ConfigFileParameters.destination_system+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_system if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination.destination_storage, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_storage'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_storage: >"+$ConfigFileParameters.destination_storage+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_storage'] -is [string]) ) {
        $ConfigFileParameters.destination_storage = $ConfigFileContent['destination'].destination_storage
        Write-Log -LogLine ("ConfigFileParameters.destination_storage: >"+$ConfigFileParameters.destination_storage+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_storage if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination.destination_posix, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_posix'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_posix: >"+$ConfigFileParameters.destination_posix+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_posix'] -is [boolean]) ) {
        $ConfigFileParameters.destination_posix = $ConfigFileContent['destination'].destination_posix
        Write-Log -LogLine ("ConfigFileParameters.destination_posix: >"+$ConfigFileParameters.destination_posix+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_posix if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination.destination_fc, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_fc'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_fc: >"+$ConfigFileParameters.destination_fc+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_fc'] -is [boolean]) ) {
        $ConfigFileParameters.destination_fc = $ConfigFileContent['destination'].destination_fc
        Write-Log -LogLine ("ConfigFileParameters.destination_fc: >"+$ConfigFileParameters.destination_fc+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_fc if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination.destination_cesd, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_cesd'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_cesd: >"+$ConfigFileParameters.destination_cesd+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_cesd'] -is [boolean]) ) {
        $ConfigFileParameters.destination_cesd = $ConfigFileContent['destination'].destination_cesd
        Write-Log -LogLine ("ConfigFileParameters.destination_cesd: >"+$ConfigFileParameters.destination_cesd+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_cesd if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja destination.destination_de, jeżeli istnieje, musi być booleanem
    if ( (-not ($ConfigFileContent.Contains('destination'))) -or (-not ($ConfigFileContent['destination'].Contains('destination_de'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.destination_de: >"+$ConfigFileParameters.destination_de+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['destination']['destination_de'] -is [boolean]) ) {
        $ConfigFileParameters.destination_de = $ConfigFileContent['destination'].destination_de
        Write-Log -LogLine ("ConfigFileParameters.destination_de: >"+$ConfigFileParameters.destination_de+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.destination.destination_de if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja rclone, jeżeli istnieje to musi być OrderedDictionary
    if ($ConfigFileContent.Contains('rclone')) {
        # ConfigFileParameters.rclone: exist
        if ( ($ConfigFileContent['rclone'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) {
            # ConfigFileParameters.rclone: exists and is of valid type
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.rclone if it exists must be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    # Walidacja rclone.rclone_prog, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('rclone'))) -or (-not ($ConfigFileContent['rclone'].Contains('rclone_prog'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.rclone_prog: >"+$ConfigFileParameters.rclone_prog+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['rclone']['rclone_prog'] -is [string]) ) {
        $ConfigFileParameters.rclone_prog = $ConfigFileContent['rclone'].rclone_prog
        Write-Log -LogLine ("ConfigFileParameters.rclone_prog: >"+$ConfigFileParameters.rclone_prog+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.rclone.rclone_prog if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    
    # Walidacja rclone.rclone_config, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('rclone'))) -or (-not ($ConfigFileContent['rclone'].Contains('rclone_config'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.rclone_config: >"+$ConfigFileParameters.rclone_config+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['rclone']['rclone_config'] -is [string]) ) {
        $ConfigFileParameters.rclone_config = $ConfigFileContent['rclone'].rclone_config
        Write-Log -LogLine ("ConfigFileParameters.rclone_config: >"+$ConfigFileParameters.rclone_config+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.rclone.rclone_config if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja rclone.rclone_credentials, jeżeli istnieje, musi być stringiem
    if ( (-not ($ConfigFileContent.Contains('rclone'))) -or (-not ($ConfigFileContent['rclone'].Contains('rclone_credentials'))) ) {
        Write-Log -LogLine ("ConfigFileParameters.rclone_credentials: >"+$ConfigFileParameters.rclone_credentials+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['rclone']['rclone_credentials'] -is [string]) ) {
        $ConfigFileParameters.rclone_credentials = $ConfigFileContent['rclone'].rclone_credentials
        Write-Log -LogLine ("ConfigFileParameters.rclone_credentials: >"+$ConfigFileParameters.rclone_credentials+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.rclone.rclone_credentials if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    ### Waliduje ConfigFileParameters i ustawia parametry BTCommon oraz SessionConfig

    # sprawdza czy backup_name jest podana w pliku konfiguracyjnym
    if ([string]::IsNullOrWhiteSpace($ConfigFileParameters.backup_name)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_name is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    
    # sprawdza czy backup_name podana w pliku konfiguracyjnym jest taka sama jak bazowa nazwa pliku konfiguracyjnego
    if ($ConfigFileParameters.backup_name -ne $($ConfigFileInfo.BaseName)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_name >"+$ConfigFileParameters.backup_name+"< not equal ConfigFileInfo.BaseName >"+$($ConfigFileInfo.BaseName)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # sprawdza czy backup_name podana w pliku konfiguracyjnym jest taka sama jak nazwa katalogu w którym jest plik konfiguracyjny
    if ($ConfigFileParameters.backup_name -ne $($ConfigFileInfo.BaseDir)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_name >"+$ConfigFileParameters.backup_name+"< not equal ConfigFileInfo.BaseDir >"+$($ConfigFileInfo.BaseDir)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # sprawdza czy backup_data jest podana w pliku konfiguracyjnym
    if ([string]::IsNullOrWhiteSpace($ConfigFileParameters.backup_data)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_data is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # sprawdza czy backup_data podany w pliku konfiguracyjnym istnieje
    try {
        $ConfigFileParameters.backup_data_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.backup_data)
        Write-Log -LogLine ("ConfigFileParameters.backup_data_expanded: >"+($ConfigFileParameters.backup_data_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
        $ConfigFileParameters.BackupDataPath = Get-Item $ConfigFileParameters.backup_data_expanded -ErrorAction Stop
    } catch {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("Check ConfigFileParameters.backup_data_expanded >"+$ConfigFileParameters.backup_data_expanded+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    Write-Log -LogLine ("ConfigFileParameters.BackupDataPath: >"+($ConfigFileParameters.BackupDataPath)+"<") -WriteToHost:$false

    # sprawdza czy backup_data podany w pliku konfiguracyjnym jest katalogiem
    if (-not $ConfigFileParameters.BackupDataPath.PSIsContainer) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_data_expanded >"+$ConfigFileParameters.backup_data_expanded+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # sprawdza czy backup_data podany w pliku konfiguracyjnym jest taki sam jak ścieżka do katalogu nadrzędnego w którym jest plik konfiguracyjny
    if ($ConfigFileParameters.BackupDataPath.FullName.ToLowerInvariant() -ne $ConfigFileInfo.ParentDir.ToLowerInvariant()) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.backup_data_expanded >"+$ConfigFileParameters.backup_data_expanded+"< not equal ConfigFileInfo.ParentDir >"+$($ConfigFileInfo.ParentDir)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # katalog tymczasowy oraz wartość parametru wywołania rclone temp-dir, cache-dir
    $BTCommon.TempDir = ""
    # jeżeli podane temp_path
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.temp_path))) {
        # czy istnieje temp_path
        try {
            $ConfigFileParameters.temp_path_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.temp_path)
            Write-Log -LogLine ("ConfigFileParameters.temp_path_expanded: >"+($ConfigFileParameters.temp_path_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $BTCommon.TempDir = Get-Item $ConfigFileParameters.temp_path_expanded -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.temp_path_expanded >"+$ConfigFileParameters.temp_path_expanded+"<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy temp_path podany w pliku konfiguracyjnym jest katalogiem
        if (-not $BTCommon.TempDir.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("ConfigFileParameters.temp_path_expanded >"+$ConfigFileParameters.temp_path_expanded+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

    } else {
        $BTCommon.TempDir = $env:TEMP
    }
    Write-Log -LogLine ("BTCommon.TempDir: >"+($BTCommon.TempDir)+"<") -WriteToHost:$false

    # ścieżka do katalogu lock
    $BTCommon.LockDir = ""
    # jeżeli podane lock_path
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.lock_path))) {
        # czy istnieje lock_path
        try {
            $ConfigFileParameters.lock_path_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.lock_path)
            Write-Log -LogLine ("ConfigFileParameters.lock_path_expanded: >"+($ConfigFileParameters.lock_path_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $BTCommon.LockDir = Get-Item $ConfigFileParameters.lock_path_expanded -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.lock_path_expanded >"+$ConfigFileParameters.lock_path_expanded+"<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy lock_path podany w pliku konfiguracyjnym jest katalogiem
        if (-not $BTCommon.LockDir.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("ConfigFileParameters.lock_path_expanded >"+$ConfigFileParameters.lock_path_expanded+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

    } else {
        $BTCommon.LockDir = $($ConfigFileInfo.HomeDir)
    }
    Write-Log -LogLine ("BTCommon.LockDir: >"+($BTCommon.LockDir)+"<") -WriteToHost:$false

    # tworzy pełną ścieżkę do pliku lock, sam lock będzie wykonywany później
    try {
        $BTCommon.LockFile = Join-Path -Path $($BTCommon.LockDir) -ChildPath ("$default_lock_prefix"+"_"+$($ConfigFileInfo.BaseName)+".lock")
    } catch {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("Unable to create session lock file name") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    Write-Log -LogLine ("BTCommon.LockFile: >"+($BTCommon.LockFile)+"<") -WriteToHost:$false

    $MailToEnabled=$false
    # sprawdza mail_to
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.mail_to))) {
        # Adresy oddzielone ;
        $MailConfig.MailTo = $ConfigFileParameters.mail_to -split ';'
        # Usuwa puste wpisy i zbędne spacje
        $MailConfig.MailTo = $MailConfig.MailTo | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        # Wyświeta adresy
        $AddressCount=0
        foreach ($Address in $MailConfig.MailTo) {
            $AddressCount += 1
            Write-Log -LogLine ("MailConfig.MailTo: >$Address<") -WriteToHost:$false -DebugLevel:$true
        }
        # Wyświeta liczbę adresów
        Write-Log -LogLine ("MailConfig.MailTo.Count: >"+$AddressCount+"<") -WriteToHost:$false -DebugLevel:$true
        if ($AddressCount -eq 0) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.mail_to, MailTo.Address.Count is zero.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        # parametry mail To zainicjowany
        $MailToEnabled=$true
    }

    $MailCredentialsEnabled=$false
    # sprawdza mail_credentials
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.mail_credentials))) {
        try {
            $ConfigFileParameters.mail_credentials_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.mail_credentials)
            Write-Log -LogLine ("ConfigFileParameters.mail_credentials_expanded: >"+($ConfigFileParameters.mail_credentials_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $MailConfig.MailCredentialsFileData = Import-Clixml -Path $ConfigFileParameters.mail_credentials_expanded
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Load ConfigFileParameters.mail_credentials_expanded >$($ConfigFileParameters.mail_credentials_expanded)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("MailCredentialsData.From: >$($MailConfig.MailCredentialsFileData.From)<") -WriteToHost:$false -DebugLevel:$true
        Write-Log -LogLine ("MailCredentialsData.smtpServer: >$($MailConfig.MailCredentialsFileData.smtpServer)<") -WriteToHost:$false -DebugLevel:$true
        Write-Log -LogLine ("MailCredentialsData.Port: >$($MailConfig.MailCredentialsFileData.Port)<") -WriteToHost:$false -DebugLevel:$true
        Write-Log -LogLine ("MailCredentialsData.useSSL: >$($MailConfig.MailCredentialsFileData.useSSL)<") -WriteToHost:$false -DebugLevel:$true
        # parametry mail Credentials zainicjowany
        $MailCredentialsEnabled=$true
    }

    # ustawia SendMail
    if ($MailToEnabled -and $MailCredentialsEnabled) {
        $MailConfig.SendMail=$true
    }
    Write-Log -LogLine ("MailConfig.SendMail: >"+$MailConfig.SendMail+"<") -WriteToHost:$false

    # ustawia AttachLog
    $MailConfig.AttachLog = $ConfigFileParameters.mail_attach_log
    Write-Log -LogLine ("MailConfig.AttachLog: >"+$MailConfig.AttachLog+"<") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessParamOrIssue, kod wyjścia $null oznacza brak błędów
}

# Waliduje konfigurację i parametry wywołania rclone
function ProcessParamRcloneOrIssue {

    # parametr wywołania rclone source-path, RcloneSourcePath budowany z source_system i source_path
    $SessionConfig.RcloneSourcePath = ""
    # source_system i source_path nie moga być jednocześnie puste
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.source_system))) {
        $SessionConfig.RcloneSourcePath = $SessionConfig.RcloneSourcePath+($ConfigFileParameters.source_system)+":"
    }
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.source_path))) {
        $ConfigFileParameters.source_path_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.source_path)
        Write-Log -LogLine ("ConfigFileParameters.source_path_expanded: >"+($ConfigFileParameters.source_path_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
        $SessionConfig.RcloneSourcePath = $SessionConfig.RcloneSourcePath+($ConfigFileParameters.source_path_expanded)
    }
    if ($SessionConfig.RcloneSourcePath -eq "") {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.source_system and ConfigFileParameters.source_path are empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    Write-Log -LogLine ("SessionConfig.RcloneSourcePath: >"+($SessionConfig.RcloneSourcePath)+"<") -WriteToHost:$false

    # parametr wywołania rclone filter-from
    $SessionConfig.RcloneFilterFile = ""
    # jeżeli source_filter jest włączone (true)
    if ($ConfigFileParameters.source_filter) {
        # Sprawdzenie istnienia pliku source_filter
        try {
            $SessionConfig.RcloneFilterFile = Get-Item (Join-Path -Path $($ConfigFileInfo.HomeDir) -ChildPath (($($ConfigFileInfo.BaseName))+"."+$default_filter_extension)) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.source_filter >$($ConfigFileParameters.source_filter)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneFilterFile jest plikiem (a nie katalogiem)
        if ($SessionConfig.RcloneFilterFile.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("SessionConfig.RcloneFilterFile >"+($SessionConfig.RcloneFilterFile)+"< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("SessionConfig.RcloneFilterFile: >"+($SessionConfig.RcloneFilterFile)+"<") -WriteToHost:$false

    # parametr wywołania rclone track-renames
    $SessionConfig.RcloneTrackRenames = $ConfigFileParameters.source_renames
    Write-Log -LogLine ("SessionConfig.RcloneTrackRenames: >"+($SessionConfig.RcloneTrackRenames)+"<") -WriteToHost:$false

    # parametr wywołania rclone iclouddrive-service photos
    $SessionConfig.RcloneServiceiphotos = $ConfigFileParameters.source_iphotos
    Write-Log -LogLine ("SessionConfig.RcloneServiceiphotos: >"+($SessionConfig.RcloneServiceiphotos)+"<") -WriteToHost:$false

    # RcloneStoragePath budowany z destination_system i destination_storage
    # informacja: parametry wywołania rclone dest-path oraz backup-path są ustawiane później w ProcessRcloneStorageOrIssue
    $SessionConfig.RcloneStoragePath = ""
    $SessionConfig.RcloneStorageLocal = $true   # domyślnie przyjmujemy, że storage jest lokalny
    $SessionConfig.RcloneStoragePOSIX = $false  # lokalny storage nie używa formatu POSIX
    # destination_system i destination_storage nie moga być jednocześnie puste
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.destination_system))) {
        $SessionConfig.RcloneStoragePath = $SessionConfig.RcloneStoragePath+($ConfigFileParameters.destination_system)+":"
        $SessionConfig.RcloneStorageLocal = $false  # jeżeli podano destination_system to storage nie jest lokalny
        $SessionConfig.RcloneStoragePOSIX = $ConfigFileParameters.destination_posix
    }
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.destination_storage))) {
        $ConfigFileParameters.destination_storage_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.destination_storage)
        Write-Log -LogLine ("ConfigFileParameters.destination_storage_expanded: >"+($ConfigFileParameters.destination_storage_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
        $SessionConfig.RcloneStoragePath = $SessionConfig.RcloneStoragePath+($ConfigFileParameters.destination_storage_expanded)
    }
    # jak nie podano destination_system ani destination_storage, przyjmujemy lokalny BackupDataPath
    if ($SessionConfig.RcloneStoragePath -eq "") {
        $SessionConfig.RcloneStoragePath = $ConfigFileParameters.BackupDataPath     # przyjmujemy lokalny $ConfigFileParameters.BackupDataPath
    }
    Write-Log -LogLine ("SessionConfig.RcloneStoragePath: >"+($SessionConfig.RcloneStoragePath)+"<") -WriteToHost:$false
    Write-Log -LogLine ("SessionConfig.RcloneStorageLocal: >"+($SessionConfig.RcloneStorageLocal)+"<") -WriteToHost:$false
    Write-Log -LogLine ("SessionConfig.RcloneStoragePOSIX: >"+($SessionConfig.RcloneStoragePOSIX)+"<") -WriteToHost:$false

    # parametr wywołania rclone, fix-case
    $SessionConfig.RcloneStorageFC = $ConfigFileParameters.destination_fc
    Write-Log -LogLine ("SessionConfig.RcloneStorageFC: >"+($SessionConfig.RcloneStorageFC)+"<") -WriteToHost:$false

    # parametr wywołania rclone, create-empty-src-dirs
    $SessionConfig.RcloneStorageCESD = $ConfigFileParameters.destination_cesd
    Write-Log -LogLine ("SessionConfig.RcloneStorageCESD: >"+($SessionConfig.RcloneStorageCESD)+"<") -WriteToHost:$false

    # parametr wywołania rclone, delete-excluded
    $SessionConfig.RcloneStorageDE = $ConfigFileParameters.destination_de
    Write-Log -LogLine ("SessionConfig.RcloneStorageDE: >"+($SessionConfig.RcloneStorageDE)+"<") -WriteToHost:$false

    # parametr wywołania rclone, log-file
    $SessionConfig.RcloneLogFile = Join-Path -Path $BTCommon.LogDir -ChildPath ($default_rclone_log_prefix+"_"+$($ConfigFileInfo.BaseName)+"_$DTSTR"+"_$PID"+".log")
    Write-Log -LogLine ("SessionConfig.RcloneLogFile: >"+($SessionConfig.RcloneLogFile)+"<") -WriteToHost:$false

    # Sprawdza czy plik log rclone nie jest taki sam jak log skryptu
    if (($SessionConfig.RcloneLogFile) -eq ($BTCommon.LogFile)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("SessionConfig.RcloneLogFile: >"+($SessionConfig.RcloneLogFile)+"< same as BTCommon.LogFile: >"+($($BTCommon.LogFile))+"<.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    #  program rclone
    $SessionConfig.RcloneProgPath = ""
    # rclone_prog nie może być puste
    if ( [string]::IsNullOrWhiteSpace($ConfigFileParameters.rclone_prog) ) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.rclone_prog is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
     else {
        # czy istnieje rclone_prog
        try {
            $ConfigFileParameters.rclone_prog_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.rclone_prog)
            Write-Log -LogLine ("ConfigFileParameters.rclone_prog_expanded: >"+($ConfigFileParameters.rclone_prog_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $SessionConfig.RcloneProgPath = Get-Item $ConfigFileParameters.rclone_prog_expanded -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.rclone_prog_expanded >$($ConfigFileParameters.rclone_prog_expanded)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneProgPath jest plikiem
        if ($SessionConfig.RcloneProgPath.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("SessionConfig.RcloneProgPath >"+($SessionConfig.RcloneProgPath)+"< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("SessionConfig.RcloneProgPath: >"+($SessionConfig.RcloneProgPath)+"<") -WriteToHost:$false

    #  parametr wywołania rclone config
    $SessionConfig.RcloneConfigFile = ""
    # jeżeli podane rclone_config
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.rclone_config))) {
        # czy istnieje rclone_config
        try {
            $ConfigFileParameters.rclone_config_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.rclone_config)
            Write-Log -LogLine ("ConfigFileParameters.rclone_config_expanded: >"+($ConfigFileParameters.rclone_config_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $SessionConfig.RcloneConfigFile = Get-Item $ConfigFileParameters.rclone_config_expanded -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Check ConfigFileParameters.rclone_config_expanded >$($ConfigFileParameters.rclone_config_expanded)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneConfigFile jest plikiem
        if ($SessionConfig.RcloneConfigFile.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("SessionConfig.RcloneConfigFile >"+($SessionConfig.RcloneConfigFile)+"< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("SessionConfig.RcloneConfigFile: >"+($SessionConfig.RcloneConfigFile)+"<") -WriteToHost:$false

    # credentials rclone
    $SessionConfig.RcloneConfigPassword = $false
    $SessionConfig.RcloneConfigPlainTextPassword = ""
    # jeżeli podane rclone_credentials
    if (-not ([string]::IsNullOrWhiteSpace($ConfigFileParameters.rclone_credentials))) {
        try {
            $ConfigFileParameters.rclone_credentials_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.rclone_credentials)
            Write-Log -LogLine ("ConfigFileParameters.rclone_credentials_expanded: >"+($ConfigFileParameters.rclone_credentials_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $RcloneConfigCredentialsFileData = Import-Clixml -Path $ConfigFileParameters.rclone_credentials_expanded
        } catch {
            $ExitResult_local=$ExitDefinitions.Param
            Write-LogError -LogMessage ("Load ConfigFileParameters.rclone_credentials_expanded >$($ConfigFileParameters.rclone_credentials_expanded)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("RcloneConfigCredentialsFileData.File: >$($RcloneConfigCredentialsFileData.File)<") -WriteToHost:$false -DebugLevel:$true

        # Get rclone config file password
        try {
            # konwersja blob na SecureString
            $RcloneConfigSecurePassword = ConvertTo-SecureString $($RcloneConfigCredentialsFileData.Password) -ErrorAction Stop

            # Konwersja SecureString do PlainText
            $SessionConfig.RcloneConfigPlainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($RcloneConfigSecurePassword)
            )
            $SessionConfig.RcloneConfigPassword = $true

        } catch {
            $ExitResult_local=$ExitDefinitions.RcloneConfigCredentials
            Write-LogError -LogMessage ("Get Rclone Config Password") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("SessionConfig.RcloneConfigPassword: >"+($SessionConfig.RcloneConfigPassword)+"<") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessParamRcloneOrIssue, kod wyjścia $null oznacza brak błędów
}

# Odczytuje wersję rclone
function ProcessRcloneVersionOrIssue {

    # Buduje argumenty wywołania rclone version
    $RcloneCommandArgs = @()
    $RcloneCommandArgs += "--version"

    $RcloneCommandArgs | ForEach-Object { Write-Log -LogLine ("RcloneCommandArgs: $_") -WriteToHost:$false -DebugLevel:$true }

    Write-Log -LogLine ("Execute rclone: $RcloneCommandArgs") -WriteToHost:$false

    # execute rclone
    $RcloneOutput = @()
    try {
        & "$($SessionConfig.RcloneProgPath)" @RcloneCommandArgs 2>&1 | ForEach-Object {
            $RcloneOutput += $_
        }
    } catch {
            if ($RcloneOutput.Count -gt 0) {
                $RcloneOutput | ForEach-Object {
                    Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
                }
            } else {
                    Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
            }

            $ExitResult_local=$ExitDefinitions.RcloneVersion
            Write-LogError -LogMessage ("Execute rclone") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
    }    

    if ($RcloneOutput.Count -gt 0) {
        $RcloneOutput | ForEach-Object {
            Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
        }
    } else {
            Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
    }

    if ($LASTEXITCODE -ne 0) {
        $ExitResult_local=$ExitDefinitions.RcloneVersion
        Write-LogError -LogMessage ("Execute rclone: $LASTEXITCODE") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    if ($RcloneOutput.Count -eq 0) {
        $ExitResult_local=$ExitDefinitions.RcloneVersion
        Write-LogError -LogMessage ("RcloneOutput is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } else {
        $FirstLine = $RcloneOutput | Select-Object -First 1
        if (-not ($FirstLine -match '^rclone v(.*)')) {
            $ExitResult_local=$ExitDefinitions.RcloneVersion
            Write-LogError -LogMessage ("Rclone version not recognized: $FirstLine") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        } else {
            # wyodrębnij wszystko po wzorcu
            $RcloneVersion = $Matches[1].Trim()
            Write-Log -LogLine ("Rclone version: >$RcloneVersion<") -WriteToHost:$false
        }
    }

     return $null   # wyjście z funkcji ProcessRcloneVersionOrIssue, kod wyjścia $null oznacza brak błędów
}

# Pobiera pełną listę plików oraz katalogów przez rclone,
# zwraca listę plików i katalogów zdalnego źródła w formacie JSON,
# w przypadku gdy ścieżka nie istnieje pozostawia $JsonOutput jako $null
function ProcessRcloneListingOrIssue {
    param(
        [string]$RclonePath,
        [Nullable[int]]$MaxDepth = $null,
        [ref]$JsonOutput
    )

    # Buduje argumenty wywołania rclone listing
    $RcloneCommandArgs = @()

    $RcloneCommandArgs += "lsjson"
    if ($RclonePath.EndsWith('\')) {
        $RcloneCommandArgs += "$RclonePath"+'\'
    } else { 
        $RcloneCommandArgs += "$RclonePath"
    }
    $RcloneCommandArgs += "--ask-password=false"
    if (($SessionConfig.RcloneConfigFile) -ne "") {
        $RcloneCommandArgs += "--config"
        $RcloneCommandArgs += "$($SessionConfig.RcloneConfigFile)"
    }
    if (($BTCommon.TempDir) -ne "") {
        $RcloneCommandArgs += "--temp-dir"
        $RcloneCommandArgs += "$($BTCommon.TempDir)"
        $RcloneCommandArgs += "--cache-dir"
        $RcloneCommandArgs += "$($BTCommon.TempDir)"
    }
    $RcloneCommandArgs += "-R"
    if ($null -ne $MaxDepth) {
        $RcloneCommandArgs += "--max-depth"
        $RcloneCommandArgs += "$MaxDepth"
    }

    $RcloneCommandArgs | ForEach-Object { Write-Log -LogLine ("RcloneCommandArgs: $_") -WriteToHost:$false -DebugLevel:$true }

    Write-Log -LogLine ("Execute rclone: $RcloneCommandArgs") -WriteToHost:$false

    # ustawia hasło do rclone config
    if ($SessionConfig.RcloneConfigPassword) {
        $env:RCLONE_CONFIG_PASS = $SessionConfig.RcloneConfigPlainTextPassword
    } else {
        $env:RCLONE_CONFIG_PASS = ""
    }

    # execute rclone
    $RcloneOutput = @()
    try {
        # tymczasowo ustawia ErrorActionPreference na 'Continue' dla obsługi przypadku gdy ścieżka nie istnieje (rclone kod wyjścia 3)
        $PreviousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & "$($SessionConfig.RcloneProgPath)" @RcloneCommandArgs 2>&1 | ForEach-Object {
            $RcloneOutput += $_
        }
    } catch {
            if ($RcloneOutput.Count -gt 0) {
                $RcloneOutput | ForEach-Object {
                    Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
                }
            } else {
                    Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
            }

            $ExitResult_local=$ExitDefinitions.RcloneListing
            Write-LogError -LogMessage ("Execute rclone") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
    } finally {
        # przywraca poprzednią wartość ErrorActionPreference
        $ErrorActionPreference = $PreviousErrorActionPreference
        # czyści hasło do rclone config
        $env:RCLONE_CONFIG_PASS = ""
    }    

    # obsługuje specyficzny błąd rclone, gdy ścieżka nie istnieje (kod wyjścia 3)
    if ($LASTEXITCODE -eq 3) {
            Write-Log -LogLine ("Rclone listing exit code 3: path >$RclonePath< not found.") -WriteToHost:$false -DebugLevel:$true
            return $null
    }

    if ($RcloneOutput.Count -gt 0) {
        $RcloneOutput | ForEach-Object {
            Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
        }
    } else {
            Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
    }

    if ($LASTEXITCODE -ne 0) {
        $ExitResult_local=$ExitDefinitions.RcloneListing
        Write-LogError -LogMessage ("Execute rclone: $LASTEXITCODE") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    if ($RcloneOutput.Count -eq 0) {
        $ExitResult_local=$ExitDefinitions.RcloneListing
        Write-LogError -LogMessage ("RcloneOutput is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } else {
        try {
            $JsonOutputValue = ($RcloneOutput | ForEach-Object { $_.ToString() }) -join "`n"
            $JsonOutput.Value = ConvertFrom-Json -InputObject $JsonOutputValue -ErrorAction Stop
        } catch {
            # handle invalid JSON
            $ExitResult_local=$ExitDefinitions.RcloneListing
            Write-LogError -LogMessage ("Invalid JSON in Rclone output.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

     return $null   # wyjście z funkcji ProcessRcloneListingOrIssue, kod wyjścia $null oznacza brak błędów
}

# Sprawdza storage przez rclone
# parametry wywołania rclone dest-path oraz backup-path
function ProcessRcloneStorageOrIssue {

    # Czy Storage jest lokalny
    if ($SessionConfig.RcloneStorageLocal) {

        # sprawdza czy istnieje katalog RcloneStoragePath, ustawia RcloneStoragePathOnLocal
        try {
            $RcloneStoragePathOnLocal = Get-Item ($SessionConfig.RcloneStoragePath) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("Check RcloneStoragePath directory") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneStoragePathOnLocal jest katalogiem
        if (-not $RcloneStoragePathOnLocal.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("RcloneStoragePathOnLocal >"+($RcloneStoragePathOnLocal)+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("SessionConfig.RcloneStoragePathOnLocal: >"+($RcloneStoragePathOnLocal)+"<") -WriteToHost:$false -DebugLevel:$true

        # sprawdza czy istnieje katalog RcloneStoragePath/backup_name, ustawia RcloneStorageHomePathOnLocal
        try {
            $RcloneStorageHomePathOnLocal = Get-Item ((Join-Path -Path $RcloneStoragePathOnLocal -ChildPath $($ConfigFileInfo.BaseName))) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("Check RcloneStorageHomePath directory") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneStorageHomePathOnLocal jest katalogiem
        if (-not $RcloneStorageHomePathOnLocal.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("RcloneStorageHomePathOnLocal >"+($RcloneStorageHomePathOnLocal)+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("SessionConfig.RcloneStorageHomePathOnLocal: >"+($RcloneStorageHomePathOnLocal)+"<") -WriteToHost:$false -DebugLevel:$true

        # parametr wywołania rclone dest-path
        $SessionConfig.RcloneStorageCurrentPath = ""
        # sprawdza czy istnieje katalog current
        try {
            $SessionConfig.RcloneStorageCurrentPath = Get-Item (Join-Path -Path $($RcloneStorageHomePathOnLocal) -ChildPath $default_storage_current_dir) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("Check $default_storage_current_dir directory") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneStorageCurrentPath jest katalogiem
        if (-not $SessionConfig.RcloneStorageCurrentPath.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("SessionConfig.RcloneStorageCurrentPath >"+($SessionConfig.RcloneStorageCurrentPath)+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("SessionConfig.RcloneStorageCurrentPath: >"+($SessionConfig.RcloneStorageCurrentPath)+"<") -WriteToHost:$false

        # sprawdza czy istnieje katalog archive, ustawia RcloneStorageArchivePath
        try {
            $SessionConfig.RcloneStorageArchivePath = Get-Item (Join-Path -Path $($RcloneStorageHomePathOnLocal) -ChildPath $default_storage_archive_dir) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("Check $default_storage_archive_dir directory") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # sprawdza czy RcloneStorageArchivePath jest katalogiem
        if (-not $SessionConfig.RcloneStorageArchivePath.PSIsContainer) {
            $ExitResult_local=$ExitDefinitions.ParamDest
            Write-LogError -LogMessage ("SessionConfig.RcloneStorageArchivePath >"+($SessionConfig.RcloneStorageArchivePath)+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("SessionConfig.RcloneStorageArchivePath: >"+($SessionConfig.RcloneStorageArchivePath)+"<") -WriteToHost:$false

        # parametr wywołania rclone, backup-path
        $SessionConfig.RcloneStorageArchiveSessionPath = Join-Path -Path $SessionConfig.RcloneStorageArchivePath -ChildPath ("$default_storage_archive_prefix"+"_$DTSTR"+"_$PID")
        Write-Log -LogLine ("SessionConfig.RcloneStorageArchiveSessionPath: >"+($SessionConfig.RcloneStorageArchiveSessionPath)+"<") -WriteToHost:$false

    } else {
        # Dla storage który nie jest lokalny, sprawdza za pomocą rclone czy katalogi istnieją i ustawia odpowiednie ścieżki

        # czy ścieżki w systemie docelowym są w formacie POSIX (używają /)
        if ($SessionConfig.RcloneStoragePOSIX) {
            $SessionConfig.RcloneStorageCurrentPath = $SessionConfig.RcloneStoragePath.TrimEnd('/') + "/" + $($ConfigFileInfo.BaseName) + "/" + $default_storage_current_dir
            $SessionConfig.RcloneStorageArchivePath = $SessionConfig.RcloneStoragePath.TrimEnd('/') + "/" + $($ConfigFileInfo.BaseName) + "/" + $default_storage_archive_dir
            $SessionConfig.RcloneStorageArchiveSessionPath = $SessionConfig.RcloneStorageArchivePath.TrimEnd('/') + "/" + "$default_storage_archive_prefix"+"_$DTSTR"+"_$PID"
        } else {
            $SessionConfig.RcloneStorageCurrentPath = $SessionConfig.RcloneStoragePath.TrimEnd('\') + "\" + $($ConfigFileInfo.BaseName) + "\" + $default_storage_current_dir
            $SessionConfig.RcloneStorageArchivePath = $SessionConfig.RcloneStoragePath.TrimEnd('\') + "\" + $($ConfigFileInfo.BaseName) + "\" + $default_storage_archive_dir
            $SessionConfig.RcloneStorageArchiveSessionPath = $SessionConfig.RcloneStorageArchivePath.TrimEnd('\') + "\" + "$default_storage_archive_prefix"+"_$DTSTR"+"_$PID"
        }

        Write-Log -LogLine ("SessionConfig.RcloneStorageCurrentPath: >"+($SessionConfig.RcloneStorageCurrentPath)+"<") -WriteToHost:$false
        Write-Log -LogLine ("SessionConfig.RcloneStorageArchivePath: >"+($SessionConfig.RcloneStorageArchivePath)+"<") -WriteToHost:$false
        Write-Log -LogLine ("SessionConfig.RcloneStorageArchiveSessionPath: >"+($SessionConfig.RcloneStorageArchiveSessionPath)+"<") -WriteToHost:$false

        # sprawdza czy katalog w systemie docelowym istnieje za pomocą rclone
        $JsonOutput = $null
        $ExitResult_single = ProcessRcloneListingOrIssue -RclonePath $SessionConfig.RcloneStoragePath -MaxDepth 2 -JsonOutput ([ref]$JsonOutput)
        if ($null -ne $ExitResult_single) {
            return $ExitResult_single
        }
        if ($null -eq $JsonOutput) {
                # jak katalog nie istnieje
                $ExitResult_local=$ExitDefinitions.ParamDest
                Write-LogError -LogMessage ("Check RcloneStoragePath >$($SessionConfig.RcloneStoragePath)< directory does not exist.") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
        } else {
            $JsonEntries = @($JsonOutput)

            if ($SessionConfig.RcloneStoragePOSIX) {
                $ExpectedStorageHomePath = $($ConfigFileInfo.BaseName)
                $ExpectedStorageCurrentPath = $($ConfigFileInfo.BaseName) + "/" + $default_storage_current_dir
                $ExpectedStorageArchivePath = $($ConfigFileInfo.BaseName) + "/" + $default_storage_archive_dir
            }
            else {
                $ExpectedStorageHomePath = $($ConfigFileInfo.BaseName)
                $ExpectedStorageCurrentPath = $($ConfigFileInfo.BaseName) + "\" + $default_storage_current_dir
                $ExpectedStorageArchivePath = $($ConfigFileInfo.BaseName) + "\" + $default_storage_archive_dir
            }

            $FountStorageHomePath = $JsonEntries | Where-Object {
                (($_.Path -eq $ExpectedStorageHomePath) -and ($_.IsDir -eq $true))
            } | Select-Object -First 1
            if ($null -eq $FountStorageHomePath) {
                $ExitResult_local=$ExitDefinitions.ParamDest
                Write-LogError -LogMessage ("Check RcloneStoragePath >$($SessionConfig.RcloneStoragePath)< directory >$ExpectedStorageHomePath< does not exist.") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }

            $FountStorageCurrentPath = $JsonEntries | Where-Object {
                (($_.Path -eq $ExpectedStorageCurrentPath) -and ($_.IsDir -eq $true))
            } | Select-Object -First 1
            if ($null -eq $FountStorageCurrentPath) {
                $ExitResult_local=$ExitDefinitions.ParamDest
                Write-LogError -LogMessage ("Check RcloneStoragePath >$($SessionConfig.RcloneStoragePath)< directory >$ExpectedStorageCurrentPath< does not exist.") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }

            $FountStorageArchivePath = $JsonEntries | Where-Object {
                (($_.Path -eq $ExpectedStorageArchivePath) -and ($_.IsDir -eq $true))
            } | Select-Object -First 1
            if ($null -eq $FountStorageArchivePath) {
                $ExitResult_local=$ExitDefinitions.ParamDest
                Write-LogError -LogMessage ("Check RcloneStoragePath >$($SessionConfig.RcloneStoragePath)< directory >$ExpectedStorageArchivePath< does not exist.") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }

        }
    }

    return $null    # wyjście z funkcji ProcessRcloneStorageOrIssue, kod wyjścia $null oznacza brak błędów
}

# Uruchamia synchronizację przez rclone
function ProcessRcloneSyncOrIssue {

    # Buduje argumenty wywołania rclone sync
    $RcloneCommandArgs = @()
    $RcloneCommandArgs += "sync"
    if ($SessionConfig.RcloneSourcePath.EndsWith('\')) {
        $RcloneCommandArgs += "$($SessionConfig.RcloneSourcePath)"+'\'
    } else { 
        $RcloneCommandArgs += "$($SessionConfig.RcloneSourcePath)"
    }
    $RcloneCommandArgs += "$($SessionConfig.RcloneStorageCurrentPath)"
    $RcloneCommandArgs += "--backup-dir"
    $RcloneCommandArgs += "$($SessionConfig.RcloneStorageArchiveSessionPath)"
    $RcloneCommandArgs += "--log-level"
    $RcloneCommandArgs += "INFO"
    $RcloneCommandArgs += "--log-file"
    $RcloneCommandArgs += "$($SessionConfig.RcloneLogFile)"
    $RcloneCommandArgs += "--ask-password=false"
    if (($SessionConfig.RcloneConfigFile) -ne "") {
        $RcloneCommandArgs += "--config"
        $RcloneCommandArgs += "$($SessionConfig.RcloneConfigFile)"
    }
    if (($SessionConfig.RcloneFilterFile) -ne "") {
        $RcloneCommandArgs += "--filter-from"
        $RcloneCommandArgs += "$($SessionConfig.RcloneFilterFile)"
    }
    if (($BTCommon.TempDir) -ne "") {
        $RcloneCommandArgs += "--temp-dir"
        $RcloneCommandArgs += "$($BTCommon.TempDir)"
        $RcloneCommandArgs += "--cache-dir"
        $RcloneCommandArgs += "$($BTCommon.TempDir)"
    }
    if ($SessionConfig.RcloneStorageFC) {
        $RcloneCommandArgs += "--fix-case"
    }
    if ($SessionConfig.RcloneStorageCESD) {
        $RcloneCommandArgs += "--create-empty-src-dirs"
    }
    if ($SessionConfig.RcloneStorageDE) {
        $RcloneCommandArgs += "--delete-excluded"
    }
    if ($SessionConfig.RcloneTrackRenames) {
        $RcloneCommandArgs += "--track-renames"
        $RcloneCommandArgs += "--track-renames-strategy"
        $RcloneCommandArgs += "hash"
    }
    if ($SessionConfig.RcloneServiceiphotos) {
        $RcloneCommandArgs += "--iclouddrive-service"
        $RcloneCommandArgs += "photos"
    }
    if ($DryRun) {
        $RcloneCommandArgs += "--dry-run"
    }

    $RcloneCommandArgs | ForEach-Object { Write-Log -LogLine ("RcloneCommandArgs: $_") -WriteToHost:$false -DebugLevel:$true }

    Write-Log -LogLine ("Execute rclone: $RcloneCommandArgs") -WriteToHost:$false

    # ustawia hasło do rclone config
    if ($SessionConfig.RcloneConfigPassword) {
        $env:RCLONE_CONFIG_PASS = $SessionConfig.RcloneConfigPlainTextPassword
    } else {
        $env:RCLONE_CONFIG_PASS = ""
    }

    # execute rclone
    $RcloneOutput = @()
    try {
        $SessionConfig.RcloneExecuted = $true

        & "$($SessionConfig.RcloneProgPath)" @RcloneCommandArgs 2>&1 | ForEach-Object {
            $RcloneOutput += $_
        }
    } catch {
            if ($RcloneOutput.Count -gt 0) {
                $RcloneOutput | ForEach-Object {
                    Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
                }
            } else {
                    Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
            }

            $ExitResult_local=$ExitDefinitions.RcloneSync
            Write-LogError -LogMessage ("Execute rclone") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
    } finally {
        # czyści hasło do rclone config
        $env:RCLONE_CONFIG_PASS = ""
    }

    if ($RcloneOutput.Count -gt 0) {
        $RcloneOutput | ForEach-Object {
            Write-Log -LogLine ("RcloneOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$true
        }
    } else {
            Write-Log -LogLine ("RcloneOutput is empty") -WriteToHost:$false -DebugLevel:$true
    }

    if ($LASTEXITCODE -ne 0) {
        $ExitResult_local=$ExitDefinitions.RcloneSync
        Write-LogError -LogMessage ("Execute rclone: $LASTEXITCODE") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    $SessionConfig.RcloneExecutedSuccesfully = $true
    Write-Log -LogLine ("Rclone executeed successfully") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessRcloneSyncOrIssue, kod wyjścia $null oznacza brak błędów
}

# Zbiera statystyki archiwum po wykonaniu backupu, w tym liczbę plików, katalogów i całkowity rozmiar danych.
function ProcessStatsArchiveOrIssue {

    if ($SessionConfig.RcloneExecuted) {
        # Czy Storage jest lokalny
        if ($SessionConfig.RcloneStorageLocal) {

            # czy został utworzony katalog backup przez rclone
            if ( (-not ([string]::IsNullOrWhiteSpace($SessionConfig.RcloneStorageArchiveSessionPath))) -and (Test-Path $SessionConfig.RcloneStorageArchiveSessionPath) ) {
                try {
                    # Lista katalogów (z podkatalogami)
                    $Dirs = @(Get-ChildItem -Path $SessionConfig.RcloneStorageArchiveSessionPath -Directory -Recurse -Force -ErrorAction Stop)
                    # Liczba katalogów
                    $DirsCount = $Dirs.Count
                    # Lista plikiów (z podkatalogami)
                    $Files = @(Get-ChildItem -Path $SessionConfig.RcloneStorageArchiveSessionPath -File -Recurse -Force -ErrorAction Stop)
                    # Liczba plików
                    $FilesCount = $Files.Count
                    # Suma rozmiarów w bajtach
                    $TotalBytes = ($Files | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum
                    # formatowanie totalBytes
                    $TotalBytesStr = Format-ByteSizeString -Bytes $TotalBytes
                    # podsumowanie
                    Write-Log -LogLine ("Archive: "+$FilesCount+" (files), "+$DirsCount+" (dirs), "+$TotalBytesStr) -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                } catch {
                    $ExitResult_local=$ExitDefinitions.StatsArchive
                    Write-LogError -LogMessage ("Analyze SessionConfig.RcloneStorageArchiveSessionPath >$($SessionConfig.RcloneStorageArchiveSessionPath)<") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$_ `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }
                $SummaryFlags.SummaryFlagArchived = "A"
            } else {
                Write-Log -LogLine ("Archive summary: There was nothing to archive") -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                $SummaryFlags.SummaryFlagArchived = "N"
            }
        } else {
            # Dla storage który nie jest lokalny, sprawdza za pomocą rclone czy katalogi istnieją i ustawia odpowiednie ścieżki

            # czy został utworzony katalog backup przez rclone
            $JsonOutput = $null
            $ExitResult_single = ProcessRcloneListingOrIssue -RclonePath $SessionConfig.RcloneStorageArchiveSessionPath -JsonOutput ([ref]$JsonOutput)
            if ($null -ne $ExitResult_single) {
                return $ExitResult_single
            }
            if ($null -ne $JsonOutput) {
                try {
                    $JsonEntries = @($JsonOutput)
                    $Files = @($JsonEntries | Where-Object { $_.IsDir -eq $false })
                    $Directories = @($JsonEntries | Where-Object { $_.IsDir -eq $true })
                    $TotalBytes = [long]0
                    for ($i = 0; $i -lt $JsonEntries.Count; $i++) {
                        if ($JsonEntries[$i].IsDir -eq $false) {
                            $TotalBytes += $JsonEntries[$i].Size
                        }
                    }
                    $TotalBytesStr = Format-ByteSizeString -Bytes $TotalBytes
                    # podsumowanie
                    Write-Log -LogLine ("Archive: "+$Files.Count+" (files), "+$Directories.Count+" (dirs), "+$TotalBytesStr) -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                } catch {
                    $ExitResult_local=$ExitDefinitions.StatsArchive
                    Write-LogError -LogMessage ("Analyze SessionConfig.RcloneStorageArchiveSessionPath >$($SessionConfig.RcloneStorageArchiveSessionPath)<") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$_ `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }
                $SummaryFlags.SummaryFlagArchived = "A"
            } else {
                Write-Log -LogLine ("Archive summary: There was nothing to archive") -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                $SummaryFlags.SummaryFlagArchived = "N"
            }
        }
    }

    return $null    # wyjście z funkcji ProcessStatsArchiveOrIssue, kod wyjścia $null oznacza brak błędów
}

# Analizuje log rclone i tworzy podsumowanie operacji.
function ProcessStatsRcloneLogOrIssue {

    if ($SessionConfig.RcloneExecuted) {
        # czy został utworzony plik log przez rclone
        try {
            $SessionConfig.RcloneLogFilePath = Get-Item $SessionConfig.RcloneLogFile -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.StatsRcloneLog
            Write-LogError -LogMessage ("SessionConfig.RcloneLogFile >$($SessionConfig.RcloneLogFile)< not created.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        if (-not ($SessionConfig.RcloneExecutedSuccesfully)) {
            Write-Log -LogLine ("Skip analyze SessionConfig.RcloneLogFile") -WriteToHost:$false
        } else {
            try {
                $lines = @{}
                $max_lines = 12
                $pattern_transferred = "Transferred:.*ETA.*"
                $pattern_nothing = ".*INFO.*:.*There was nothing to transfer"
                $pattern_deleted = "Deleted:*"
                $pattern_renamed = "Renamed:*"
                $pattern_elapsed_time = "Elapsed time:*"

                $found_pattern_transferred_line_no = 0
                $found_pattern_nothing_line_no = 0
                $found_pattern_deleted_line_no = 0
                $found_pattern_renamed_line_no = 0

                # wczytuje linie zawierające statystykę z log
                Get-Content $SessionConfig.RcloneLogFilePath -Tail $max_lines -Encoding UTF8 -ErrorAction Stop | ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace($_)) {
                        return
                    }
                    # usuwa podwójne spacje 
                    $lines[$lines.Count+1] = $_ -replace '\s{2,}', ' '
                }

                # sprawdza czy istnieje transferred, pattern_transferred
                Write-Log -LogLine ("Search pattern pattern_transferred") -WriteToHost:$false -DebugLevel:$true
                ($lines.count)..1 | ForEach-Object {
                    if ($found_pattern_transferred_line_no -eq 0) {
                        if ($lines[$_] -match $pattern_transferred) {
                            $found_pattern_transferred_line_no = $_
                        }
                        Write-Log -LogLine ("SessionConfig.RcloneLogFile.descending_line_no $_"+": "+$($lines[$_])) -WriteToHost:$false -DebugLevel:$true
                    }
                }
                Write-Log -LogLine ("SessionConfig.RcloneLogFile.pattern_transferred_line_no: $found_pattern_transferred_line_no") -WriteToHost:$false -DebugLevel:$true

                if ($found_pattern_transferred_line_no -eq 0) {
                    $ExitResult_local=$ExitDefinitions.StatsRcloneLog
                    Write-LogError -LogMessage ("Analyze SessionConfig.RcloneLogFile >$($SessionConfig.RcloneLogFile)<: Pattern >$pattern_transferred< not found.") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$null `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                } else {
                    # sprawdza czy istnieje nothing to transfer, pattern_nothing
                    Write-Log -LogLine ("Search pattern pattern_nothing") -WriteToHost:$false -DebugLevel:$true
                    $line_no=$found_pattern_transferred_line_no
                    $max_depth = 4
                    $i = 1
                    while ( ($i -le $max_depth) -and (($line_no-$i) -gt 0) -and ($found_pattern_nothing_line_no -eq 0) ) {
                        Write-Log -LogLine ("SessionConfig.RcloneLogFile.descending_line_no "+($line_no-$i)+": "+$($lines[$line_no-$i])) -WriteToHost:$false -DebugLevel:$true
                        if ($lines[$line_no-$i] -match $pattern_nothing) { 
                            $found_pattern_nothing_line_no=$line_no-$i
                        } else {
                            $i += 1
                        }
                    }
                    Write-Log -LogLine ("SessionConfig.RcloneLogFile.pattern_nothing_line_no: $found_pattern_nothing_line_no") -WriteToHost:$false -DebugLevel:$true
                    # wyświetla podsumowanie nothing to transfer, wyświetla gdzy znalazł wzór
                    if ($found_pattern_nothing_line_no -gt 0) {
                        Write-Log -LogLine ("Transfer summary: There was nothing to transfer") -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                        $SummaryFlags.SummaryFlagTransferred = "N"
                    } else {
                        $SummaryFlags.SummaryFlagTransferred = "T"
                    }

                    # sprawdza czy istnieje deleted, pattern_deleted
                    Write-Log -LogLine ("Search pattern pattern_deleted") -WriteToHost:$false -DebugLevel:$true
                    ($lines.count)..$found_pattern_transferred_line_no | ForEach-Object {
                        if ($found_pattern_deleted_line_no -eq 0) {
                            if ($lines[$_] -match $pattern_deleted) {
                                $found_pattern_deleted_line_no = $_
                            }
                            Write-Log -LogLine ("SessionConfig.RcloneLogFile.descending_line_no $_"+": "+$($lines[$_])) -WriteToHost:$false -DebugLevel:$true
                        }
                    }
                    Write-Log -LogLine ("SessionConfig.RcloneLogFile.pattern_deleted_line_no: $found_pattern_deleted_line_no") -WriteToHost:$false -DebugLevel:$true
                    # wyświetla podsumowanie nothing to delete, wyświetla gdzy nie znalazł wzoru
                    if ($found_pattern_deleted_line_no -eq 0) {
                        Write-Log -LogLine ("Delete summary: There was nothing to delete") -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                        $SummaryFlags.SummaryFlagDeleted = "N"
                    } else {
                        $SummaryFlags.SummaryFlagDeleted = "D"
                    }

                    # sprawdza czy istnieje renamed, pattern_renamed
                    Write-Log -LogLine ("Search pattern pattern_renamed") -WriteToHost:$false -DebugLevel:$true
                    ($lines.count)..$found_pattern_transferred_line_no | ForEach-Object {
                        if ($found_pattern_renamed_line_no -eq 0) {
                            if ($lines[$_] -match $pattern_renamed) {
                                $found_pattern_renamed_line_no = $_
                            }
                            Write-Log -LogLine ("SessionConfig.RcloneLogFile.descending_line_no $_"+": "+$($lines[$_])) -WriteToHost:$false -DebugLevel:$true
                        }
                    }
                    Write-Log -LogLine ("SessionConfig.RcloneLogFile.pattern_renamed_line_no: $found_pattern_renamed_line_no") -WriteToHost:$false -DebugLevel:$true
                    # wyświetla podsumowanie nothing to rename, wyświetla gdzy nie znalazł wzoru
                    if ($found_pattern_renamed_line_no -eq 0) {
                        Write-Log -LogLine ("Rename summary: There was nothing to rename") -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                        $SummaryFlags.SummaryFlagRenamed = "N"
                    } else {
                        $SummaryFlags.SummaryFlagRenamed = "R"
                    }

                    # wyświetla podsumowanie transfer, linie z rclone log
                    $found_pattern_transferred_line_no..($lines.count) | ForEach-Object {
                        if ($lines[$_] -notmatch $pattern_elapsed_time) {
                            Write-Log -LogLine ($($lines[$_])) -WriteToMail:$true -MailSegment:"Body" -WriteToHost:$true
                        }
                    }
                }
            } catch {
                $ExitResult_local=$ExitDefinitions.StatsRcloneLog
                Write-LogError -LogMessage ("Analyze SessionConfig.RcloneLogFile >$($SessionConfig.RcloneLogFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }
        }
    }

    return $null    # wyjście z funkcji ProcessStatsRcloneLogOrIssue, kod wyjścia $null oznacza brak błędów
}

# Wysyła raport mailowy.
function ProcessMailOrIssue {

    if ( (-not ($MailConfig.SendMail)) -or ($NoMail) ) {
        Write-Log -LogLine ("Skip Send Mail") -WriteToHost:$false
    } else {

        $Escaped = ""
        $EscapedSummary = ""
        # wyświeta treść maila i napełnia Body
        for ($j = 0; $j -lt $BTCommon.MailBody.count; $j++) {
            Write-Log -LogLine ("BTCommon.MailBody.Line: >"+$($BTCommon.MailBody[$j].Segment)+"< >"+$($BTCommon.MailBody[$j].Line)+"<") -WriteToHost:$false -DebugLevel:$true
            if ($($BTCommon.MailBody[$j].Segment) -in @("Header","Body")) {
                $Escaped += [System.Net.WebUtility]::HtmlEncode($($BTCommon.MailBody[$j].Line))+ '<br>'
            } elseif ($($BTCommon.MailBody[$j].Segment) -in @("Summary")) {
                $EscapedSummary += [System.Net.WebUtility]::HtmlEncode($($BTCommon.MailBody[$j].Line))+ '<br>'
            }
        }

$body = @"
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="UTF-8">
<title>Raport</title>
<style>
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
        font-size: 10pt;
        color: #000000;
        text-align: left;
    }
    p, th, td {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
        font-size: 10pt;
        color: #000000;
        text-align: left;
    }
    pre {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
        font-size: 10pt;
        color: #000000;
        white-space: pre-wrap;
    }
</style>
</head>
<body style="margin:0; padding:8px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; color:#000000; line-height:normal;">
<pre>$Escaped</pre>
<pre><b>$EscapedSummary</b></pre>
</body>
</html>
"@

        # przygotowanie załącznika mail
        if ( ($MailConfig.AttachLog) ) {

            # tworzy katalog tymczasowy dla sesji, jeśli nie został jeszcze utworzony
            if ($null -ne ($rc = CreateSessionTemporaryDir)) {
                return $rc
            }

            try {
                # przygotowuje listę plików do spakowania w archiwum zip
                $ItemsToZip = @()

                # jeżeli istnieje plik log skryptu, dodaje go do załącznika
                if ($null -ne ($BTCommon.LogFile)) {
                    $ItemsToZip += $($BTCommon.LogFile.FullName)
                }

                # jeżeli istnieje plik log rclone, dodaje go do załącznika
                if ($null -ne ($SessionConfig.RcloneLogFilePath)) {
                    $ItemsToZip += $SessionConfig.RcloneLogFilePath.FullName
                }

                # lista plików do spakowania w archiwum zip nie jest pusta, tworzy archiwum zip
                if ($ItemsToZip.Count -gt 0) {
                    $MailConfig.Attachement = join-Path -Path ($BTCommon.ProcessTempDir) -ChildPath ($ConfigFileInfo.BaseName+"_$DTSTR"+"_$PID"+".zip") -ErrorAction Stop
                    Compress-Archive -Path $ItemsToZip -DestinationPath $MailConfig.Attachement -ErrorAction Stop
                }
            } catch {
                $ExitResult_local=$ExitDefinitions.MailAttachement
                Write-LogError -LogMessage ("Prepare mail attachement") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }
        }
        Write-Log -LogLine ("Mail.Attachement: >"+$($MailConfig.Attachement)+"<") -WriteToHost:$false
        Write-Log -LogLine ("Mail.Subject: >"+$($MailConfig.Subject)+"<") -WriteToHost:$false

        # Mail Credentials
        try {
            # konwersja blob na SecureString
            $SecurePassword = ConvertTo-SecureString $($MailConfig.MailCredentialsFileData.Password) -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.MailCredentials
            Write-LogError -LogMessage ("Mail Credentials") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

        # Send Mail
        try {
            # mail credentials
            $credentials = New-Object System.Management.Automation.PSCredential ($($MailConfig.MailCredentialsFileData.From), $SecurePassword) -ErrorAction Stop
            # Kodowanie jako obiekt System.Text.Encoding
            $utf8 = [System.Text.Encoding]::UTF8
            # send mail
            if (-not ([string]::IsNullOrWhiteSpace($MailConfig.Attachement))) {
                # mail z załącznikiem
                Send-MailMessage -From $($MailConfig.MailCredentialsFileData.From) -To $($MailConfig.MailTo) -Subject $($MailConfig.Subject) -Body $body -BodyAsHtml -SmtpServer $($MailConfig.MailCredentialsFileData.smtpServer) -Port $($MailConfig.MailCredentialsFileData.Port) -UseSsl:$($MailConfig.MailCredentialsFileData.useSSL) -Attachments ($MailConfig.Attachement) -Credential $credentials -Encoding $utf8 -ErrorAction Stop
            } else {
                # mail bez załącznika
                Send-MailMessage -From $($MailConfig.MailCredentialsFileData.From) -To $($MailConfig.MailTo) -Subject $($MailConfig.Subject) -Body $body -BodyAsHtml -SmtpServer $($MailConfig.MailCredentialsFileData.smtpServer) -Port $($MailConfig.MailCredentialsFileData.Port) -UseSsl:$($MailConfig.MailCredentialsFileData.useSSL) -Credential $credentials -Encoding $utf8 -ErrorAction Stop
            }
            Write-Log -LogLine ("Mail sent successfully") -WriteToHost:$false
        } catch {
            $ExitResult_local=$ExitDefinitions.MailSend
            Write-LogError -LogMessage ("Send Mail") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

    }

    return $null    # wyjście z funkcji ProcessMailOrIssue, kod wyjścia $null oznacza brak błędów
}

# Wysyła zawartość raportu mailowego na output
function ProcessMailOutputOrIssue {

    if (-not $FromPlan) {
        Write-Log -LogLine ("Skip Mail Output") -WriteToHost:$false -DebugLevel:$true
    } else {

        # dodaje do control records treść maila ze specjalnymi znacznikami
        0..($BTCommon.MailBody.count-1) | ForEach-Object {
            Write-Log -LogLine ("@BODY@"+$($BTCommon.MailBody[$_].Segment)+"@"+$($BTCommon.MailBody[$_].Line)+"@") -WriteToHost:$true -DebugLevel:$false
        }

        # jeżeli istnieje plik log skryptu, dodaje go do control records
        if ( ($null -ne ($BTCommon.LogFile)) ) {
            Write-Log -LogLine ("@ATTACHMENT@"+"BTBACKUP"+"@"+$($BTCommon.LogFile.FullName)+"@") -WriteToHost:$true -DebugLevel:$false
            $ItemsToZip += $($BTCommon.LogFile.FullName)
        }

        # jeżeli istnieje plik log rclone, dodaje go do control records
        if ( ($null -ne ($SessionConfig.RcloneLogFilePath)) ) {
            Write-Log -LogLine ("@ATTACHMENT@"+"RCLONE"+"@"+$($SessionConfig.RcloneLogFilePath.FullName)+"@") -WriteToHost:$true -DebugLevel:$false
            $ItemsToZip += $SessionConfig.RcloneLogFilePath.FullName
        }

        # dodaje do control records flagi podsumowania backupu
        Write-Log -LogLine ("@FLAGS@"+(Get-SummaryFlagsString)+"@") -WriteToHost:$true -DebugLevel:$false
    }

    return $null    # wyjście z funkcji ProcessMailOutputOrIssue, kod wyjścia $null oznacza brak błędów
}

# Zwraca string z informacją o trybie działania skryptu (tylko walidacja, dry run, normalny)
function Get-ModeString {

    if ($ValidateOnly) {
        return "[VALIDATE ONLY] "
    } elseif ($DryRun) {
        return "[DRY RUN] "
    } else {
        return ""
    }
}

# Zwraca string z informacją o flagach podsumowania backup
function Get-SummaryFlagsString {
    # sformowany string z flagami w formacie (ATDR)
    return "($($SummaryFlags.SummaryFlagArchived)$($SummaryFlags.SummaryFlagTransferred)$($SummaryFlags.SummaryFlagDeleted)$($SummaryFlags.SummaryFlagRenamed))"
}

# Podsumowuje wykonanie backupu i ustawia temat maila.
# Obsługuje brak błędów, jeden błąd lub wiele błędów w ExitResults.
# Zwraca liczbę wyświetlonych błędów (0, gdy nie ma błędów), używaną w końcowym podsumowaniu do pominięcia już wyświetlonych błędów.
function Write-BackupSummary {
    $ExitResults_displayed = 0

    if ($ExitResults.count -eq 0) {
        $MailConfig.Subject = (Get-ModeString)+"Successful "+(Get-SummaryFlagsString)+" backup """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        Write-Log -LogLine ((Get-ModeString)+"Backup completed successfully "+(Get-SummaryFlagsString)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    } elseif ($ExitResults.count -eq 1) {
        $MailConfig.Subject = (Get-ModeString)+"Failed "+(Get-SummaryFlagsString)+" backup """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        $ExitResults_displayed = 1
        Write-Log -LogLine ((Get-ModeString)+"Backup failed with Error: "+$($ExitResults[1]).Code+" "+$($ExitResults[1]).Message+" "+(Get-SummaryFlagsString)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    } else {
        $MailConfig.Subject = (Get-ModeString)+"Failed "+(Get-SummaryFlagsString)+" backup """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        1..($ExitResults.count) | ForEach-Object {
            $ExitResults_displayed = $_
            Write-Log -LogLine ("Error: "+$($ExitResults[$ExitResults_displayed]).Code+" "+$($ExitResults[$ExitResults_displayed]).Message) -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
        }
        $ExitResult_local=$ExitDefinitions.Multiple
        Write-Log -LogLine ((Get-ModeString)+"Backup failed with Error: "+$($ExitResult_local.Code)+" "+$ExitResult_local.Message+" ("+$ExitResults.count+")"+" "+(Get-SummaryFlagsString)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    }

    return $ExitResults_displayed
}

# Wyświetla ostateczne podsumowanie backupu po wysłaniu raportu mailowego i usunięciu plików tymczasowych oraz blokady.
# Obsługuje brak błędów, jeden błąd lub wiele błędów w ExitResults i wyświetla pozostałe błędy.
# Zwraca tablicę haszującą z polami Code i Message: Success przy braku błędów, jedyny błąd zapisany w ExitResults lub Multiple przy wielu błędach.
function Write-BackupFinalSummary {
    param (
        [int]$DisplayedErrorCount
    )

    if ($ExitResults.count -eq 0) {
        Write-Log -LogLine ("Finish backup $($ConfigFileInfo.BaseName)"+": Completed successfully") -WriteToMail:$false -WriteToHost:$true
        $ExitResult_final=$ExitDefinitions.Success
    } elseif ($ExitResults.count -eq 1) {
        Write-Log -LogLine ("Finish backup $($ConfigFileInfo.BaseName)"+": Completed with Error: "+$($ExitResults[1]).Code+" "+$($ExitResults[1]).Message) -WriteToMail:$false -WriteToHost:$true
        $ExitResult_final=$ExitResults[1]
    } else {
        if (($DisplayedErrorCount+1) -le ($ExitResults.count)) {
            ($DisplayedErrorCount+1)..($ExitResults.count) | ForEach-Object {
                Write-Log -LogLine ("Error: "+$($ExitResults[$_]).Code+" "+$($ExitResults[$_]).Message) -WriteToMail:$false -WriteToHost:$true
            }
        }
        $ExitResult_final=$ExitDefinitions.Multiple
        Write-Log -LogLine ("Finish backup $($ConfigFileInfo.BaseName)"+": Completed with Error: "+$($ExitResult_final.Code)+" "+$ExitResult_final.Message+" ("+$ExitResults.count+")") -WriteToMail:$false -WriteToHost:$true
    }

    return $ExitResult_final
}

### Main script execution starts here

# Wczytuje i waliduje konfigurację backupu, inicjalizuje raportowanie mailowe
$ExitResult_single = ProcessParamOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Waliduje konfigurację i parametry wywołania rclone
$ExitResult_single = ProcessParamRcloneOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Tworzy plik lock dla tej sesji,
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów
if ($ExitResults.count -eq 0) {
    $ExitResult_single = CreateSessionLockFile -Command $Script.CommandPath
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Odczytuje wersję rclone,
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów
if ($ExitResults.count -eq 0) {
    $ExitResult_single = ProcessRcloneVersionOrIssue
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Sprawdza storage przez rclone,
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów i nie jest to tryb walidacji
if ( ($ExitResults.count -eq 0) -and (-not $ValidateOnly) ) {
    $ExitResult_single = ProcessRcloneStorageOrIssue
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Uruchamia synchronizację przez rclone,
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów i nie jest to tryb walidacji
if ( ($ExitResults.count -eq 0) -and (-not $ValidateOnly) ) {
    $ExitResult_single = ProcessRcloneSyncOrIssue
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Zbiera statystyki archiwum po wykonaniu backupu
$ExitResult_single = ProcessStatsArchiveOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Analizuje log rclone i tworzy podsumowanie operacji
$ExitResult_single = ProcessStatsRcloneLogOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Podsumowanie wykonania backupu oraz ustawia temat maila,
# obsługa przypadków, brak błędów, jeden błąd lub wiele błędów w tablicy ExitResults
$ExitResults_displayed = Write-BackupSummary

# Wysyła raport mailowy,
# wykonuje się tylko wtedy, gdy nie jest to tryb walidacji
if (-not $ValidateOnly) {
    $ExitResult_single = ProcessMailOrIssue
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Czyści katalog i pliki tymczasowe dla tej sesji
$ExitResult_single = RemoveSessionTemporaryDir
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Usuwa plik lock dla tej sesji
$ExitResult_single = RemoveSessionLockFile
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Wysyła raport mailowy na output
$ExitResult_single = ProcessMailOutputOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Ostateczne podsumowanie wykonania backupu po wysłaniu raportu mailowego i czyszczeniu plików tymczasowych,
# obsługa przypadków, brak błędów, jeden błąd lub wiele błędów w tablicy ExitResults. 
$ExitResult_final = Write-BackupFinalSummary -DisplayedErrorCount $ExitResults_displayed

Exit-Pause -ExitCode:$($ExitResult_final.Code)

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
