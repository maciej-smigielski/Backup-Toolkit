<#
.SYNOPSIS
    BT-Plan.ps1 - Narzędzie do uruchamiania planu backupów BT-Backup.

.DESCRIPTION
    Skrypt do automatyzacji wywołań BT-Backup wykorzystującego rclone do tworzenia i synchronizacji kopii zapasowych.

.PARAMETER ConfigFile
    (Required) Ścieżka do pliku konfiguracyjnego. Musi wskazywać plik konfiguracyjny (*.BT-Plan).

.PARAMETER LogPath
    (Optional) Ścieżka do katalogu logów. Jeżeli nie podany, używany jest domyślny katalog logów.

.PARAMETER RunAll
    (Optional) Przełącznik powoduje uruchomienie wszystkich job bez względu na status scheduled.

.PARAMETER RunJob
    (Optional) Nazwa joba (backup_name) do uruchomienia. Uruchamia wyłącznie wskazany job bez względu na status scheduled.
    Ma wyższy priorytet niż przełączniki RunAll, ValidateJobs i DryRun w zakresie selekcji jobów (uruchamia tylko ten jeden wskazany job).

.PARAMETER ValidateOnly
    (Optional) Przełącznik uruchamiający skrypt w trybie walidacji, nie wykonuje BT-Backup i nie wysyła maila.

.PARAMETER ValidateJobs
    (Optional) Przełącznik powoduje wywołanie BT-Backup w trybie validate-only, nie wykonuje rclone sync i nie wysyła maila.
    Uruchamina wszystkie job bez względu na status scheduled.

.PARAMETER DryRun
    (Optional) Przełącznik powoduje wywołanie BT-Backup w trybie dry-run, nie wykonuje faktycznych zmian.
    Uruchamina wszystkie job bez względu na status scheduled.

.PARAMETER NoMail
    (Optional) Przełącznik wyłączający wysyłanie maila po wykonaniu planu backupów.

.PARAMETER NoPause
    (Optional) Przełącznik wyłączający pauzę na końcu wykonania.

.PARAMETER Debug
    (Optional) Włącza tryb debugowania i dodatkowe informacje diagnostyczne.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan
    Uruchamia skrypt w trybie standardowym.
    Uruchamiane są tylko scheduled jobs.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -LogPath C:\Logs
    Uruchamia skrypt w trybie standardowym, z określonym katalogiem logów.
    Uruchamiane są tylko scheduled jobs.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -RunAll
    Uruchamiane są wszystkie job bez względu na status scheduled.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -RunJob backup-test
    Uruchamiany jest tylko job o nazwie backup-test bez względu na status scheduled.
    RunJob ma wyższy priorytet niż RunAll, ValidateJobs i DryRun (uruchamia wyłącznie wskazany job).

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -ValidateOnly
    Uruchamia skrypt w trybie walidacji, nie wykonuje BT-Backup i nie wysyła maila.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -ValidateJobs
    Uruchamia BT-Backup w trybie validate-only, nie wykonuje rclone sync i nie wysyła maila.
    Uruchamina wszystkie job bez względu na status scheduled.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -RunJob backup-test -ValidateJobs
    Uruchamia tylko job o nazwie backup-test w trybie validate-only (RunJob ogranicza wykonanie tylko do tego joba).

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -DryRun
    Uruchamia BT-Backup w trybie dry-run, nie wykonuje faktycznych zmian.
    Uruchamina wszystkie job bez względu na status scheduled.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -RunJob backup-test -DryRun
    Uruchamia tylko job o nazwie backup-test w trybie dry-run (RunJob ogranicza wykonanie tylko do tego joba).

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -NoMail
    Uruchamia skrypt w trybie standardowym, bez wysyłania maila po wykonaniu planu backupów.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -NoPause
    Uruchamia skrypt w trybie standardowym, bez pauzy na końcu.
    Uruchamiane są tylko scheduled jobs.

.EXAMPLE
    .\BT-Plan.ps1 -ConfigFile config.BT-Plan -Debug
    Uruchamia skrypt w trybie debugowania.
    Uruchamiane są tylko scheduled jobs.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Plan.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-Plan
    [Parameter(Position = 0)]
    [string]$ConfigFile,

    # Katalog logów, jeżeli nie podany, to używa katalogu logs w katalogu pliku konfiguracyjnego
    [Parameter(Position = 1)]
    [string]$LogPath,

    # Opcjonalny przełącznik RunAll, uruchamia wszystkie job bez względu na status scheduled
    [switch]$RunAll,

    # Opcjonalny parametr RunJob, uruchamia tylko wskazany job (backup_name) bez względu na status scheduled
    # Ma wyższy priorytet niż przełączniki RunAll, ValidateJobs i DryRun w zakresie selekcji jobów (uruchamia tylko ten jeden wskazany job)
    [string]$RunJob,

    # Opcjonalny przełącznik ValidateOnly, uruchamia skrypt w trybie walidacji, nie wykonuje BT-Backup i nie wysyła maila
    [switch]$ValidateOnly,

    # Opcjonalny przełącznik ValidateJobs, uruchamia BT-Backup w trybie validate-only, nie wykonuje rclone sync i nie wysyła maila
    # Uruchamina wszystkie job bez względu na status scheduled
    [switch]$ValidateJobs,

    # Opcjonalny przełącznik DryRun, uruchamia BT-Backup w trybie dry-run, nie wykonuje faktycznych zmian
    # Uruchamina wszystkie job bez względu na status scheduled
    [switch]$DryRun,

    # Opcjonalny przełącznik NoMail, wyłącza wysyłanie maila po wykonaniu planu backupów
    [switch]$NoMail,

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
$null = Initialize-BTCommon -NoPause:$NoPause -DebugMode:$DebugMode

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów
$ExitDefinitions = @{
    Success = @{ Code = 0; Message = "Completed successfully" }                         # Zakończono pomyślnie, w podsumowaniu wartość Message wpisane jawnie
    Unhandled = @{ Code = 1; Message = "Unhandled exception" }                          # Nieobsłużony wyjątek, proces zatrzymany, w write-error wartość Code i Message wpisane jawnie 
    General = @{ Code = 101; Message = "General validation error, process stopped" }    # Ogólny błąd walidacji, proces zatrzymany, nie powstaje plik log
    Param = @{ Code = 102; Message = "Configuration parameter error, process failed" }
    ParamRead = @{ Code = 103; Message = "Unable to read config file, process failed" }
    ParamShow = @{ Code = 104; Message = "Unable to show content of config file, process failed" }
    ParamParse = @{ Code = 105; Message = "Unable to parse config file, process failed" }
    Multiple = @{ Code = 111; Message = "Multiple execution errors" }
    UnprocessedError = @{ Code = 121; Message = "Backup plan contains unprocessed jobs" }
    DefinitionError = @{ Code = 122; Message = "Backup plan contains improperly defined jobs" }
    ExecutionError = @{ Code = 123; Message = "Backup plan contains jobs that could not be executed" }
    ExitCodeError = @{ Code = 124; Message = "Backup plan completed with failed jobs" }
    ExitCodeControlError = @{ Code = 125; Message = "Backup plan completed with failed jobs and invalid control records" }
    ControlRecordError = @{ Code = 126; Message = "Backup plan completed with successful jobs and invalid control records" }    
    RunJobNotFound = @{ Code = 131; Message = "Specified RunJob not found in backup plan" }
    MailAttachement = @{ Code = 141; Message = "Mail attachement preparation failed" }
    MailCredentials = @{ Code = 142; Message = "Mail credentials failed" }
    MailSend = @{ Code = 143; Message = "Send mail failed" }
}

# Zbiór kodów wyjścia i komunikatów błędów
$ExitResults = @{}
$ExitResults_displayed = 0

