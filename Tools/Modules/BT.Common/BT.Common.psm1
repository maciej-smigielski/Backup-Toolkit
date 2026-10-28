
Set-StrictMode -Version Latest

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów modułu BT.Common
$BTCommonExitDefinitions = @{
    BTCommonLock = @{ Code = 801; Message = "Lock process failed" }
    BTCommonUnlock = @{ Code = 802; Message = "Unlock process failed" }
    BTCommonSessionTemp = @{ Code = 803; Message = "Temporary directory creation failed" }
    BTCommonCleanup = @{ Code = 804; Message = " Temporary directory cleanup failed" }
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
    LockFile = $null                    # Ścieżka do pliku lock, ustawiane manualnie, obiekt System.String
    LockFileHandle = $null              # Uchwyt do pliku lock, ustawiane przez CreateSessionLockFile, obiekt System.IO.FileStream
    #
    TempDir = $null                     # Katalog tymczasowy, ustawiane manualnie, obiekt System.String
    ProcessTempDir = $null              # Katalog tymczasowy dla tej sesji, ustawiane przez CreateSessionTemporaryDir, obiekt System.String
    ProcessTempDirCreated = $false      # Flaga określająca, czy katalog tymczasowy dla sesji został utworzony, ustawiana przez CreateSessionTemporaryDir
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

    if ($WriteToHost -or ($DebugLevel -and $BTCommon.DebugToConsole)) {
        $foregroundColor = switch ($Color) {
            'Error'   { 'Red' }
            'Warning' { 'Yellow' }
            'Success' { 'Green' }
            'Note'    { 'Cyan' }
            default   { $null }
        }

        if ($null -eq $foregroundColor) {
            Write-Host $LogLine
        } else {
            Write-Host $LogLine -ForegroundColor $foregroundColor
        }
    }

    if ($WriteToMail) {
        $BTCommon.MailBody[$BTCommon.MailBody.Count] = [PSCustomObject]@{
            Segment = $MailSegment
            Line    = $LogLine
        }
    }

    if ( ($WriteToLog) -and (-not [string]::IsNullOrWhiteSpace($BTCommon.LogFile)) ){
        Add-Content -Path $BTCommon.LogFile -Value ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+": $LogLine")
    }

    if ($ShowDialogBox) {
        Show-MessageDialog -Title:$BTCommon.ApplicationTitle -Message:$LogLine
    }
}

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

# Tworzy plik lock dla tej sesji
function CreateSessionLockFile {
    param(
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($($BTCommon.LockFile))) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonLock
        Write-LogError -LogMessage ("CreateSessionLockFile: BTCommon.LockFile is empty.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } elseif ($BTCommon.LockFileHandle) {
        $ExitResult_local=$BTCommonExitDefinitions.BTCommonLock
        Write-LogError -LogMessage ("CreateSessionLockFile: Lock file already created by this session.") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local `
            -WriteToHost:$true
        return $ExitResult_local
    } else {
        try {
            $BTCommon.LockFileHandle = [System.IO.File]::Open(
                $BTCommon.LockFile, 
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::Read
            )

            $LockFileContent = @(
                "PID=$PID",
                "COMMAND=$Command",
                "LOG=$($BTCommon.LogFile)"
            ) -join "`r`n"
            $BTCommon.LockFileHandle.Write(
                [Text.Encoding]::UTF8.GetBytes($LockFileContent),
                0,
                [Text.Encoding]::UTF8.GetByteCount($LockFileContent)
            )

            $BTCommon.LockFileHandle.Flush()
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonLock
            Write-LogError -LogMessage ("CreateSessionLockFile: Unable to create lock file >$($BTCommon.LockFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("CreateSessionLockFile: Created session lock file >"+($BTCommon.LockFile)+"<") -WriteToHost:$false    

    return $null    # wyjście z funkcji CreateSessionLockFile, kod wyjścia $null oznacza brak błędów
}

# Usuwa plik lock dla tej sesji
function RemoveSessionLockFile {

    if ($BTCommon.LockFileHandle) {
        try {
            $BTCommon.LockFileHandle.Close()
            $BTCommon.LockFileHandle.Dispose()
            $BTCommon.LockFileHandle = $null
            Remove-Item -Path $BTCommon.LockFile -Force -ErrorAction Stop
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonUnlock
            Write-LogError -LogMessage ("RemoveSessionLockFile: Unable to remove lock file >$($BTCommon.LockFile)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }
    Write-Log -LogLine ("RemoveSessionLockFile: Removed session lock file.") -WriteToHost:$false    

    return $null    # wyjście z funkcji RemoveSessionLockFile, kod wyjścia $null oznacza brak błędów
}

# Tworzy katalog tymczasowy dla sesji, jeśli nie został jeszcze utworzony
function CreateSessionTemporaryDir {

    if (-not $BTCommon.ProcessTempDirCreated) {
        # Pobranie unikalnego identyfikatora sesji w formacie {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
        $SessionId = ([guid]::NewGuid()).ToString("B").ToUpper()

        try {
            $BTCommon.ProcessTempDir = Join-Path -Path ($BTCommon.TempDir) -ChildPath ("$SessionId") -ErrorAction Stop
            New-Item -ItemType Directory -Path $BTCommon.ProcessTempDir -ErrorAction Stop | Out-Null
            $BTCommon.ProcessTempDirCreated = $true
        } catch {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonSessionTemp
            Write-LogError -LogMessage ("CreateSessionTemporaryDir: Create ProcessTempDir >$($BTCommon.ProcessTempDir)<") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
       Write-Log -LogLine ("CreateSessionTemporaryDir: Created process temporary directory >"+($BTCommon.ProcessTempDir)+"<") -WriteToHost:$false -DebugLevel:$true
    } else {
       Write-Log -LogLine ("CreateSessionTemporaryDir: Process temporary directory already created >"+($BTCommon.ProcessTempDir)+"<") -WriteToHost:$false -DebugLevel:$true
    }

    return $null    # wyjście z funkcji CreateSessionTemporaryDir, kod wyjścia $null oznacza brak błędów
}

# Czyści katalog i pliki tymczasowe dla tej sesji
function RemoveSessionTemporaryDir {

    if ( $BTCommon.ProcessTempDirCreated ) {
    
        $Attempts = 20
        $Deleted = $false
        for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {

            try {
                Remove-Item -Path $BTCommon.ProcessTempDir -Recurse -Force -ErrorAction Stop
                Write-Log -LogLine ("RemoveSessionTemporaryDir: Cleanup executed successfully at $Attempt attempt.") -WriteToHost:$false

                $Deleted = $true
                break
            }
            catch {
                Write-Log -LogLine ("RemoveSessionTemporaryDir: Cleanup attempt $Attempt/$Attempts failed: $($_.Exception.Message)") -WriteToHost:$false

                if ($Attempt -lt $Attempts) {
                    Start-Sleep -Seconds 2
                }
            }
        }

        if (-not $Deleted) {
            $ExitResult_local=$BTCommonExitDefinitions.BTCommonCleanup
            Write-LogError -LogMessage ("RemoveSessionTemporaryDir: Cleanup after $Attempts attempts.") -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local `
                -WriteToHost:$true
            return $ExitResult_local
        }
    }

    return $null    # wyjście z funkcji RemoveSessionTemporaryDir, kod wyjścia $null oznacza brak błędów
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
        'CreateSessionLockFile',
        'RemoveSessionLockFile',
        'CreateSessionTemporaryDir',
        'RemoveSessionTemporaryDir',
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
