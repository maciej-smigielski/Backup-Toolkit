<#
.SYNOPSIS
    BT-Mail-Send.ps1 - Wysyła wiadomość e-mail z poziomu powłoki PowerShell
    na podstawie danych z pliku Mail Credentials oraz parametrów wywołania.

.DESCRIPTION
    Skrypt pobiera dane SMTP i poświadczenia z pliku Mail Credentials typu XML,
    waliduje parametry wejściowe (plik konfiguracji, odbiorcy, temat i treść),
    a następnie wysyła wiadomość e-mail do wskazanych adresatów.

.EXAMPLE
    .\BT-Mail-Send.ps1 -ConfigFile noname.mail_credentials -MailTo "user@example.com;admin@example.com" -Subject "Raport" -Body "Treść wiadomości"
    Wysyła wiadomość e-mail do wskazanych odbiorców z tematem "Raport" i treścią "Treść wiadomości"

.EXAMPLE
    .\BT-Mail-Send.ps1 -ConfigFile noname.mail_credentials -MailTo "user@example.com;admin@example.com" -Subject "Raport" -Body "Treść wiadomości" -Debug
    Uruchamia skrypt z włączonym trybem debugowania.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Mail-Send.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-Mail-Credentials
    [Parameter(Position = 0)]
    [string]$ConfigFile,

    [Parameter(Position = 1)]
    [string]$MailTo,

    [Parameter(Position = 2)]
    [string]$Subject,

    [Parameter(Position = 3)]
    [string]$Body
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

# Inicjalizacja modułu BT.Common
$null = Initialize-BTCommon -DebugMode:$DebugMode -DebugToConsole:$true -ApplicationTitle:$Script.BaseName

# Definicje kodów wyjścia i odpowiadających im komunikatów błędów
$ExitDefinitions = @{
    Success = @{ Code = 0; Message = "Completed successfully" }                             # Zakończono pomyślnie
    Unhandled = @{ Code = 1; Message = "Unhandled exception" }                              # Nieobsłużony wyjątek, proces zatrzymany, w write-error wartość Code i Message wpisane jawnie 
    General = @{ Code = 101; Message = "General error, process stopped" }                   # Ogólny błąd, proces zatrzymany
    Param = @{ Code = 102; Message = "Configuration parameter error, process stopped" }     # Błąd parametru, proces zatrzymany
    MailCredentials = @{ Code = 103; Message = "Mail credentials error, process stopped" }  # Błąd odczytu poświadczeń, proces zatrzymany
    MailSend = @{ Code = 104; Message = "Mail send error, process stopped" }                # Błąd wysyłki maila, proces zatrzymany
}

# Script information
Write-Log -LogLine ("Script.CommandPath: >$($Script.CommandPath)<") -DebugLevel:$true
Write-Log -LogLine ("Script.HomeDir: >$($Script.HomeDir)<") -DebugLevel:$true
Write-Log -LogLine ("Script.Name: >$($Script.Name)<") -DebugLevel:$true
Write-Log -LogLine ("Script.BaseName: >$($Script.BaseName)<") -DebugLevel:$true

# Versions
Write-Log -LogLine ("Script Version: >$($ScriptVersion)<") -DebugLevel:$true

# Arguments
Write-Log -LogLine ("Arg.ConfigFile: >$($ConfigFile)<") -DebugLevel:$true
Write-Log -LogLine ("Arg.MailTo: >$($MailTo)<") -DebugLevel:$true
Write-Log -LogLine ("Arg.Subject: >$($Subject)<") -DebugLevel:$true
Write-Log -LogLine ("Arg.Body: >$($Body)<") -DebugLevel:$true
Write-Log -LogLine ("Arg.DebugMode: >$($DebugMode)<") -DebugLevel:$true

# Sprawdzenie parametrów
if ( ([string]::IsNullOrWhiteSpace($ConfigFile)) -or ([string]::IsNullOrWhiteSpace($MailTo)) -or ([string]::IsNullOrWhiteSpace($Subject)) -or ([string]::IsNullOrWhiteSpace($Body)) )  {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage "One or more required parameters are empty." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}

$MailConfig = [PSCustomObject]@{
    SendMail = $false
    MailTo = ""
    MailCredentialsFileData = ""
    Subject = ""
    AttachLog = $false
    Attachement = ""
}

# sprawdza mail_to
# Adresy oddzielone ;
$MailConfig.MailTo = $MailTo -split ';'
# Usuwa puste wpisy i zbędne spacje
$MailConfig.MailTo = $MailConfig.MailTo | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
# Wyświeta adresy
$AddressCount=0
foreach ($Address in $MailConfig.MailTo) {
    $AddressCount += 1
    Write-Log -LogLine ("MailTo.Address: >$Address<") -DebugLevel:$true
}
# Wyświeta liczbę adresów
Write-Log -LogLine ("MailTo.Address.Count: >"+$AddressCount+"<") -DebugLevel:$true
if ($AddressCount -eq 0) {
    $ExitResult_local=$ExitDefinitions.Param
    Write-LogError -LogMessage "MailTo contains no valid recipients." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}

# sprawdza mail_credentials
try {
    $MailConfig.MailCredentialsFileData = Import-Clixml -Path $ConfigFile
} catch {
    $ExitResult_local=$ExitDefinitions.Param
    Write-LogError -LogMessage "Load ConfigFile." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}
Write-Log -LogLine ("CredentialsData.From: >$($MailConfig.MailCredentialsFileData.From)<") -DebugLevel:$true
Write-Log -LogLine ("CredentialsData.smtpServer: >$($MailConfig.MailCredentialsFileData.smtpServer)<") -DebugLevel:$true
Write-Log -LogLine ("CredentialsData.Port: >$($MailConfig.MailCredentialsFileData.Port)<") -DebugLevel:$true
Write-Log -LogLine ("CredentialsData.useSSL: >$($MailConfig.MailCredentialsFileData.useSSL)<") -DebugLevel:$true

# Mail Credentials
try {
    # konwersja blob na SecureString
    $SecurePassword = ConvertTo-SecureString $($MailConfig.MailCredentialsFileData.Password) -ErrorAction Stop
} catch {
    $ExitResult_local=$ExitDefinitions.MailCredentials
    Write-LogError -LogMessage "Mail Credentials." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}

# Send Mail
try {
    # mail credentials
    $credentials = New-Object System.Management.Automation.PSCredential ($($MailConfig.MailCredentialsFileData.From), $SecurePassword) -ErrorAction Stop
    # Kodowanie jako obiekt System.Text.Encoding
    $utf8 = [System.Text.Encoding]::UTF8
    # mail bez załącznika
    Send-MailMessage -From $($MailConfig.MailCredentialsFileData.From) -To $($MailConfig.MailTo) -Subject $Subject -Body $body -SmtpServer $($MailConfig.MailCredentialsFileData.smtpServer) -Port $($MailConfig.MailCredentialsFileData.Port) -UseSsl:$($MailConfig.MailCredentialsFileData.useSSL) -Credential $credentials -Encoding $utf8 -ErrorAction Stop
    Write-Log -LogLine ("Mail sent successfully") -WriteToHost:$true
} catch {
    $ExitResult_local=$ExitDefinitions.MailSend
    Write-LogError -LogMessage "Send Mail." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}

return $($ExitDefinitions.Success).Code

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