# Domyślne wartości dla katalogów i prefiksów
$default_log_dir = "logs"                           # katalog log, w nim są tworzone pliki log dla sesji skryptu i rclone
$default_script_log_prefix = "BT-Plan"              # prefix pliku log skryptu dla sesji
$default_lock_prefix = "BT-Plan"                    # prefix pliku lock dla sesji
$default_config_extension = "BT-Plan"               # rozszerzenie pliku konfiguracyjnego backup plan
$default_backup_config_extension = "BT-Backup"      # rozszerzenie pliku konfiguracyjnego backup

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
Write-Log -LogLine ("Arg.RunAll: >$($RunAll)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.RunJob: >$($RunJob)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.ValidateOnly: >$($ValidateOnly)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.ValidateJobs: >$($ValidateJobs)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.DryRun: >$($DryRun)<") -DebugLevel:$true -WriteToHost:$true
Write-Log -LogLine ("Arg.NoMail: >$($NoMail)<") -DebugLevel:$true -WriteToHost:$true
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

# Dane pliku backup plan config
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

# Flagi podsumowujące stan backup plan
$SummaryFlags = [PSCustomObject]@{
    SuccessJobs = $null
    ScheduledJobs = $null
    ReadyJobs = $null
    DefinedJobs = $null
}

# Wyświetla informacje o pliku backup plan config
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

# Definicje kodów statusów jobów
$JobStatus_NotProcessed = -1
$JobStatus_Success = 0
$JobStatus_Skipped = 1
$JobStatus_Failed_Definition = 2
$JobStatus_Failed_Execution = 3
$JobStatus_Failed_ExitCode = 4
$JobStatus_Failed_ExitCode_ControlRecord = 5
$JobStatus_Failed_Success_ControlRecord = 6

# Teksty statusów jobów, używane do wyświetlania końcowego statusu joba
$JobStatusTexts = @{
    $JobStatus_NotProcessed = "Not Processed"
    $JobStatus_Success = "Success"
    $JobStatus_Skipped = "Skipped"
    $JobStatus_Failed_Definition = "Failed (Definition Error)"
    $JobStatus_Failed_Execution = "Failed (Execution Error)"
    $JobStatus_Failed_ExitCode = "Failed (Exit Code: {0})"
    $JobStatus_Failed_ExitCode_ControlRecord = "Failed (Exit Code: {0}, Invalid Control Record)"
    $JobStatus_Failed_Success_ControlRecord = "Failed (Successful Exit Code, Invalid Control Record)"
}

# Parametry backup planu
$ConfigFileParameters = [PSCustomObject]@{
    plan_name = [string]$null                   # nazwa planu backupu, musi istnieć i być stringiem
    #
    temp_path = [string]$null                   # katalog tymczasowy, jeżeli istnieje, musi być stringiem
    temp_path_expanded = [string]$null          # katalog tymczasowy z rozwiniętymi zmiennymi środowiskowymi
    lock_path = [string]$null                   # katalog gdzie tworzony jest plik blokady, jeżeli istnieje, musi być stringiem
    lock_path_expanded = [string]$null          # katalog gdzie tworzony jest plik blokady z rozwiniętymi zmiennymi środowiskowymi
    #
    mail_to = [string]$null                     # adres wysyłki mail, jeżeli istnieje, musi być stringiem
    mail_credentials = [string]$null            # plik z danymi uwierzytelniającymi mail, jeżeli istnieje, musi być stringiem
    mail_credentials_expanded = [string]$null   # plik z danymi uwierzytelniającymi mail z rozwiniętymi zmiennymi środowiskowymi
    mail_attach_log = [boolean]$false           # czy dołączać log do maila, jeżeli istnieje, musi być booleanem
    #
    job_defaults = [PSCustomObject]@{           # domyślne ustawienia dla wszystkich jobs w planie
        backup_data = [string]$null             # domyślny katalog backup_data dla jobs
        backup_data_expanded = [string]$null    # domyślny katalog backup_data dla jobs z rozwiniętymi zmiennymi środowiskowymi
        run_days = [string]$null                # domyślne dni uruchamiania dla jobs, format "1234567"
        skip_mail = [boolean]$false             # domyślna wartość określająca czy pomijać wysyłkę mail dla jobs
    }
    #
    jobs = @()                                  # lista zadań (jobs) zdefiniowna w tym planie, domyślnie pusta tablica
}

# Pusty obiekt z parametrami domyślnymi dla jobs, używany do inicjalizacji nowych jobs
$ConfigFileParameters_jobs_empty = [PSCustomObject]@{
    backup_name = [string]$null                 # nazwa backupu
    backup_data = [string]$null                 # katalog backup_data, wartość domyślna pobierana z job_defaults
    backup_data_expanded = [string]$null        # katalog backup_data po rozwinięciu zmiennych środowiskowych
    BackupDataPath = ""                         # katalog backup_data, ustawiane po walidacji
    BackupConfigPath = ""                       # ścieżka do konfiguracji backupu, ustawiane po walidacji
    run_days = [string]$null                    # dni uruchomienia backupu, wartość domyślna pobierana z job_defaults
    skip_mail = [boolean]$false                 # pomijanie wysyłki maila po zakończeniu backupu, wartość domyślna pobierana z job_defaults
    #
    JobReady = $false                           # czy backup jest gotowy do uruchomienia, ustawiane po walidacji
    JobScheduled = $false                       # czy backup jest zaplanowany na dzisiaj (dany dzień tygodnia), ustawiane po walidacji
    #
    JobFinalStatus = $JobStatus_NotProcessed    # końcowy status joba, może przyjmować wartości z $JobStatusTexts
    JobExitCode = $null                         # kod wyjścia BT-Backupu
    JobMailBody = @{}                           # zawiera treść maila do wysłania, ustawiane przez output BT-Backup, odczytana z control records
    JobSummaryFlags = ""                        # flagi podsumowujące stan wykonania backup BT-Backup, odczytane z control records
    JobBTBackupLogFilePath = $null              # ścieżka do pliku BT-Backup log-file, odczytana z control records, obiekt System.IO.FileInfo
    JobRcloneLogFilePath = $null                # ścieżka do pliku rclone log-file, odczytana z control records, obiekt System.IO.FileInfo
}

