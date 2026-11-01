
Set-StrictMode -Version Latest

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów modułu BT.Common
$BTCommonExitDefinitions = @{
    BTCommonCoordinatorLock = @{ Code = 801; Message = "Coordinator lock process failed" }
    BTCommonCoordinatorUnlock = @{ Code = 802; Message = "Coordinator unlock process failed" }
    BTCommonSessionLock = @{ Code = 803; Message = "Session lock process failed" }
    BTCommonSessionUnlock = @{ Code = 804; Message = "Session unlock process failed" }
    BTCommonSessionTempDirCreate = @{ Code = 805; Message = "Temporary directory creation failed" }
    BTCommonSessionTempDirRemove = @{ Code = 806; Message = " Temporary directory cleanup failed" }
    BTCommonShutdownStarted = @{ Code = 807; Message = "Operating system is shutting down" }
    BTCommonShutdownPending = @{ Code = 808; Message = "Operating system shutdown is pending" }
}

# Zmienne wewnętrzne modułu BT.Common
$BTCommon = [PSCustomObject]@{
    NoPause = $null                     # Flaga określająca, czy pomijać pauzę przy Exit-Pause, null i true pomija pause, ustawiane przez Initialize-BTCommon
    DebugMode = $false                  # Flaga określająca, czy tryb debug jest włączony, ustawiana przez Initialize-BTCommon
    DebugToConsole = $false             # Flaga określająca, czy debug ma być wyświetlany w konsoli, ustawiana przez Initialize-BTCommon
    ApplicationTitle = ""               # Tytuł aplikacji używany w oknach dialogowych, ustawiany przez Initialize-BTCommon
    #
    LogDir = $null                      # Ścieżka do katalogu log, ustawiane manualnie, obiekt System.IO.DirectoryInfo
    LogFile = $null                     # Ścieżka do pliku log, ustawiane manualnie, obiekt System.IO.FileInfo
    #
    MailBody = @{}                      # Zawiera treść maila do wysłania, ustawiane przez Write-Log
    #
    LockDir = $null                     # Ścieżka do katalogu lock, ustawiane manualnie, obiekt System.IO.DirectoryInfo
    SessionLockFile = $null             # Ścieżka do pliku lock sesji, ustawiane manualnie, obiekt System.String
    SessionLockFileHandle = $null       # Uchwyt do pliku lock sesji, ustawiane przez Open-SessionLockFile, obiekt System.IO.FileStream
    CoordinatorLockFile = $null         # Ścieżka do pliku lock koordynatora, ustawiane przez Open-CoordinatorLockFile, obiekt System.String
    CoordinatorLockFileHandle = $null   # Uchwyt do pliku lock koordynatora, ustawiane przez Open-CoordinatorLockFile, obiekt System.IO.FileStream
    #
    TempDir = $null                     # Katalog tymczasowy, ustawiane manualnie, obiekt System.String
    ProcessTempDir = $null              # Katalog tymczasowy dla tej sesji, ustawiane przez Initialize-SessionTemporaryDirectory, obiekt System.String
    ProcessTempDirCreated = $false      # Flaga określająca, czy katalog tymczasowy dla sesji został utworzony, ustawiana przez Initialize-SessionTemporaryDirectory
}

# Inicjalizuje moduł BT.Common
function Initialize-BTCommon {
    param(
        [bool]$NoPause = $false,
        [bool]$DebugMode = $false,
        [bool]$DebugToConsole = $false,
        [string]$ApplicationTitle = ""
    )

    if ($PSBoundParameters.ContainsKey('NoPause')) {
        $BTCommon.NoPause = $NoPause
    }
    if ($PSBoundParameters.ContainsKey('DebugMode')) {
        $BTCommon.DebugMode = $DebugMode
    }
    if ($PSBoundParameters.ContainsKey('DebugToConsole')) {
        $BTCommon.DebugToConsole = $DebugToConsole
    }
    if ($PSBoundParameters.ContainsKey('ApplicationTitle')) {
        $BTCommon.ApplicationTitle = $ApplicationTitle
    }
}

