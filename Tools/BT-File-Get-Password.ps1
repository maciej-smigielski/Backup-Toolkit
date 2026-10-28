<#
.SYNOPSIS
    BT-File-Get-Password.ps1 - Pobiera hasło z pliku konfiguracyjnego typu File Credentials.

.DESCRIPTION
    Skrypt odczytuje plik File Credentials typu XML, który zawiera zapisane hasło
    w formacie SecureString dla zasobu plikowego. 
    Następnie konwertuje zapisane hasło z formatu SecureString
    do tekstu jawnego i zwraca je na standardowym wyjściu jako wynik działania skryptu.

.PARAMETER ConfigFile
    Ścieżka do pliku konfiguracyjnego z danymi poświadczeń.
    Plik musi być w formacie File Credentials typu XML.

.EXAMPLE
    .\BT-File-Get-Password.ps1 -ConfigFile noname.file_credentials
    Odczytuje hasło z pliku z danymi poświadczeń i wyświetla je w oknie konsoli.

.EXAMPLE
    .\BT-File-Get-Password.ps1 -ConfigFile noname.file_credentials -Debug
    Uruchamia skrypt z włączonym trybem debugowania.

.OUTPUTS
    String
    Zwraca hasło w postaci tekstu jawnego po poprawnym odczytaniu danych z pliku.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-File-Get-Password.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-File-Credentials
    [Parameter(Position = 0)]
    [string]$ConfigFile             # zawiera File Credentials
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
    Success = @{ Code = ""; Message = "Completed successfully" }                    # Zakończono pomyślnie, wartość "" bo przez output zwracana jesy odczytana wartość
    Unhandled = @{ Code = 1; Message = "Unhandled exception" }                      # Nieobsłużony wyjątek, proces zatrzymany, w write-error wartość Code i Message wpisane jawnie 
    General = @{ Code = 101; Message = "General error, process stopped" }           # Ogólny błąd, proces zatrzymany
    Param = @{ Code = 102; Message = "Parameter error, process stopped" }           # Błąd parametru, proces zatrzymany
    Credentials = @{ Code = 103; Message = "Credentials error, process stopped" }   # Błąd odczytu poświadczeń, proces zatrzymany
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
Write-Log -LogLine ("Arg.DebugMode: >$($DebugMode)<") -DebugLevel:$true

# Sprawdzenie parametrów
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ExitResult_local=$ExitDefinitions.General
    Write-LogError -LogMessage "Parameter Arg.ConfigFile is empty." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$null `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    Exit $($ExitResult_local.Code)
}

$FileCredentialsFileData = ""

# sprawdza file_credentials
try {
    $FileCredentialsFileData = Import-Clixml -Path $ConfigFile
} catch {
    $ExitResult_local=$ExitDefinitions.Param
    Write-LogError -LogMessage "Load ConfigFile." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    return $($ExitResult_local.Code)
}
Write-Log -LogLine ("CredentialsData.File: >$($FileCredentialsFileData.File)<") -DebugLevel:$true

# Get file password
try {
    # konwersja blob na SecureString
    $SecurePassword = ConvertTo-SecureString $($FileCredentialsFileData.Password) -ErrorAction Stop

    # Konwersja SecureString do PlainText
    $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    )
} catch {
    $ExitResult_local=$ExitDefinitions.Credentials
    Write-LogError -LogMessage "Get File Password." -CallStackFrame:(Get-PSCallStack)[0] `
        -ErrorRecord:$_ `
        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
        -WriteToHost:$true
    return $($ExitResult_local.Code)
}

Write-Log -LogLine ($plainTextPassword) -WriteToHost:$true
return $($ExitDefinitions.Success).Code

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