# Wczytuje i waliduje konfigurację backup planu, inicjalizuje raportowanie mailowe
function ProcessParamOrIssue {

    Write-Log -LogLine ("Start backup plan $($ConfigFileInfo.BaseName)"+": $DTSTR"+"_$PID") -WriteToMail:$true -MailSegment:"Header" -WriteToHost:$true

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
    Write-Log -LogLine ("Ctx.RunAll: >$($RunAll)<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.RunJob: >$($RunJob)<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.ValidateOnly: >$ValidateOnly<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.ValidateJobs: >$ValidateJobs<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.DryRun: >$DryRun<") -WriteToHost:$false
    Write-Log -LogLine ("Ctx.NoMail: >$NoMail<") -WriteToHost:$false
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

    # Walidacja bt-plan, czy istnieje i jest być OrderedDictionary
    if ( (-not ($ConfigFileContent.Contains('bt-plan'))) -or
         ( ($ConfigFileContent['bt-plan'] -is [System.Collections.Specialized.OrderedDictionary]) -eq $false ) ) {
        # ConfigFileParameters.bt-plan: does not exist
        # ConfigFileParameters.bt-plan: exists and is of valid type
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.bt-plan must exists and be an OrderedDictionary.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja bt-plan.plan_name, musi istniec i być stringiem
    if ( ($ConfigFileContent['bt-plan'].Contains('plan_name')) -and ($ConfigFileContent['bt-plan']['plan_name'] -is [string]) ) {
        $ConfigFileParameters.plan_name = $ConfigFileContent['bt-plan'].plan_name
        Write-Log -LogLine ("ConfigFileParameters.plan_name: >"+$ConfigFileParameters.plan_name+"<") -WriteToHost:$false
    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.bt-plan.plan_name must exists and be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
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

    # Walidacja job_defaults, jeżeli istnieje, musi być OrderedDictionary
    if (-not ($ConfigFileContent.Contains('job_defaults'))) {
        # ConfigFileParameters.job_defaults: does not exist
        Write-Log -LogLine ("ConfigFileParameters.job_defaults.backup_data: >"+$ConfigFileParameters.job_defaults.backup_data+"< (Default)") -WriteToHost:$false
        Write-Log -LogLine ("ConfigFileParameters.job_defaults.run_days: >"+$ConfigFileParameters.job_defaults.run_days+"< (Default)") -WriteToHost:$false
        Write-Log -LogLine ("ConfigFileParameters.job_defaults.skip_mail: >"+$ConfigFileParameters.job_defaults.skip_mail+"< (Default)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['job_defaults'] -is [System.Collections.Specialized.OrderedDictionary]) ) {
        # ConfigFileParameters.job_defaults: exists and is of valid type
        
        # Walidacja job_defaults.backup_data, jeżeli istnieje, musi być stringiem
        if (-not (($ConfigFileContent['job_defaults'].Contains('backup_data')))) {
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.backup_data: >"+$ConfigFileParameters.job_defaults.backup_data+"< (Default)") -WriteToHost:$false
        } elseif ( ($ConfigFileContent['job_defaults']['backup_data'] -is [string]) ) {
            $ConfigFileParameters.job_defaults.backup_data = $ConfigFileContent['job_defaults']['backup_data']
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.backup_data: >"+$ConfigFileParameters.job_defaults.backup_data+"<") -WriteToHost:$false
        } else {
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.job_defaults.backup_data if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        
        # Walidacja job_defaults.run_days, jeżeli istnieje, musi być stringiem
        if (-not (($ConfigFileContent['job_defaults'].Contains('run_days')))) {
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.run_days: >"+$ConfigFileParameters.job_defaults.run_days+"< (Default)") -WriteToHost:$false
        } elseif ( ($ConfigFileContent['job_defaults']['run_days'] -is [string]) ) {
            $ConfigFileParameters.job_defaults.run_days = $ConfigFileContent['job_defaults']['run_days']
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.run_days: >"+$ConfigFileParameters.job_defaults.run_days+"<") -WriteToHost:$false
        } else {
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.job_defaults.run_days if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        
        # Walidacja job_defaults.skip_mail, jeżeli istnieje, musi być booleanem
        if (-not (($ConfigFileContent['job_defaults'].Contains('skip_mail')))) {
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.skip_mail: >"+$ConfigFileParameters.job_defaults.skip_mail+"< (Default)") -WriteToHost:$false
        } elseif ( ($ConfigFileContent['job_defaults']['skip_mail'] -is [boolean]) ) {
            $ConfigFileParameters.job_defaults.skip_mail = $ConfigFileContent['job_defaults']['skip_mail']
            Write-Log -LogLine ("ConfigFileParameters.job_defaults.skip_mail: >"+$ConfigFileParameters.job_defaults.skip_mail+"<") -WriteToHost:$false
        } else {
            $ExitResult_local=$ExitDefinitions.ParamParse
            Write-LogError -LogMessage ("ConfigFileContent.job_defaults.skip_mail if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }

    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.job_defaults if it exists must be an OrderedDictionary but is of type >"+($ConfigFileContent['job_defaults'].GetType().Name)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # Walidacja sekcji jobs, jeżeli istnieje, musi być tablicą OrderedDictionary
    if (-not ($ConfigFileContent.Contains('jobs'))) {
        # ConfigFileParameters.jobs: does not exist
        Write-Log -LogLine ("ConfigFileParameters.jobs.count: >"+$ConfigFileParameters.jobs.count+"< (No jobs defined)") -WriteToHost:$false
    } elseif ( ($ConfigFileContent['jobs'] -is [array]) -and ( -not ( $ConfigFileContent['jobs'] | Where-Object { $_ -isnot [System.Collections.Specialized.OrderedDictionary] } ) ) ) {
        # tablice w PowerShell są typu Object[]/System.Array, więc trzeba sprawdzić typ każdego elementu z osobna,
        # nie da się bezpośrednio sprawdzić typu tablicy jako [System.Collections.Specialized.OrderedDictionary[]]
        # ConfigFileParameters.jobs: exists and is of valid type

        # Iteracja po wszystkich zadaniach w sekcji jobs w ConfigFileContent
        for ($i = 0; $i -lt $ConfigFileContent['jobs'].count; $i++) {
            if ( ($ConfigFileContent['jobs'][$i] -is [System.Collections.Specialized.OrderedDictionary]) ) {
                $ConfigFileParameters.jobs += ,($ConfigFileParameters_jobs_empty.PSObject.Copy())
                $ConfigFileParameters.jobs[$i].JobMailBody = ($ConfigFileParameters_jobs_empty.JobMailBody.PSObject.Copy())
                $ConfigFileParameters.jobs[$i].backup_data = [string]$null = $ConfigFileParameters.job_defaults.backup_data
                $ConfigFileParameters.jobs[$i].run_days = [string]$null = $ConfigFileParameters.job_defaults.run_days
                $ConfigFileParameters.jobs[$i].skip_mail = [boolean]$false = $ConfigFileParameters.job_defaults.skip_mail

                Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"]") -WriteToHost:$false

                # Walidacja jobs[i].backup_name, jeżeli istnieje, musi być stringiem
                if (-not (($ConfigFileContent['jobs'][$i].Contains('backup_name')))) {
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].backup_name: >"+$ConfigFileParameters.jobs[$i].backup_name+"< (Default)") -WriteToHost:$false
                } elseif ( ($ConfigFileContent['jobs'][$i]['backup_name'] -is [string]) ) {
                    $ConfigFileParameters.jobs[$i].backup_name = $($ConfigFileContent['jobs'][$i]['backup_name'])
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].backup_name: >"+$ConfigFileParameters.jobs[$i].backup_name+"<") -WriteToHost:$false
                } else {
                    $ExitResult_local=$ExitDefinitions.ParamParse
                    Write-LogError -LogMessage ("ConfigFileContent.jobs["+ $($i+1) +"].backup_name if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$null `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }

                # Walidacja jobs[i].backup_data, jeżeli istnieje, musi być stringiem
                if (-not (($ConfigFileContent['jobs'][$i].Contains('backup_data')))) {
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].backup_data: >"+$ConfigFileParameters.jobs[$i].backup_data+"< (Default)") -WriteToHost:$false
                } elseif ( ($ConfigFileContent['jobs'][$i]['backup_data'] -is [string]) ) {
                    $ConfigFileParameters.jobs[$i].backup_data = $($ConfigFileContent['jobs'][$i]['backup_data'])
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].backup_data: >"+$ConfigFileParameters.jobs[$i].backup_data+"<") -WriteToHost:$false
                } else {
                    $ExitResult_local=$ExitDefinitions.ParamParse
                    Write-LogError -LogMessage ("ConfigFileContent.jobs["+ $($i+1) +"].backup_data if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$null `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }

                # Walidacja jobs[i].run_days, jeżeli istnieje, musi być stringiem
                if (-not (($ConfigFileContent['jobs'][$i].Contains('run_days')))) {
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].run_days: >"+$ConfigFileParameters.jobs[$i].run_days+"< (Default)") -WriteToHost:$false
                } elseif ( ($ConfigFileContent['jobs'][$i]['run_days'] -is [string]) ) {
                    $ConfigFileParameters.jobs[$i].run_days = $($ConfigFileContent['jobs'][$i]['run_days'])
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].run_days: >"+$ConfigFileParameters.jobs[$i].run_days+"<") -WriteToHost:$false
                } else {
                    $ExitResult_local=$ExitDefinitions.ParamParse
                    Write-LogError -LogMessage ("ConfigFileContent.jobs["+ $($i+1) +"].run_days if it exists must be a string.") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$null `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }

                # Walidacja jobs[i].skip_mail, jeżeli istnieje, musi być booleanem
                if (-not (($ConfigFileContent['jobs'][$i].Contains('skip_mail')))) {
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].skip_mail: >"+$ConfigFileParameters.jobs[$i].skip_mail+"< (Default)") -WriteToHost:$false
                } elseif ( ($ConfigFileContent['jobs'][$i]['skip_mail'] -is [boolean]) ) {
                    $ConfigFileParameters.jobs[$i].skip_mail = $($ConfigFileContent['jobs'][$i]['skip_mail'])
                    Write-Log -LogLine ("ConfigFileParameters.jobs["+ $($i+1) +"].skip_mail: >"+$ConfigFileParameters.jobs[$i].skip_mail+"<") -WriteToHost:$false
                } else {
                    $ExitResult_local=$ExitDefinitions.ParamParse
                    Write-LogError -LogMessage ("ConfigFileContent.jobs["+ $($i+1) +"].skip_mail if it exists must be a boolean.") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$null `
                        -ExitResult:$ExitResult_local `
                        -WriteToHost:$true
                    return $ExitResult_local
                }

            } else {
                $ExitResult_local=$ExitDefinitions.ParamParse
                Write-LogError -LogMessage ("ConfigFileContent.jobs["+ $($i+1) +"] if it exists must be an OrderedDictionary but is of type >"+($ConfigFileContent['jobs'][$i].GetType().Name)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }
        }

        # Inicjalizacja licznika podsumowania DefinedJobs
        $SummaryFlags.DefinedJobs = $ConfigFileParameters.jobs.count
        Write-Log -LogLine ("SummaryFlags.DefinedJobs: >"+$SummaryFlags.DefinedJobs+"<") -WriteToHost:$false

    } else {
        $ExitResult_local=$ExitDefinitions.ParamParse
        Write-LogError -LogMessage ("ConfigFileContent.jobs if it exists must be an OrderedDictionary[] but is of type >"+($ConfigFileContent['jobs'].GetType().Name)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    ### Waliduje ConfigFileParameters i ustawia parametry BTCommon oraz SessionConfig

    # sprawdza czy plan_name jest podana w pliku konfiguracyjnym
    if ([string]::IsNullOrWhiteSpace($ConfigFileParameters.plan_name)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.plan_name is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }
    
    # sprawdza czy plan_name podana w pliku konfiguracyjnym jest taka sama jak bazowa nazwa pliku konfiguracyjnego
    if ($ConfigFileParameters.plan_name -ne $($ConfigFileInfo.BaseName)) {
        $ExitResult_local=$ExitDefinitions.Param
        Write-LogError -LogMessage ("ConfigFileParameters.plan_name >"+$ConfigFileParameters.plan_name+"< not equal ConfigFileInfo.BaseName >"+$($ConfigFileInfo.BaseName)+"<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    # katalog tymczasowy
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

    # jeżeli podane mail_attach_log
    if ($ConfigFileParameters.mail_attach_log) {
            $MailConfig.AttachLog = $ConfigFileParameters.mail_attach_log
    }
        Write-Log -LogLine ("MailConfig.AttachLog: >"+$MailConfig.AttachLog+"<") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessParamOrIssue, kod wyjścia $null oznacza brak błędów
}

# Waliduje konfigurację backup jobs
function ProcessParamJobs {

    # Obliczanie numeru dnia tygodnia w formacie ISO (1 = poniedziałek, 7 = niedziela)
    $isoWeekDay = [int]$DT.DayOfWeek
    if ($isoWeekDay -eq 0) { $isoWeekDay = 7 }
    Write-Log -LogLine ("ISO week day number: >$isoWeekDay<") -WriteToHost:$false

    # Walidacja jobs, iteracja po wszystkich zadaniach w sekcji jobs w pliku ConfigFileParameters
    for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {

        # Spradzanie backup_name w backup jobs
        if ([string]::IsNullOrWhiteSpace($ConfigFileParameters.jobs[$i].backup_name)) {
            Write-LogError -LogMessage ("ConfigFileParameters.jobs[$($i+1)].backup_name is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -WriteToHost:$true
            continue
        }

        # Spradzanie backup_data w backup jobs
        if ([string]::IsNullOrWhiteSpace($ConfigFileParameters.jobs[$i].backup_data)) {
            Write-LogError -LogMessage ("ConfigFileParameters.jobs[$($i+1)].backup_data is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -WriteToHost:$true
            continue
        }

        # sprawdza czy backup_data w backup jobs istnieje
        try {
            $ConfigFileParameters.jobs[$i].backup_data_expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigFileParameters.jobs[$i].backup_data)
            Write-Log -LogLine ("ConfigFileParameters.jobs[$($i+1)].backup_data_expanded: >"+($ConfigFileParameters.jobs[$i].backup_data_expanded)+"<") -WriteToHost:$false -DebugLevel:$true
            $ConfigFileParameters.jobs[$i].BackupDataPath = Get-Item $ConfigFileParameters.jobs[$i].backup_data_expanded -ErrorAction Stop
        } catch {
            Write-LogError -LogMessage ("Check ConfigFileParameters.jobs[$($i+1)].backup_data_expanded >"+$ConfigFileParameters.jobs[$i].backup_data_expanded+"<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -WriteToHost:$true
            continue
        }
        Write-Log -LogLine ("ConfigFileParameters.jobs[$($i+1)].BackupDataPath: >"+($ConfigFileParameters.jobs[$i].BackupDataPath)+"<") -WriteToHost:$false

        # sprawdza czy backup_data w backup jobs jest katalogiem
        if (-not $ConfigFileParameters.jobs[$i].BackupDataPath.PSIsContainer) {
            Write-LogError -LogMessage ("ConfigFileParameters.jobs[$($i+1)].BackupDataPath >"+$ConfigFileParameters.jobs[$i].BackupDataPath+"< is not a directory.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -WriteToHost:$true
            continue
        }

        # sprawdza czy istnieje plik konfiguracyjny BT-Backup
        try {
            $ConfigFileParameters.jobs[$i].BackupConfigPath = Get-Item (Join-Path (Join-Path $ConfigFileParameters.jobs[$i].BackupDataPath $ConfigFileParameters.jobs[$i].backup_name) $($ConfigFileParameters.jobs[$i].backup_name+"."+$default_backup_config_extension)) -ErrorAction Stop
        } catch {
            Write-LogError -LogMessage ("Check ConfigFileParameters.jobs[$($i+1)].backup_name >"+$ConfigFileParameters.jobs[$i].backup_name+"<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -WriteToHost:$true
            continue
        }
        Write-Log -LogLine ("ConfigFileParameters.jobs[$($i+1)].BackupConfigPath: >"+($ConfigFileParameters.jobs[$i].BackupConfigPath)+"<") -WriteToHost:$false

        # sprawdza czy backup_data w backup jobs jest plikiem (a nie katalogiem)
        if ($ConfigFileParameters.jobs[$i].BackupConfigPath.PSIsContainer) {
            Write-LogError -LogMessage ("ConfigFileParameters.jobs[$($i+1)].BackupConfigPath >"+$ConfigFileParameters.jobs[$i].BackupConfigPath+"< points to a directory, not a file.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -WriteToHost:$true
            continue
        }

        # sprawdza run_days
        if (-not ( ($ConfigFileParameters.jobs[$i].run_days -eq "") -or ($ConfigFileParameters.jobs[$i].run_days -match '^(?=.+)1?2?3?4?5?6?7?$') ) ) {
            Write-LogError -LogMessage ("ConfigFileParameters.jobs[$($i+1)].run_days >"+$ConfigFileParameters.jobs[$i].run_days+"< has invalid format.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -WriteToHost:$true
            continue
        }

        # oznacza, że job przeszedł walidację i jest gotowy do uruchomienia
        $ConfigFileParameters.jobs[$i].JobReady = $true
        Write-Log -LogLine ("ConfigFileParameters.jobs[$($i+1)].JobReady: >"+($ConfigFileParameters.jobs[$i].JobReady)+"<") -WriteToHost:$false

        # sprawdza czy backup jest zaplanowany na dany dzień tygodnia
        if ($ConfigFileParameters.jobs[$i].run_days -match [regex]::Escape($isoWeekDay.ToString())) {
            $ConfigFileParameters.jobs[$i].JobScheduled = $true
        }
        Write-Log -LogLine ("ConfigFileParameters.jobs[$($i+1)].JobScheduled: >"+($ConfigFileParameters.jobs[$i].JobScheduled)+"<") -WriteToHost:$false

    }

    # Inicjalizacja liczników podsumowania ReadyJobs, ScheduledJobs
    # Ustawia JobFinalStatus dla błędów definicji (JobReady = $false)
    $SummaryFlags.ReadyJobs = 0
    $SummaryFlags.ScheduledJobs = 0
    # Walidacja jobs, iteracja po wszystkich zadaniach w sekcji jobs w pliku ConfigFileParameters
    for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {
        if ($ConfigFileParameters.jobs[$i].JobReady) {
            $SummaryFlags.ReadyJobs += 1
            if ($ConfigFileParameters.jobs[$i].JobScheduled) {
                $SummaryFlags.ScheduledJobs += 1
            }
        } else {
            $ConfigFileParameters.jobs[$i].JobFinalStatus = $JobStatus_Failed_Definition
        }
    }
    Write-Log -LogLine ("SummaryFlags.ReadyJobs: >"+$SummaryFlags.ReadyJobs+"<") -WriteToHost:$false
    Write-Log -LogLine ("SummaryFlags.ScheduledJobs: >"+$SummaryFlags.ScheduledJobs+"<") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessParamJobs, kod wyjścia $null oznacza brak błędów
}

# Uruchamia bt-backup
function ProcessBTBackupOrIssue {
    param(
        [int]$JobId
    )

    Write-Log -LogLine ("Start Job >$JobId<") -WriteToHost:$false

    # Buduje argumenty wywołania BT-Backup
    $BTBackupCommandArgs = @()
    $BTBackupCommandArgs += "-ExecutionPolicy"
    $BTBackupCommandArgs += "Bypass"
    $BTBackupCommandArgs += "-NonInteractive"
    $BTBackupCommandArgs += "-file"
    $BTBackupCommandArgs += "$PSScriptRoot\BT-Backup.ps1"
    $BTBackupCommandArgs += "$($ConfigFileParameters.jobs[$JobId].BackupConfigPath)"
    $BTBackupCommandArgs += "-FromPlan"
    if ($ValidateJobs) {
        $BTBackupCommandArgs += "-ValidateOnly"
    } elseif ($DryRun) {
        $BTBackupCommandArgs += "-DryRun"
    }
    if ($ConfigFileParameters.jobs[$JobId].skip_mail) {
        $BTBackupCommandArgs += "-NoMail"
    }

    $BTBackupCommandArgs | ForEach-Object { Write-Log -LogLine ("Job "+($JobId+1)+": "+"BTBackupCommandArgs: $_") -WriteToHost:$false -DebugLevel:$true }

    Write-Log -LogLine ("Job "+($JobId+1)+": "+"Execute BT-Backup: $BTBackupCommandArgs") -WriteToHost:$false

    # execute BT-Backup
    $BTBackupOutput = @()
    try {
        & "powershell.exe" @BTBackupCommandArgs 2>&1 | ForEach-Object {
            $BTBackupOutput += $_
        }
    } catch {
            if ($BTBackupOutput.Count -gt 0) {
                $BTBackupOutput | ForEach-Object {
                    Write-Log -LogLine ("Job "+($JobId+1)+": "+"BTBackupOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$false
                }
            } else {
                    Write-Log -LogLine ("Job "+($JobId+1)+": "+"BTBackupOutput is empty") -WriteToHost:$false -DebugLevel:$false
            }

            $ConfigFileParameters.jobs[$JobId].JobFinalStatus = $JobStatus_Failed_Execution
            Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("Execute BT-Backup") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -WriteToHost:$true
            return $ConfigFileParameters.jobs[$JobId].JobFinalStatus
    }

    # Flaga wskazująca, czy wystąpił problem z analizą Control Record w outputu BT-Backup
    $AnalyzeControlRecordProblem = $false

    # Ile znalazł wystąpień @FLAGS@ w outputcie BT-Backup
    $JobSummaryFlagsCount = 0

    # Ile znalazł wystąpień @ATTACHMENT@BTBACKUP@ w outputcie BT-Backup
    $JobBTBackupLogFileCount = 0
    # Zmienna robocza do odczytu ścieżki pliku log BT-Backup
    $JobBTBackupLogFile = ""

    # Ile znalazł wystąpień @ATTACHMENT@RCLONE@ w outputcie BT-Backup
    $JobRcloneLogFileCount = 0
    # Zmienna robocza do odczytu ścieżki pliku log Rclone
    $JobRcloneLogFile = ""

    if ($BTBackupOutput.Count -gt 0) {
        $BTBackupOutput | ForEach-Object {
            Write-Log -LogLine ("Job "+($JobId+1)+": "+"BTBackupOutput "+$(if ($_ -is [System.Management.Automation.ErrorRecord]) { "stderr:" } else { "stdout:" })+" $_") -WriteToHost:$false -DebugLevel:$false

            # Ustawia flagę JobSummaryFlags oraz buduje linie do maila w JobMailBody na podstawie output z BT-Backup
            # Normalne linie z outputu są przekazywane na output
            $MessageText = [string]$_
            $IsSpecialLine = $MessageText -match '^@[A-Za-z0-9]+@.*@$'
            if ($IsSpecialLine) {
                $IsFlagsLine = $MessageText -match '^@FLAGS@(\([A-Za-z]{4}\))@$'
                $IsBTBackupLogLine = $MessageText -match '^@ATTACHMENT@BTBACKUP@.*@$'
                $IsRcloneLogLine = $MessageText -match '^@ATTACHMENT@RCLONE@.*@$'
                $IsBodyLine = $MessageText -match '^@BODY@(.*)@(.*)@$'
                if ($IsFlagsLine) {
                    # Ustawia flagę JobSummaryFlags na podstawie linii z outputu
                    $JobSummaryFlagsCount++
                    $MessageArray = $MessageText -split '@'
                    $ConfigFileParameters.jobs[$JobId].JobSummaryFlags = $MessageArray[2]
                    Write-Log -LogLine ("Job "+($JobId+1)+": JobSummaryFlags >"+$($ConfigFileParameters.jobs[$JobId].JobSummaryFlags)+"<") -WriteToHost:$false -DebugLevel:$true
                } elseif ($IsBTBackupLogLine) {
                    # Ustawia JobBTBackupLogFile na podstawie linii z outputu
                    $JobBTBackupLogFileCount++
                    $MessageArray = $MessageText -split '@'
                    $JobBTBackupLogFile = $MessageArray[3]
                    Write-Log -LogLine ("Job "+($JobId+1)+": JobBTBackupLogFile >"+$($JobBTBackupLogFile)+"<") -WriteToHost:$false -DebugLevel:$true
                } elseif ($IsRcloneLogLine) {
                    # Ustawia JobRcloneLogFile na podstawie linii z outputu
                    $JobRcloneLogFileCount++
                    $MessageArray = $MessageText -split '@'
                    $JobRcloneLogFile = $MessageArray[3]
                    Write-Log -LogLine ("Job "+($JobId+1)+": JobRcloneLogFile >"+$($JobRcloneLogFile)+"<") -WriteToHost:$false -DebugLevel:$true
                } elseif ($IsBodyLine) {
                        # Dodaje linię do raportu mailowego na podstawie linii z outputu
                        $MessageArray = $MessageText -split '@'
                        $ConfigFileParameters.jobs[$JobId].JobMailBody[$ConfigFileParameters.jobs[$JobId].JobMailBody.Count] = [PSCustomObject]@{
                            Segment = $MessageArray[2]
                            Line    = $MessageArray[3]
                        }
                        Write-Log -LogLine ("Job "+($JobId+1)+": JobMailBody >"+"<"+$($ConfigFileParameters.jobs[$JobId].JobMailBody[$ConfigFileParameters.jobs[$JobId].JobMailBody.Count-1].Segment)+"< >"+$($ConfigFileParameters.jobs[$JobId].JobMailBody[$ConfigFileParameters.jobs[$JobId].JobMailBody.Count-1].Line)+"<") -WriteToHost:$false -DebugLevel:$true
                }        
            } else {
                # Wyświetla output z BT-Backup, nie zapisuje do logu bo informacja już została zapisana powyżej
                # nie zapisuje do logu bo informacja już została zapisana powyżej                    
                Write-Log -LogLine ("  "+$MessageText) -WriteToLog:$false -WriteToHost:$true -DebugLevel:$false
            }
        }
    } else {
            Write-Log -LogLine ("Job "+($JobId+1)+": "+"BTBackupOutput is empty") -WriteToHost:$false -DebugLevel:$false
    }

    if ($JobSummaryFlagsCount -ne 1) {
        $AnalyzeControlRecordProblem = $true
        Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("JobSummaryFlagsCount <$JobSummaryFlagsCount> is not equal to 1") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -WriteToHost:$true
    }    

    if ($JobBTBackupLogFileCount -gt 1) {
        $AnalyzeControlRecordProblem = $true
        Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("JobBTBackupLogFileCount <$JobBTBackupLogFileCount> is greater than 1") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -WriteToHost:$true
    } elseif ($JobBTBackupLogFileCount -eq 1) {
        try {
            $ConfigFileParameters.jobs[$JobId].JobBTBackupLogFilePath = Get-Item $JobBTBackupLogFile -ErrorAction Stop
        } catch {
            $AnalyzeControlRecordProblem = $true
            Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("Check JobBTBackupLogFile <$JobBTBackupLogFile>") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -WriteToHost:$true
        }
    }
    write-Log -LogLine ("Job "+($JobId+1)+": "+"JobBTBackupLogFilePath <$($ConfigFileParameters.jobs[$JobId].JobBTBackupLogFilePath)>") -WriteToHost:$false -DebugLevel:$true

    if ($JobRcloneLogFileCount -gt 1) {
        $AnalyzeControlRecordProblem = $true
        Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("JobRcloneLogFileCount <$JobRcloneLogFileCount> is greater than 1") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -WriteToHost:$true
    } elseif ($JobRcloneLogFileCount -eq 1) {
        try {
            $ConfigFileParameters.jobs[$JobId].JobRcloneLogFilePath = Get-Item $JobRcloneLogFile -ErrorAction Stop
        } catch {
            $AnalyzeControlRecordProblem = $true
            Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("Check JobRcloneLogFile <$JobRcloneLogFile>") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -WriteToHost:$true
        }
    }
    write-Log -LogLine ("Job "+($JobId+1)+": "+"JobRcloneLogFilePath <$($ConfigFileParameters.jobs[$JobId].JobRcloneLogFilePath)>") -WriteToHost:$false -DebugLevel:$true

    $ConfigFileParameters.jobs[$JobId].JobExitCode = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0) {
        if ($AnalyzeControlRecordProblem) {
            $ConfigFileParameters.jobs[$JobId].JobFinalStatus = $JobStatus_Failed_ExitCode_ControlRecord
        } else {
            $ConfigFileParameters.jobs[$JobId].JobFinalStatus = $JobStatus_Failed_ExitCode
        }
        Write-LogError -LogMessagePrefix ("Job "+($JobId+1)+": ") -LogMessage ("Execute BT-Backup: $LASTEXITCODE") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -WriteToHost:$true
        return $ConfigFileParameters.jobs[$JobId].JobFinalStatus
    }

    if ($AnalyzeControlRecordProblem) {
        $ConfigFileParameters.jobs[$JobId].JobFinalStatus = $JobStatus_Failed_Success_ControlRecord
    } else {
        $ConfigFileParameters.jobs[$JobId].JobFinalStatus = $JobStatus_Success
    }
    Write-Log -LogLine ("Job "+($JobId+1)+": "+"BT-Backup executeed successfully") -WriteToHost:$false

    return $null    # wyjście z funkcji ProcessBTBackupOrIssue, kod wyjścia $null oznacza brak błędów
}

# Uruchamia backup joby startujące bt-backup i wyświetla status jobów
function ProcessBackupJobs {

    if (-not $ValidateOnly) {
        # Inicjalizacja licznika podsumowania SuccessJobs
        $SummaryFlags.SuccessJobs = 0
    }

    for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {

        if (-not $ValidateOnly) {
            # Przetwarza job tylko gdy jego status jest NotProcessed, jak jest inny to oznacza że posiada juz błąd lub finalny status
            if ( ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_NotProcessed) ) {
                $ShouldRun = if (-not [string]::IsNullOrWhiteSpace($RunJob)) {
                    $ConfigFileParameters.jobs[$i].backup_name -eq $RunJob
                } else {
                    ($ConfigFileParameters.jobs[$i].JobScheduled) -or $ValidateJobs -or $DryRun -or $RunAll
                }

                if (-not $ShouldRun) {
                    $ConfigFileParameters.jobs[$i].JobFinalStatus = $JobStatus_Skipped
                } else {
                    $Result_ProcessBTBackupOrIssue = ProcessBTBackupOrIssue -JobId $i
                    if ($null -eq $Result_ProcessBTBackupOrIssue) {
                        # Job zakończył się sukcesem
                        $SummaryFlags.SuccessJobs++
                    } 
                }
            }
        }

        # Wyświetla status joba
        $JobScheduledText = if ($ConfigFileParameters.jobs[$i].JobScheduled) { "Yes" } else { "No" }
        Write-Log -LogLine ("Job "+($i+1)+": "+$ConfigFileParameters.jobs[$i].backup_name+" (Scheduled: "+$JobScheduledText+") Status: "+$($JobStatusTexts[$ConfigFileParameters.jobs[$i].JobFinalStatus] -f $ConfigFileParameters.jobs[$i].JobExitCode)+" "+$ConfigFileParameters.jobs[$i].JobSummaryFlags) -WriteToMail:$false -WriteToHost:$true
    }

    if (-not $ValidateOnly) {
        # Finalnie policzona wartość SuccessJobs
        Write-Log -LogLine ("SummaryFlags.SuccessJobs: >"+$SummaryFlags.SuccessJobs+"<") -WriteToHost:$false
    }

    return $null    # wyjście z funkcji ProcessBackupJobs, kod wyjścia $null oznacza brak błędów
}

# Gerenuje kody błędów dla job na podstawie ich statusu
function ProcessResolveJobStatuses {

    $Found_JobStatus_NotProcessed = 0
    $Found_JobStatus_Failed_Definition = 0
    $Found_JobStatus_Failed_Execution = 0
    $Found_JobStatus_Failed_ExitCode = 0
    $Found_JobStatus_Failed_ExitCode_ControlRecord = 0
    $Found_JobStatus_Failed_Success_ControlRecord = 0

    # Sprawdzenie, czy którykolwiek job ma status Falied lub NotProcessed i ustawienie flagi
    for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {
        # Nie traktuje jako problem jobów ze statusem NotProcessed, jeżeli włączony validate only,
        # tryb validate only z założenia pomija uruchomienie jobów
        if ( ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_NotProcessed) -and (-not $ValidateOnly) ) {
            $Found_JobStatus_NotProcessed++
        }
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Failed_Definition) {
            $Found_JobStatus_Failed_Definition++
        }
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Failed_Execution) {
            $Found_JobStatus_Failed_Execution++
        }
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Failed_ExitCode) {
            $Found_JobStatus_Failed_ExitCode++
        }
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Failed_ExitCode_ControlRecord) {
            $Found_JobStatus_Failed_ExitCode_ControlRecord++
        }
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Failed_Success_ControlRecord) {
            $Found_JobStatus_Failed_Success_ControlRecord++
        }
    }

    if ($Found_JobStatus_NotProcessed -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.UnprocessedError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_NotProcessed") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }

    if ($Found_JobStatus_Failed_Definition -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.DefinitionError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_Failed_Definition") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }

     if ($Found_JobStatus_Failed_Execution -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.ExecutionError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_Failed_Execution") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }

    if ($Found_JobStatus_Failed_ExitCode -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.ExitCodeError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_Failed_ExitCode") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }
    
    if ($Found_JobStatus_Failed_ExitCode_ControlRecord -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.ExitCodeControlError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_Failed_ExitCode_ControlRecord") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }

    if ($Found_JobStatus_Failed_Success_ControlRecord -gt 0) {
        $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.ControlRecordError
        Write-LogError -LogMessage ("Jobs Count: $Found_JobStatus_Failed_Success_ControlRecord") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
            -WriteToHost:$true
    }
 
    # Sprawdzenie czy job wskazany w RunJob istnieje w planie
    if (-not [string]::IsNullOrWhiteSpace($RunJob)) {
        $MatchingJob = $ConfigFileParameters.jobs | Where-Object { $_.backup_name -eq $RunJob }
        if (-not $MatchingJob) {
            $ExitResults[$ExitResults.Count+1] = $ExitDefinitions.RunJobNotFound
            Write-LogError -LogMessage ("Parameter Arg.RunJob is set, job with backup_name >$RunJob< not found in backup plan.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$($ExitResults[$ExitResults.Count]) -IncludeErrorMessage:$true `
                -WriteToHost:$true
        }
    }
   
    return $null    # wyjście z funkcji ProcessResolveJobStatuses, kod wyjścia $null oznacza brak błędów
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
        # procentowe szerokości kolumn w raporcie mailowym
        $ColumnsWidthPercent = @(3, 17, 7, 12, 7, 54)

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
<div style="height:10pt; line-height:10pt;">&nbsp;</div>
<pre><b>$EscapedSummary</b></pre>
<div style="height:10pt; line-height:10pt;">&nbsp;</div>
<table role="presentation" border="0" cellspacing="0" cellpadding="0" width="800" style="border-collapse:collapse; width:800px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt;">
    <tr>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[0])%; border:1px solid #000000; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Job</th>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[1])%; border:1px solid #000000; border-left:0; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Backup name</th>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[2])%; border:1px solid #000000; border-left:0; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Sched.</th>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[3])%; border:1px solid #000000; border-left:0; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Status</th>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[4])%; border:1px solid #000000; border-left:0; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Flags</th>
        <th align="left" valign="top" style="width:$($ColumnsWidthPercent[5])%; border:1px solid #000000; border-left:0; padding:0 7px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; font-size:10pt; font-weight:normal; line-height:normal;">Log Summary</th>
    </tr>
"@

    for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {

        # Przygotowuje zmienne do kolumn tabeli HTML
        $JobNo = $i + 1
        $JobBackupName = $ConfigFileParameters.jobs[$i].backup_name
        $JobScheduledText = if ($ConfigFileParameters.jobs[$i].JobScheduled) { "Yes" } else { "No" }
        $JobStatusEscaped = [System.Net.WebUtility]::HtmlEncode($JobStatusTexts[$ConfigFileParameters.jobs[$i].JobFinalStatus] -f $ConfigFileParameters.jobs[$i].JobExitCode)
        if ($ConfigFileParameters.jobs[$i].JobFinalStatus -eq $JobStatus_Success) {
            $JobStatusEscaped = '<span style="color:#00A800;">' + $JobStatusEscaped + '</span>'
        } elseif ($ConfigFileParameters.jobs[$i].JobFinalStatus -ne $JobStatus_Skipped) {
            $JobStatusEscaped = '<span style="color:#FF0000;">' + $JobStatusEscaped + '</span>'
        }
        $JobFlags = $ConfigFileParameters.jobs[$i].JobSummaryFlags
        if ((-not [string]::IsNullOrWhiteSpace($JobFlags)) -and ($JobFlags -cnotmatch '^\([XN]{4}\)$')) {
            $JobFlags = '<span style="color:#0000FF;">' + $JobFlags + '</span>'
        }

        # Przygotowuje zmienną do kolumny Log Summary w tabeli HTML
        $JobEscaped = ""
        for ($j = 0; $j -lt $ConfigFileParameters.jobs[$i].JobMailBody.count; $j++) {
            $JobEscaped += [System.Net.WebUtility]::HtmlEncode($($ConfigFileParameters.jobs[$i].JobMailBody[$j].Line))+ '<br>'
        }

$body += @"
    <tr>
        <td valign="top" style="width:$($ColumnsWidthPercent[0])%; border:1px solid #000000; border-top:0; padding:0 7px; line-height:normal;">$JobNo</td>
        <td valign="top" style="width:$($ColumnsWidthPercent[1])%; border:1px solid #000000; border-top:0; border-left:0; padding:0 7px; line-height:normal;">$JobBackupName</td>
        <td valign="top" style="width:$($ColumnsWidthPercent[2])%; border:1px solid #000000; border-top:0; border-left:0; padding:0 7px; line-height:normal;">$JobScheduledText</td>
        <td valign="top" style="width:$($ColumnsWidthPercent[3])%; border:1px solid #000000; border-top:0; border-left:0; padding:0 7px; line-height:normal;">$JobStatusEscaped</td>
        <td valign="top" style="width:$($ColumnsWidthPercent[4])%; border:1px solid #000000; border-top:0; border-left:0; padding:0 7px; line-height:normal;">$JobFlags</td>
        <td valign="top" style="width:$($ColumnsWidthPercent[5])%; border:1px solid #000000; border-top:0; border-left:0; padding:0 7px; line-height:normal; word-break:break-word;">$JobEscaped</td>
    </tr>
"@
    }

$body += @"
</table>
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

                # dodaje pliki log z jobów
                for ($i = 0; $i -lt $ConfigFileParameters.jobs.count; $i++) {
                    if ($null -ne ($ConfigFileParameters.jobs[$i].JobBTBackupLogFilePath)) {
                        $ItemsToZip += $($ConfigFileParameters.jobs[$i].JobBTBackupLogFilePath.FullName)
                    }
                    if ($null -ne ($ConfigFileParameters.jobs[$i].JobRcloneLogFilePath)) {
                        $ItemsToZip += $($ConfigFileParameters.jobs[$i].JobRcloneLogFilePath.FullName)
                    }
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

# Zwraca string z informacją o trybie działania skryptu (tylko walidacja, dry run, normalny)
function Get-ModeString {

    if ($ValidateOnly) {
        return "[VALIDATE ONLY] "
    } elseif ($ValidateJobs) {
        return "[VALIDATE JOBS] "
    } elseif ($DryRun) {
        return "[DRY RUN] "
    } else {
        return ""
    }
}

# Zwraca string z informacją o flagach podsumowania backup planu
function Get-SummaryFlagsString {
    param (
        [bool]$LongVersion = $false  # czy zbudować długą wersję
    )

    if ($null -eq $SummaryFlags.SuccessJobs) { $SuccessStatus = 'N' } else { $SuccessStatus = $SummaryFlags.SuccessJobs }
    if ($null -eq $SummaryFlags.ScheduledJobs) { $ScheduledStatus = 'N' } else { $ScheduledStatus = $SummaryFlags.ScheduledJobs }
    if ($null -eq $SummaryFlags.ReadyJobs) { $ReadyStatus = 'N' } else { $ReadyStatus = $SummaryFlags.ReadyJobs }
    if ($null -eq $SummaryFlags.DefinedJobs) { $DefinedStatus = 'N' } else { $DefinedStatus = $SummaryFlags.DefinedJobs }

    # Long version wykorzystywana w output i logach
    if ($LongVersion) {
        $Success_Scheduled = "Success/Scheduled: $SuccessStatus/$ScheduledStatus"
        $Ready_Defined = "Ready/Defined: $ReadyStatus/$DefinedStatus"
    }
    else {
        # Short version wykorzystywana w tytule maila

        # Czy string ma być uproszczony poprzez zamianę n/n do pojedynczego n
        if ($ValidateOnly -or $ValidateJobs -or $DryRun -or $RunAll -or (-not [string]::IsNullOrWhiteSpace($RunJob))) {
            $SimplifyString = $false
        } else {
            $SimplifyString = $true
        }

        if ( ($SuccessStatus -ne $ScheduledStatus) -or ($SuccessStatus -eq 'X') -or ($ScheduledStatus -eq 'X') -or (-not $SimplifyString) ) {
            $Success_Scheduled = "Success: $SuccessStatus/$ScheduledStatus"
        } else {
            $Success_Scheduled = "Success: $SuccessStatus"
        }
        if ( ($ReadyStatus -ne $DefinedStatus) -or ($ReadyStatus -eq 'X') -or ($DefinedStatus -eq 'X') -or (-not $SimplifyString) ) {
            $Ready_Defined = "Ready: $ReadyStatus/$DefinedStatus"
        } else {
            $Ready_Defined = "Ready: $ReadyStatus"
        }
    }

    return "($($Success_Scheduled), $($Ready_Defined))"
}

# Podsumowuje wykonanie planu backupów i ustawia temat maila.
# Obsługuje brak błędów, jeden błąd lub wiele błędów w ExitResults.
# Zwraca liczbę wyświetlonych błędów (0, gdy nie ma błędów), używaną w końcowym podsumowaniu do pominięcia już wyświetlonych błędów.
function Write-BackupPlanSummary {
    $ExitResults_displayed = 0

    if ($ExitResults.count -eq 0) {
        $MailConfig.Subject = (Get-ModeString)+"Successful "+(Get-SummaryFlagsString -LongVersion:$false)+" backup plan """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        Write-Log -LogLine ((Get-ModeString)+"Backup plan completed successfully "+(Get-SummaryFlagsString -LongVersion:$true)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    } elseif ($ExitResults.count -eq 1) {
        $MailConfig.Subject = (Get-ModeString)+"Failed "+(Get-SummaryFlagsString -LongVersion:$false)+" backup plan """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        $ExitResults_displayed = 1
        Write-Log -LogLine ((Get-ModeString)+"Backup plan failed with Error: "+$($ExitResults[1]).Code+" "+$($ExitResults[1]).Message+" "+(Get-SummaryFlagsString -LongVersion:$true)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    } else {
        $MailConfig.Subject = (Get-ModeString)+"Failed "+(Get-SummaryFlagsString -LongVersion:$false)+" backup plan """+$($ConfigFileInfo.BaseName)+""" on "+$env:COMPUTERNAME
        1..($ExitResults.count) | ForEach-Object {
            $ExitResults_displayed = $_
            Write-Log -LogLine ("Error: "+$($ExitResults[$ExitResults_displayed]).Code+" "+$($ExitResults[$ExitResults_displayed]).Message) -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
        }
        $ExitResult_local=$ExitDefinitions.Multiple
        Write-Log -LogLine ((Get-ModeString)+"Backup plan failed with Error: "+$($ExitResult_local.Code)+" "+$ExitResult_local.Message+" ("+$ExitResults.count+")"+" "+(Get-SummaryFlagsString -LongVersion:$true)+" (Duration: $(Get-ElapsedDurationString -StartTime $DT))") -WriteToMail:$true -MailSegment:"Summary" -WriteToHost:$true
    }

    return $ExitResults_displayed
}

# Wyświetla ostateczne podsumowanie planu backupów po wysłaniu raportu mailowego i usunięciu plików tymczasowych oraz blokady.
# Obsługuje brak błędów, jeden błąd lub wiele błędów w ExitResults i wyświetla pozostałe błędy.
# Zwraca tablicę haszującą z polami Code i Message: Success przy braku błędów, jedyny błąd zapisany w ExitResults lub Multiple przy wielu błędach.
function Write-BackupPlanFinalSummary {
    param (
        [int]$DisplayedErrorCount
    )

    if ($ExitResults.count -eq 0) {
        Write-Log -LogLine ("Finish backup plan $($ConfigFileInfo.BaseName)"+": Completed successfully") -WriteToMail:$false -WriteToHost:$true
        $ExitResult_final=$ExitDefinitions.Success
    } elseif ($ExitResults.count -eq 1) {
        Write-Log -LogLine ("Finish backup plan $($ConfigFileInfo.BaseName)"+": Completed with Error: "+$($ExitResults[1]).Code+" "+$($ExitResults[1]).Message) -WriteToMail:$false -WriteToHost:$true
        $ExitResult_final=$ExitResults[1]
    } else {
        if (($DisplayedErrorCount+1) -le ($ExitResults.count)) {
            ($DisplayedErrorCount+1)..($ExitResults.count) | ForEach-Object {
                Write-Log -LogLine ("Error: "+$($ExitResults[$_]).Code+" "+$($ExitResults[$_]).Message) -WriteToMail:$false -WriteToHost:$true
            }
        }
        $ExitResult_final=$ExitDefinitions.Multiple
        Write-Log -LogLine ("Finish backup plan $($ConfigFileInfo.BaseName)"+": Completed with Error: "+$($ExitResult_final.Code)+" "+$ExitResult_final.Message+" ("+$ExitResults.count+")") -WriteToMail:$false -WriteToHost:$true
    }

    return $ExitResult_final
}

### Main script execution starts here

# Wczytuje i waliduje konfigurację backup planu, inicjalizuje raportowanie mailowe
$ExitResult_single = ProcessParamOrIssue
if ($null -ne $ExitResult_single) {
    $ExitResults[$ExitResults.Count+1] = $ExitResult_single
}

# Waliduje konfigurację backup jobs
$ExitResult_single = ProcessParamJobs
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

# Uruchamia backup joby startujące bt-backup i wyświetla status jobów
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów
if ($ExitResults.count -eq 0) {
    $ExitResult_single = ProcessBackupJobs
    if ($null -ne $ExitResult_single) {
        $ExitResults[$ExitResults.Count+1] = $ExitResult_single
    }
}

# Gerenuje kody błędów dla job na podstawie ich statusu
# wykonuje się tylko wtedy, gdy nie było wcześniejszych błędów
if ($ExitResults.count -eq 0) {
    $null = ProcessResolveJobStatuses
}

# Podsumowanie wykonania backup planu oraz ustawia temat maila,
# obsługa przypadków, brak błędów, jeden błąd lub wiele błędów w tablicy ExitResults
$ExitResults_displayed = Write-BackupPlanSummary

# Wysyła raport mailowy,
# wykonuje się tylko wtedy, gdy nie jest to tryb walidacji
if ((-not $ValidateOnly) -and (-not $ValidateJobs)) {
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

# Ostateczne podsumowanie wykonania backup planu po wysłaniu raportu mailowego i czyszczeniu plików tymczasowych,
# obsługa przypadków, brak błędów, jeden błąd lub wiele błędów w tablicy ExitResults. 
$ExitResult_final = Write-BackupPlanFinalSummary -DisplayedErrorCount $ExitResults_displayed

Exit-Pause -ExitCode:$($ExitResult_final.Code)

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