# Zatrzymuje skrypt i czeka na naciśnięcie klawisza, następnie kończy skrypt z podanym kodem wyjścia
function Exit-Pause {
    param (
        [int]$ExitCode = 0
    )

    # Jeżeli NoPause jest puste/nieokreślone, pomija pauzę
    if ($null -ne $BTCommon.NoPause) {
        if ($BTCommon.NoPause -eq $false) {
            try {
                Read-Host "Press Enter to continue . . ."
            } catch {
                # Jeżeli tryb NonInteractive, pomija/ignowuje pauzę
                if (-not ($_.Exception.Message -like "*NonInteractive mode*")) {
                    throw
                }
            }
        }
    }

    exit $ExitCode
}

# Zapisuje komunikat do logu, na ekran oraz do maila
function Write-Log {
    param (
        [string]$LogLine = "",
        [bool]$WriteToHost = $false,    # czy pisać na ekran
        [bool]$WriteToLog  = $true,     # czy pisać do log, wymaga aby log był aktywny, ustawiona zmienna LogFile
        [bool]$WriteToMail = $false,    # czy pisać do mail, zapisuje w MailBody
        [string]$MailSegment = "",      # Segment wiadomości e-mail, do którego zostanie dodany komunikat
        [bool]$ShowDialogBox = $false,  # czy pokazywać okno dialogowe z komunikatem
        [ValidateSet('Error', 'Warning', 'Success', 'Note', 'Standard')]
        [string]$Color = 'Standard',    # dla Write-Host: Error=Red, Warning=Yellow, Success=Green, Note=Cyan; Standard bez zmiany koloru
        [bool]$DebugLevel = $false      # czy komunikat tylko w trybie debug
    )

    # Jeżeli komunikat jest w trybie debug, a nie jest ustawiony parametr Debug, to nie zapisuje komunikatu
    if ( ($DebugLevel) -and (-not ($BTCommon.DebugMode)) ) {
            return
    }

    $outputLogLine = $LogLine
    if ($DebugLevel) {
        $outputLogLine = "[Debug] $LogLine"
    }

    if ($WriteToHost -or ($DebugLevel -and $BTCommon.DebugToConsole)) {
        $foregroundColor = switch ($Color) {
            'Error'   { 'Red' }
            'Warning' { 'Yellow' }
            'Success' { 'Green' }
            'Note'    { 'Cyan' }
            default   { $null }
        }

        if ($null -eq $foregroundColor) {
            Write-Host $outputLogLine
        } else {
            Write-Host $outputLogLine -ForegroundColor $foregroundColor
        }
    }

    if ($WriteToMail) {
        $BTCommon.MailBody[$BTCommon.MailBody.Count] = [PSCustomObject]@{
            Segment = $MailSegment
            Line    = $LogLine
        }
    }

    if ( ($WriteToLog) -and (-not [string]::IsNullOrWhiteSpace($BTCommon.LogFile)) ){
        Add-Content -Path $BTCommon.LogFile -Value ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+": $outputLogLine")
    }

    if ($ShowDialogBox) {
        Show-MessageDialog -Title:$BTCommon.ApplicationTitle -Message:$outputLogLine
    }
}

# Formatuje i zapisuje błąd lub ostrzeżenie z informacją o miejscu wywołania
function Write-LogError {
    param (
        [string]$LogMessagePrefix = "",             # Opcjonalny prefiks dla komunikatu błędu, jest dołączany na początku komunikatu
        [string]$LogMessage = "",                   # Komunikat który ma być zapisany do log, jest obudowany dodatkowymi informacjami o błędzie
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.CallStackFrame]$CallStackFrame,       # Ramka stosu wywołań, zawiera informacje o miejscu wywołania funkcji, przy wywołaniu pobierajy jako (Get-PSCallStack)[0]
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null,     # Dla błędów po catch, zawiera informacje błędzie i miejscu jego powstania, przy wywołaniu pobierane jako $_
        [PSCustomObject]$ExitResult = $null,        # Obiekt zawierający informacje o błędzie, w tym kod błędu, jak pusty to wyświetlany jest Warning zamiast Error i brak numeru błędu
        [bool]$IncludeErrorMessage = $false,        # czy do komunikatu dołączyć wiadomość błędu z ExitResult, wymagane aby ExitResult był podany
        [bool]$WriteToHost = $false,                # czy pisać na ekran
        [bool]$WriteToLog  = $true,                 # czy pisać do log, wymaga aby log był aktywny, ustawiona zmienna LogFile
        [bool]$WriteToMail = $false,                # czy pisać do mail, zapisuje w MailBody
        [string]$MailSegment = "",                  # Segment wiadomości e-mail, do którego zostanie dodany komunikat
        [bool]$ShowDialogBox = $false,              # czy pokazywać okno dialogowe z komunikatem
        [ValidateSet('Error', 'Warning', 'Success', 'Note', 'Standard')]
        [string]$Color = 'Standard',    # dla Write-Host: Error=Red, Warning=Yellow, Success=Green, Note=Cyan; Standard bez zmiany koloru
        [bool]$DebugLevel = $false                  # czy komunikat tylko w trybie debug
    )

    $CallStackFrameString = "$(Split-Path -Leaf $CallStackFrame.ScriptName):$($CallStackFrame.ScriptLineNumber)"

    if ($null -ne $ErrorRecord) {
        $InvocationInfoString = "$(Split-Path -Leaf $ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)/"
        $ExceptionString = ": $($ErrorRecord.Exception.Message)"
    } else {
        $InvocationInfoString = ""
        $ExceptionString = ""
    }

    $ErrorWarningString = "Warning:"
    $ExitResultCodeString = ""
    $ExitResultMessageString = ""
    if ($null -ne $ExitResult) {
        $ErrorWarningString = "Error:"
        $ExitResultCodeString = "($($ExitResult.Code))"
        if ($IncludeErrorMessage) {
            $ExitResultMessageString = " $($ExitResult.Message);"
        }
    }

    Write-Log -LogLine ("$($LogMessagePrefix)$($ErrorWarningString) $($ExitResultCodeString)[$($InvocationInfoString)$($CallStackFrameString)]$($ExitResultMessageString) $($LogMessage)$($ExceptionString)") `
        -WriteToHost:$WriteToHost `
        -WriteToLog:$WriteToLog `
        -WriteToMail:$WriteToMail `
        -MailSegment:$MailSegment `
        -ShowDialogBox:$ShowDialogBox `
        -DebugLevel:$DebugLevel `
        -Color:$Color
}

# Zbiera zdarzenia systemowe związane z zamknięciem od czasu uruchomienia systemu
function Get-ShutdownEventsSinceBoot {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime

    # Bez -ErrorAction SilentlyContinue Get-WinEvent rzuca wyjątek, gdy brak zdarzeń
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 1074, 1075, 13
        StartTime = $bootTime
    } -ErrorAction SilentlyContinue | Where-Object {
        ($_.Id -in 1074, 1075 -and $_.ProviderName -eq 'User32') -or
        ($_.Id -eq 13 -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-General')
    }

    $descriptions = @{
        1074 = 'Shutdown/restart requested'
        1075 = 'Shutdown/restart aborted'
        13   = 'Operating system is shutting down'
    }

    if (@($events).Count -eq 0) {
        Write-Log -LogLine 'Get-ShutdownEventsSinceBoot: Event count: 0' -WriteToHost:$false -DebugLevel:$true
    } else {
        @($events) | Sort-Object TimeCreated | ForEach-Object {
            $line = 'Get-ShutdownEventsSinceBoot: Event: {0:yyyy-MM-dd HH:mm:ss}; RecordId: {1}; ID: {2}; {3}' -f $_.TimeCreated, $_.RecordId, $_.Id, $descriptions[$_.Id]
            Write-Log -LogLine $line -WriteToHost:$false -DebugLevel:$true
        }
    }

    @($events) | Sort-Object TimeCreated | ForEach-Object {
        [PSCustomObject]@{
            RecordId    = $_.RecordId
            TimeCreated = $_.TimeCreated
            Id          = $_.Id
            Description = $descriptions[$_.Id]
            Message     = $_.Message
        }
    }
}

# Sprawdza, czy system oczekuje na zamknięcie lub jest już w trakcie zamykania, zwraca null gdy zamknięcie nie oczekuje, w przeciwnym razie kod błędu
function Test-ShutdownPending {
    $events = @(Get-ShutdownEventsSinceBoot | Sort-Object RecordId)

    $shutdownStarted = $events |
        Where-Object { $_.Id -eq 13 } |
        Select-Object -First 1

    if ($null -ne $shutdownStarted) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonShutdownStarted
        Write-LogError -LogMessage ('Test-ShutdownPending: Found event 13; TimeCreated: {0:yyyy-MM-dd HH:mm:ss}; RecordId: {1}; Operating system is shutting down' -f $shutdownStarted.TimeCreated, $shutdownStarted.RecordId) -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    $lastShutdownRequest = $events |
        Where-Object { $_.Id -eq 1074 } |
        Select-Object -Last 1

    if ($null -eq $lastShutdownRequest) {
        Write-Log -LogLine 'Test-ShutdownPending: No event 1074 or 13 found; Shutdown is not pending' -WriteToHost:$false
        return $null
    }

    $cancellationAfterRequest = $events |
        Where-Object { $_.Id -eq 1075 -and $_.RecordId -gt $lastShutdownRequest.RecordId } |
        Select-Object -First 1

    if ($null -ne $cancellationAfterRequest) {
        Write-Log -LogLine ('Test-ShutdownPending: Found event 1075 after event 1074; TimeCreated: {0:yyyy-MM-dd HH:mm:ss}; RecordId: {1}; Shutdown is not pending' -f $cancellationAfterRequest.TimeCreated, $cancellationAfterRequest.RecordId) -WriteToHost:$false
        return $null
    }

    $ExitResult_local=$BTCommonExitDefinitions.BTCommonShutdownPending
    Write-LogError -LogMessage ('Test-ShutdownPending: Found event 1074 and not event 1075 after it; TimeCreated: {0:yyyy-MM-dd HH:mm:ss}; RecordId: {1}; Shutdown pending' -f $lastShutdownRequest.TimeCreated, $lastShutdownRequest.RecordId) -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local `
        -WriteToHost:$true
    return $ExitResult_local
}

# Tworzy plik lock koordynatora na podstawie katalogu LockDir
function Open-CoordinatorLockFile {
    param(
        [string]$Command    # Pełna ścieżka do skryptu powiązanego z plikiem lock koordynatora
    )

    if ([string]::IsNullOrWhiteSpace($($BTCommon.LockDir))) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorLock
        Write-LogError -LogMessage ("Open-CoordinatorLockFile: BTCommon.LockDir is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } elseif ($BTCommon.CoordinatorLockFileHandle) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorLock
        Write-LogError -LogMessage ("Open-CoordinatorLockFile: Coordinator lock file already created by this session.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } else {
        try {
            $LockDirFullPath = [System.IO.Path]::GetFullPath($BTCommon.LockDir)
            $LockDirParent = [System.IO.Directory]::GetParent($LockDirFullPath)            
            if ([string]::IsNullOrWhiteSpace($LockDirParent)) {
                $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorLock
                Write-LogError -LogMessage ("Open-CoordinatorLockFile: Lock directory parent is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$null `
                    -ExitResult:$ExitResult_local `
                    -WriteToHost:$true
                return $ExitResult_local
            }
            $LockDirName = Split-Path -Path $LockDirFullPath -Leaf -ErrorAction Stop
            $BTCommon.CoordinatorLockFile = Join-Path -Path $BTCommon.LockDir -ChildPath ('.' + $LockDirName) -ErrorAction Stop
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorLock
            Write-LogError -LogMessage ("Open-CoordinatorLockFile: Unable to determine coordinator lock file path.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    $Attempts = 30
    $Opened = $false
    $LastErrorRecord = $null
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        $CoordinatorLockFileHandle = $null

        try {
            $CoordinatorLockFileHandle = [System.IO.File]::Open(
                $BTCommon.CoordinatorLockFile,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::Read
            )

            $CoordinatorLockFileContent = @(
                "PID=$PID",
                "COMMAND=$Command",
                "LOG=$($BTCommon.LogFile)"
            ) -join "`r`n"
            $CoordinatorLockFileHandle.Write(
                [Text.Encoding]::UTF8.GetBytes($CoordinatorLockFileContent),
                0,
                [Text.Encoding]::UTF8.GetByteCount($CoordinatorLockFileContent)
            )
            $CoordinatorLockFileHandle.Flush()

            $BTCommon.CoordinatorLockFileHandle = $CoordinatorLockFileHandle
            $Opened = $true
        } catch {
            $LastErrorRecord = $_
            Write-Log -LogLine ("Open-CoordinatorLockFile: Lock attempt $Attempt/$Attempts failed: $($_.Exception.Message)") -WriteToHost:$false
        } finally {
            if ((-not $Opened) -and ($null -ne $CoordinatorLockFileHandle)) {
                $CoordinatorLockFileHandle.Dispose()
            }
        }

        if ($Opened) {
            break
        }

        if ($Attempt -lt $Attempts) {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $Opened) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorLock
        Write-LogError -LogMessage ("Open-CoordinatorLockFile: Unable to create coordinator lock file >$($BTCommon.CoordinatorLockFile)< after $Attempts attempts.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$LastErrorRecord `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    }

    Write-Log -LogLine ("Open-CoordinatorLockFile: Created coordinator lock file >$($BTCommon.CoordinatorLockFile)< at $Attempt attempt.") -WriteToHost:$false

    return $null    # Brak błędów podczas tworzenia pliku lock koordynatora
}

# Usuwa plik lock koordynatora
function Close-CoordinatorLockFile {

    if ($BTCommon.CoordinatorLockFileHandle) {
        try {
            $BTCommon.CoordinatorLockFileHandle.Close()
            $BTCommon.CoordinatorLockFileHandle.Dispose()
            $BTCommon.CoordinatorLockFileHandle = $null
            Remove-Item -Path $BTCommon.CoordinatorLockFile -Force -ErrorAction Stop
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonCoordinatorUnlock
            Write-LogError -LogMessage ("Close-CoordinatorLockFile: Unable to remove coordinator lock file >$($BTCommon.CoordinatorLockFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("Close-CoordinatorLockFile: Removed coordinator lock file.") -WriteToHost:$false
    }

    return $null    # Brak błędów podczas usuwania pliku lock koordynatora
}

# Tworzy plik lock dla tej sesji
function Open-SessionLockFile {
    param(
        [string]$Command    # Full path to the script associated with this session lock file
    )

    if ([string]::IsNullOrWhiteSpace($($BTCommon.SessionLockFile))) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionLock
        Write-LogError -LogMessage ("Open-SessionLockFile: BTCommon.SessionLockFile is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } elseif ($BTCommon.SessionLockFileHandle) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionLock
        Write-LogError -LogMessage ("Open-SessionLockFile: Lock file already created by this session.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } else {
        try {
            $BTCommon.SessionLockFileHandle = [System.IO.File]::Open(
                $BTCommon.SessionLockFile,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::Read
            )

            $LockFileContent = @(
                "PID=$PID",
                "COMMAND=$Command",
                "LOG=$($BTCommon.LogFile)"
            ) -join "`r`n"
            $BTCommon.SessionLockFileHandle.Write(
                [Text.Encoding]::UTF8.GetBytes($LockFileContent),
                0,
                [Text.Encoding]::UTF8.GetByteCount($LockFileContent)
            )

            $BTCommon.SessionLockFileHandle.Flush()
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionLock
            Write-LogError -LogMessage ("Open-SessionLockFile: Unable to create lock file >$($BTCommon.SessionLockFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("Open-SessionLockFile: Created session lock file >"+($BTCommon.SessionLockFile)+"<") -WriteToHost:$false

    return $null    # wyjście z funkcji Open-SessionLockFile, kod wyjścia $null oznacza brak błędów
}

# Usuwa plik lock dla tej sesji
function Close-SessionLockFile {

    if ($BTCommon.SessionLockFileHandle) {
        try {
            $BTCommon.SessionLockFileHandle.Close()
            $BTCommon.SessionLockFileHandle.Dispose()
            $BTCommon.SessionLockFileHandle = $null
            Remove-Item -Path $BTCommon.SessionLockFile -Force -ErrorAction Stop
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionUnlock
            Write-LogError -LogMessage ("Close-SessionLockFile: Unable to remove lock file >$($BTCommon.SessionLockFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
        Write-Log -LogLine ("Close-SessionLockFile: Removed session lock file.") -WriteToHost:$false
    }

    return $null    # wyjście z funkcji Close-SessionLockFile, kod wyjścia $null oznacza brak błędów
}

# Tworzy katalog tymczasowy dla sesji, jeśli nie został jeszcze utworzony
function Initialize-SessionTemporaryDirectory {

    if (-not $BTCommon.ProcessTempDirCreated) {
        # Pobranie unikalnego identyfikatora sesji w formacie {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
        $SessionId = ([guid]::NewGuid()).ToString("B").ToUpper()

        try {
            $BTCommon.ProcessTempDir = Join-Path -Path ($BTCommon.TempDir) -ChildPath ("$SessionId") -ErrorAction Stop
            New-Item -ItemType Directory -Path $BTCommon.ProcessTempDir -ErrorAction Stop | Out-Null
            $BTCommon.ProcessTempDirCreated = $true
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionTempDirCreate
            Write-LogError -LogMessage ("Initialize-SessionTemporaryDirectory: Create ProcessTempDir >$($BTCommon.ProcessTempDir)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
       Write-Log -LogLine ("Initialize-SessionTemporaryDirectory: Created process temporary directory >"+($BTCommon.ProcessTempDir)+"<") -WriteToHost:$false -DebugLevel:$true
    } else {
       Write-Log -LogLine ("Initialize-SessionTemporaryDirectory: Process temporary directory already created >"+($BTCommon.ProcessTempDir)+"<") -WriteToHost:$false -DebugLevel:$true
    }

    return $null    # wyjście z funkcji Initialize-SessionTemporaryDirectory, kod wyjścia $null oznacza brak błędów
}

# Czyści katalog i pliki tymczasowe dla tej sesji
function Remove-SessionTemporaryDirectory {

    if ( $BTCommon.ProcessTempDirCreated ) {
    
        $Attempts = 20
        $Deleted = $false
        for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {

            try {
                Remove-Item -Path $BTCommon.ProcessTempDir -Recurse -Force -ErrorAction Stop
                Write-Log -LogLine ("Remove-SessionTemporaryDirectory: Cleanup executed successfully at $Attempt attempt.") -WriteToHost:$false

                $Deleted = $true
                break
            }
            catch {
                Write-Log -LogLine ("Remove-SessionTemporaryDirectory: Cleanup attempt $Attempt/$Attempts failed: $($_.Exception.Message)") -WriteToHost:$false

                if ($Attempt -lt $Attempts) {
                    Start-Sleep -Seconds 2
                }
            }
        }

        if (-not $Deleted) {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionTempDirRemove
            Write-LogError -LogMessage ("Remove-SessionTemporaryDirectory: Cleanup after $Attempts attempts.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    return $null    # wyjście z funkcji Remove-SessionTemporaryDirectory, kod wyjścia $null oznacza brak błędów
}

# Zwraca aktualny czas w standardowym formacie znaczników czasu
function Get-Timestamp {
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

# Zwraca sformatowany czas wykonania w formacie d:h:m:s bez zbędnych zer wiodących
function Get-ElapsedDurationString {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [datetime]$StartTime
    )

    $elapsed = (Get-Date) - $StartTime
    $segments = @($elapsed.Days, $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds)
    $labels = @('d', 'h', 'm', 's')

    while ($segments.Count -gt 1 -and $segments[0] -eq 0) {
        $segments = $segments[1..($segments.Count - 1)]
        $labels = $labels[1..($labels.Count - 1)]
    }

    $result = @()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $result += "$($segments[$i])$($labels[$i])"
    }

    return ($result -join ' ')
}

# Formatuje rozmiar w bajtach na czytelny format (B, KiB, MiB, GiB, TiB)
function Format-ByteSizeString {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [double] $Bytes,
        [int] $Decimals = 3
    )

    process {
        if ($Bytes -lt 1024) {
            return ("{0:N0} B" -f $Bytes)
        } elseif ($Bytes -lt 1MB) {
            return ("{0:N$Decimals} KiB" -f ($Bytes / 1KB))
        } elseif ($Bytes -lt 1GB) {
            return ("{0:N$Decimals} MiB" -f ($Bytes / 1MB))
        } elseif ($Bytes -lt 1TB) {
            return ("{0:N$Decimals} GiB" -f ($Bytes / 1GB))
        } else {
            return ("{0:N$Decimals} TiB" -f ($Bytes / 1TB))
        }
    }
}

# Displays a message dialog.
function Show-MessageDialog {
    param (
        [string]$Title,
        [string]$Message
    )

    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.Add_Shown({ $form.Activate() })

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Message
    $label.AutoSize = $true
    $label.TextAlign = 'TopLeft'
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $form.Controls.Add($label)

    $form.Size = [System.Drawing.Size]::new(
        [Math]::Max($label.PreferredSize.Width + 60, 200),
        $label.PreferredSize.Height + 120
    )

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(
        [Math]::Round(($form.ClientSize.Width - $btnClose.Width) / 2),
        ($form.ClientSize.Height - 50)
    )
    $btnClose.Add_Click({ $form.Tag = "Close"; $form.Close() })
    $form.Controls.Add($btnClose)
    $form.CancelButton = $btnClose

    $form.ShowDialog() | Out-Null
}

# Displays a confirmation dialog and returns whether it was confirmed.
function Show-ConfirmationDialog {
    param (
        [string]$Title,
        [string]$Message
    )

    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.Tag = $false
    $form.Add_Shown({ $form.Activate() })

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Message
    $label.AutoSize = $true
    $label.TextAlign = 'TopLeft'
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $form.Controls.Add($label)

    $form.Size = [System.Drawing.Size]::new(
        [Math]::Max($label.PreferredSize.Width + 60, 260),
        $label.PreferredSize.Height + 120
    )

    $btnConfirm = New-Object System.Windows.Forms.Button
    $btnConfirm.Text = "Confirm"
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $buttonSpacing = 10
    $buttonGroupWidth = $btnConfirm.Width + $btnClose.Width + $buttonSpacing
    $buttonLeft = [Math]::Round(($form.ClientSize.Width - $buttonGroupWidth) / 2)
    $buttonTop = $form.ClientSize.Height - 50

    $btnConfirm.Location = New-Object System.Drawing.Point($buttonLeft, $buttonTop)
    $btnConfirm.Add_Click({ $form.Tag = $true; $form.Close() })
    $form.Controls.Add($btnConfirm)
    $form.AcceptButton = $btnConfirm

    $btnClose.Location = New-Object System.Drawing.Point(
        ($buttonLeft + $btnConfirm.Width + $buttonSpacing),
        $buttonTop
    )
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)
    $form.CancelButton = $btnClose

    $form.ShowDialog() | Out-Null
    return [bool]$form.Tag
}

# Displays a save-file dialog and returns the selected path.
function Show-SaveFileDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Filter,
        [Parameter(Mandatory = $true)]
        [string]$DefaultFileName
    )

    Add-Type -AssemblyName System.Windows.Forms

    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Title = $Title
    $saveDialog.Filter = $Filter
    $saveDialog.FileName = $DefaultFileName
    if ($saveDialog.ShowDialog() -eq "OK") {
        return $saveDialog.FileName
    }

    return $null
}

# Displays an open-file dialog and returns the selected path.
function Show-OpenFileDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    Add-Type -AssemblyName System.Windows.Forms

    $openDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openDialog.Title = $Title
    $openDialog.Filter = $Filter
    if ($openDialog.ShowDialog() -eq "OK") {
        return $openDialog.FileName
    }

    return $null
}

# Displays a dialog for choosing whether to create or open a credentials file.
function Select-NewOrOpenFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(300,150)
    $form.StartPosition = "CenterScreen"

    $form.Add_Shown({ $form.Activate() })

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.AutoSize = $true
    $label.TextAlign = 'TopLeft'
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $form.Controls.Add($label)

    $btnNew = New-Object System.Windows.Forms.Button
    $btnNew.Text = "New"
    $btnNew.Location = New-Object System.Drawing.Point(20,60)
    $btnNew.Add_Click({ $form.Tag = "New"; $form.Close() })
    $form.Controls.Add($btnNew)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Open"
    $btnOpen.Location = New-Object System.Drawing.Point(100,60)
    $btnOpen.Add_Click({ $form.Tag = "Open"; $form.Close() })
    $form.Controls.Add($btnOpen)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(180,60)
    $btnClose.Add_Click({ $form.Tag = "Close"; $form.Close() })
    $form.Controls.Add($btnClose)

    $form.ShowDialog() | Out-Null

    return $form.Tag
}

# Bez jawnego Export-ModuleMember, zmienna BTCommon nie zostaje wyeksportowana do sesji wywołującej, mimo wpisu w VariablesToExport manifestu
Export-ModuleMember `
    -Function @(
        'Initialize-BTCommon', 
        'Exit-Pause', 
        'Write-Log',
        'Write-LogError',
        'Get-ShutdownEventsSinceBoot',
        'Test-ShutdownPending',
        'Open-CoordinatorLockFile',
        'Close-CoordinatorLockFile',
        'Open-SessionLockFile',
        'Close-SessionLockFile',
        'Initialize-SessionTemporaryDirectory',
        'Remove-SessionTemporaryDirectory',
        'Get-ElapsedDurationString', 
        'Format-ByteSizeString',
        'Get-Timestamp',
        'Show-MessageDialog',
        'Show-ConfirmationDialog',
        'Show-SaveFileDialog',
        'Show-OpenFileDialog',
        'Select-NewOrOpenFile'
    ) `
    -Variable @(
        'BTCommonExitDefinitions',
        'BTCommon'
    )
