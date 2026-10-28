<#
.SYNOPSIS
    BT-Mail-Credentials.ps1 - Zarządzanie plikiem mail credentials

.DESCRIPTION
    Skrypt służy do zarządzania plikiem zawierającym poświadczenia mailowe
    wykorzystywane przez narzędzia Backup-Toolkit.
    Domyślny standard nazwy pliku credentials noname.HOSTNAME.USERNAME.BT-Mail-Credentials.

.PARAMETER Debug
    Włącza tryb debugowania i wyświetla dodatkowe informacje diagnostyczne.

.EXAMPLE
    .\BT-Mail-Credentials.ps1
    Uruchamia skrypt w trybie standardowym.

.EXAMPLE
    .\BT-Mail-Credentials.ps1 -Debug
    Uruchamia skrypt z włączonym trybem debugowania.

.NOTES
    Autor: Maciej-Smigielski
    Dokumentacja: Docs/BT-Mail-Credentials.md
#>

[CmdletBinding()]
param(
    # Wymagany plik konfiguracyjny w formacie BT-Mail-Credentials
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
    DecodePassword = @{ Code = 123; Message = "Failed to decode password" }         # Błąd dekodowania hasła
    EmptyPassword = @{ Code = 124; Message = "Password is empty" }                  # Hasło jest puste
    SentMail = @{ Code = 125; Message = "Failed to send test mail" }                # Błąd wysyłania testowego maila
}

# wartości domyślne dla pliku poświadczeń mailowych
$default_credentials_prefix = "NoName"
$default_credentials_extension = "BT-Mail-Credentials"

$CredentialsEmptyData = [PSCustomObject]@{
    FileType  = $default_credentials_extension
    HostName = "$env:COMPUTERNAME"
    UserName = "$env:USERNAME"
    From = ""
    Password = ""
    smtpServer = ""
    Port = 587
    useSSL = $True
    CreateTimeStamp = ""
    ModifyTimeStamp = ""
    ModifiedByVersion = "$ScriptVersion"
    ModifiedByUser = ""
}

$CredentialsFileName = $null
$CredentialsFileData = $null

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

function show-data {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$CFData  # CredentialsData
    )

    Write-Log -LogLine ("CredentialsData.FileType: >$($CFData.FileType)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.HostName: >$($CFData.HostName)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.UserName: >$($CFData.UserName)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.From: >$($CFData.From)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.Password: >$($CFData.Password)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.smtpServer: >$($CFData.smtpServer)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.Port: >$($CFData.Port)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.useSSL: >$($CFData.useSSL)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.CreateTimeStamp: >$($CFData.CreateTimeStamp)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.ModifyTimeStamp: >$($CFData.ModifyTimeStamp)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.ModifiedByVersion: >$($CFData.ModifiedByVersion)<") -DebugLevel:$true
    Write-Log -LogLine ("CredentialsData.ModifiedByUser: >$($CFData.ModifiedByUser)<") -DebugLevel:$true
}

function save-data {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$CFData,  # CredentialsData

        [Parameter(Mandatory)]
        [string]$CFName           # CredentialsFileName
    )

    try {
        $CFData | Export-Clixml -Path $CFName
    } catch {
        $ExitResult_local=$ExitDefinitions.Write
        Write-LogError -LogMessage ("Unable to save >$CFName<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return 1
    }

    return 0
}

function import-data {
    param(
        [Parameter(Mandatory)]
        [string]$CFName           # CredentialsFileName
    )

    try {
        $CFDataImported = Import-Clixml -Path $CFName
    } catch {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Unable to load >$CFName<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$_ `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    if ( ($null -eq $CFDataImported.PSObject.Properties['FileType']) -or ($($CFDataImported.FileType) -ne $($CredentialsEmptyData.FileType)) ) {
        $ExitResult_local=$ExitDefinitions.Read
        Write-LogError -LogMessage ("Missing or incorrect FileType definition in >$CFName<") -CallStackFrame:(Get-PSCallStack)[0] `
            -ErrorRecord:$null `
            -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
            -ShowDialogBox:$true
        return $null
    }

    $CFData = $CredentialsEmptyData.PSObject.Copy()
    foreach ($PropertyName in $CredentialsEmptyData.PSObject.Properties.Name) {
        if ($null -ne $CFDataImported.PSObject.Properties[$PropertyName]) {
            $CFData.$PropertyName = $CFDataImported.$PropertyName
        }
    }

    return $CFData
}

function edit-data {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$CFData,  # CredentialsData

        [Parameter(Mandatory)]
        [string]$CFName           # CredentialsFileName
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = [System.IO.Path]::GetFileName($CFName)
    $form.Size = New-Object System.Drawing.Size(700,340)
    $form.StartPosition = "CenterScreen"

    # Dodanie zdarzenia, aby okno miało fokus
    $form.Add_Shown({ $form.Activate() })

    # Etykiety i pola (bez useSSL w tablicy, bo będzie CheckBox)
    $labels = @("HostName","HostNameOpis","UserName","UserNameOpis","From","Password","smtpServer")
    $values = @($($CFData.HostName),"$env:COMPUTERNAME",$($CFData.UserName),"$env:USERNAME",$($CFData.From),$($CFData.Password),$($CFData.smtpServer))
    $controls = @{}

    for ($i=0; $i -lt $labels.Count; $i++) {
        $label = New-Object System.Windows.Forms.Label

        # Specjalne etykiety dla opisów
        if ($labels[$i] -eq "HostName") {
            $label.Text = "HostName:"
            $label.Location = New-Object System.Drawing.Point(10,20)
        } elseif ($labels[$i] -eq "HostNameOpis") {
            $label.Text = "Current HostName:"
            $label.Location = New-Object System.Drawing.Point(330,20)
        } elseif ($labels[$i] -eq "UserName") {
            $label.Text = "UserName:"
            $label.Location = New-Object System.Drawing.Point(10,50)
        } elseif ($labels[$i] -eq "UserNameOpis") {
            $label.Text = "Current UserName:"
            $label.Location = New-Object System.Drawing.Point(330,50)
        } elseif ($labels[$i] -eq "From") {
            $label.Text = "From:"
            $label.Location = New-Object System.Drawing.Point(10,80)
        } elseif ($labels[$i] -eq "Password") {
            $label.Text = "Password:"
            $label.Location = New-Object System.Drawing.Point(10,110)
        } elseif ($labels[$i] -eq "smtpServer") {
            $label.Text = "smtpServer:"
            $label.Location = New-Object System.Drawing.Point(10,140)
        } else {
            $label.Text = $labels[$i]
            $label.Location = New-Object System.Drawing.Point(10,(80+((($i-4))*30)))
        }

        $label.Size = New-Object System.Drawing.Size(110,20)
        $form.Controls.Add($label)

        # Tworzenie pola tekstowego
        $textbox = New-Object System.Windows.Forms.TextBox
        $textbox.Text = $values[$i]

        if ($labels[$i] -eq "HostName") {
            $textbox.Location = New-Object System.Drawing.Point(120,20)
            $textbox.Size = New-Object System.Drawing.Size(200,20)
            $textbox.ReadOnly = $true
            $textbox.BackColor = [System.Drawing.Color]::LightGray
        } elseif ($labels[$i] -eq "HostNameOpis") {
            $textbox.Location = New-Object System.Drawing.Point(450,20)
            $textbox.Size = New-Object System.Drawing.Size(200,20)
            $textbox.ReadOnly = $true
            $textbox.BackColor = [System.Drawing.Color]::LightGray
        } elseif ($labels[$i] -eq "UserName") {
            $textbox.Location = New-Object System.Drawing.Point(120,50)
            $textbox.Size = New-Object System.Drawing.Size(200,20)
            $textbox.ReadOnly = $true
            $textbox.BackColor = [System.Drawing.Color]::LightGray
        } elseif ($labels[$i] -eq "UserNameOpis") {
            $textbox.Location = New-Object System.Drawing.Point(450,50)
            $textbox.Size = New-Object System.Drawing.Size(200,20)
            $textbox.ReadOnly = $true
            $textbox.BackColor = [System.Drawing.Color]::LightGray
        } elseif ($labels[$i] -eq "Password") {
            $textbox.Location = New-Object System.Drawing.Point(120,110)
            $textbox.Size = New-Object System.Drawing.Size(200,20)
            $textbox.ReadOnly = $true
            $textbox.BackColor = [System.Drawing.Color]::LightGray
            $textbox.Tag = $values[$i]

            if ([string]::IsNullOrWhiteSpace($values[$i])) {
                $textbox.Text = "Password is empty"
                $textbox.ForeColor = [System.Drawing.Color]::FromArgb(138,58,0)
            } else {
                try {
                    $null = ConvertTo-SecureString $values[$i] -ErrorAction Stop
                    $textbox.Text = "Password is set and readable"
                    $textbox.ForeColor = [System.Drawing.Color]::FromArgb(0,85,31)
                } catch {
                    $textbox.Text = "Password cannot be read"
                    $textbox.ForeColor = [System.Drawing.Color]::FromArgb(138,58,0)
                }
            }
        } else {
            $textbox.Location = New-Object System.Drawing.Point(120,(80+((($i-4))*30)))
            $textbox.Size = New-Object System.Drawing.Size(200,20)
        }

        $form.Controls.Add($textbox)
        $controls[$labels[$i]] = $textbox
    }

    # Etykieta i NumericUpDown dla Port
    $lblSSL = New-Object System.Windows.Forms.Label
    $lblSSL.Text = "Port:"
    $lblSSL.Location = New-Object System.Drawing.Point(10,170)
    $lblSSL.Size = New-Object System.Drawing.Size(100,20)
    $form.Controls.Add($lblSSL)

    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Location = New-Object System.Drawing.Point(120,170)
    $numeric.Size = New-Object System.Drawing.Size(200,20)
    $numeric.Minimum = 0
    $numeric.Maximum = 65535
    $numeric.Value = $($CFData.Port)
    $form.Controls.Add($numeric)
    $controls["Port"] = $numeric

    # Etykieta i CheckBox dla useSSL
    $lblSSL = New-Object System.Windows.Forms.Label
    $lblSSL.Text = "Use SSL:"
    $lblSSL.Location = New-Object System.Drawing.Point(10,200)
    $lblSSL.Size = New-Object System.Drawing.Size(100,20)
    $form.Controls.Add($lblSSL)

    $chkSSL = New-Object System.Windows.Forms.CheckBox
    $chkSSL.Location = New-Object System.Drawing.Point(120,200)
    $chkSSL.Checked = $($CFData.useSSL)
    $form.Controls.Add($chkSSL)
    $controls["useSSL"] = $chkSSL

    # ShowPass button
    $btnShow = New-Object System.Windows.Forms.Button
    $btnShow.Text = "Show Password"
    $btnShow.Size = New-Object System.Drawing.Size(100,30)
    $btnShow.Location = New-Object System.Drawing.Point(450,110)
    $btnShow.Add_Click({
        Write-Log -LogLine ("Info: Show Password selected") -DebugLevel:$true

        $plainTextPassword = ""
        $passwordDecoded = $true
        if (-not [string]::IsNullOrWhiteSpace($controls["Password"].Tag)) {
            try {
                # konwersja blob na SecureString
                $SecurePassword = ConvertTo-SecureString $controls["Password"].Tag -ErrorAction Stop
                # Konwersja SecureString do PlainText
                $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
                )
            } catch {
                $ExitResult_local=$ExitDefinitions.DecodePassword
                Write-LogError -LogMessage "Unable to decode password." -CallStackFrame:(Get-PSCallStack)[0] `
                    -ErrorRecord:$_ `
                    -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                    -ShowDialogBox:$true
                $passwordDecoded = $false
            }
        } else {
            $ExitResult_local=$ExitDefinitions.EmptyPassword
            Write-LogError -LogMessage "" -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            $passwordDecoded = $false
        }

        if ($passwordDecoded) {
            # Tworzymy małe okno do pokazania hasła
            $editForm = New-Object System.Windows.Forms.Form
            $editForm.Text = "Password"
            $editForm.Size = New-Object System.Drawing.Size(300,150)
            $editForm.StartPosition = "CenterParent"

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = "Current Password:"
            $lbl.Location = New-Object System.Drawing.Point(10,20)
            $lbl.Size = New-Object System.Drawing.Size(100,20)
            $editForm.Controls.Add($lbl)

            $txtPass = New-Object System.Windows.Forms.TextBox
            $txtPass.Location = New-Object System.Drawing.Point(120,20)
            $txtPass.Size = New-Object System.Drawing.Size(150,20)
            $txtPass.Text = $plainTextPassword
            $txtPass.ReadOnly = $true
            $editForm.Controls.Add($txtPass)

            $btnOK = New-Object System.Windows.Forms.Button
            $btnOK.Text = "Close"
            $btnOK.Location = New-Object System.Drawing.Point(100,60)
            $btnOK.Add_Click({
                $editForm.Close()
            })
            $editForm.Controls.Add($btnOK)
            $editForm.CancelButton = $btnOK

            $editForm.ShowDialog()
        }
    })
    $form.Controls.Add($btnShow)

    # EditPass button
    $btnEditPass = New-Object System.Windows.Forms.Button
    $btnEditPass.Text = "Set Password"
    $btnEditPass.Size = New-Object System.Drawing.Size(100,30)
    $btnEditPass.Location = New-Object System.Drawing.Point(560,110)
    $btnEditPass.Add_Click({
        Write-Log -LogLine ("Info: Set Password selected") -DebugLevel:$true

        # Tworzymy małe okno do edycji hasła
        $editForm = New-Object System.Windows.Forms.Form
        $editForm.Text = "Password"
        $editForm.Size = New-Object System.Drawing.Size(300,150)
        $editForm.StartPosition = "CenterParent"

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "New Password:"
        $lbl.Location = New-Object System.Drawing.Point(10,20)
        $lbl.Size = New-Object System.Drawing.Size(100,20)
        $editForm.Controls.Add($lbl)

        $txtPass = New-Object System.Windows.Forms.TextBox
        $txtPass.Location = New-Object System.Drawing.Point(120,20)
        $txtPass.Size = New-Object System.Drawing.Size(150,20)
        $txtPass.Text = ""
        $txtPass.UseSystemPasswordChar = $true      # maskowanie hasła
        $editForm.Controls.Add($txtPass)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Location = New-Object System.Drawing.Point(100,60)
        $btnOK.Add_Click({
            if (-not ([string]::IsNullOrWhiteSpace($txtPass.Text))) {
                $SecurePassword = ConvertTo-SecureString ($txtPass.Text) -AsPlainText -Force
                $blobSecurePassword = ConvertFrom-SecureString $SecurePassword

                $controls["HostName"].Text = "$env:COMPUTERNAME"
                $controls["UserName"].Text = "$env:USERNAME"
                $controls["Password"].Tag = $blobSecurePassword
                $controls["Password"].Text = "Password is set and readable"
                $controls["Password"].ForeColor = [System.Drawing.Color]::FromArgb(0,85,31)
                $editForm.Close()
                Write-Log -LogLine ("Info: Password set") -DebugLevel:$true
            }
        })
        $editForm.Controls.Add($btnOK)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(180,60)
        $btnCancel.Add_Click({
            $editForm.Close()
        })
        $editForm.Controls.Add($btnCancel)
        $editForm.CancelButton = $btnCancel

        $editForm.ShowDialog()
    })
    $form.Controls.Add($btnEditPass)

    # Test mail button
    $btnTestMail = New-Object System.Windows.Forms.Button
    $btnTestMail.Text = "Test Mail"
    $btnTestMail.Size = New-Object System.Drawing.Size(100,30)
    $btnTestMail.Location = New-Object System.Drawing.Point(340,260)
    $btnTestMail.Add_Click({
        Write-Log -LogLine ("Info: Test Mail selected") -DebugLevel:$true

        if ([string]::IsNullOrWhiteSpace($controls["Password"].Tag)) {
            $ExitResult_local=$ExitDefinitions.EmptyPassword
            Write-LogError -LogMessage "Password is empty." -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$null `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            return
        }

        try {
            $null = ConvertTo-SecureString $controls["Password"].Tag -ErrorAction Stop
        } catch {
            $ExitResult_local=$ExitDefinitions.DecodePassword
            Write-LogError -LogMessage "Unable to decode password." -CallStackFrame:(Get-PSCallStack)[0] `
                -ErrorRecord:$_ `
                -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                -ShowDialogBox:$true
            return
        }

        # Tworzymy małe okno do edycji hasła
        $editForm = New-Object System.Windows.Forms.Form
        $editForm.Text = "Address"
        $editForm.Size = New-Object System.Drawing.Size(300,150)
        $editForm.StartPosition = "CenterParent"

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "Test Mail To:"
        $lbl.Location = New-Object System.Drawing.Point(10,20)
        $lbl.Size = New-Object System.Drawing.Size(100,20)
        $editForm.Controls.Add($lbl)

        $toaddr = New-Object System.Windows.Forms.TextBox
        $toaddr.Location = New-Object System.Drawing.Point(120,20)
        $toaddr.Size = New-Object System.Drawing.Size(150,20)
        $toaddr.Text = ""
        $editForm.Controls.Add($toaddr)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Location = New-Object System.Drawing.Point(100,60)
        $btnOK.Add_Click({
            if (-not ([string]::IsNullOrWhiteSpace($toaddr.Text))) {
                Write-Log -LogLine ("To: >"+($toaddr.Text)+"<") -DebugLevel:$true

                $subject = "Test "+($Script.basename)+" on $env:COMPUTERNAME"
                $body = "Test mail"

                try {
                    # konwersja blob na SecureString
                    $SecurePassword = ConvertTo-SecureString $controls["Password"].Tag -ErrorAction Stop
                    # mail credentials
                    $credentials = New-Object System.Management.Automation.PSCredential ($controls["From"].Text, $SecurePassword) -ErrorAction Stop
                    # sent mail
                    Send-MailMessage -From $controls["From"].Text -To $toaddr.Text -Subject $subject -Body $body -SmtpServer $controls["smtpServer"].Text -Port $controls["Port"].Value -UseSsl:$controls["useSSL"].Checked -Credential $credentials -ErrorAction Stop
                    Write-Log -LogLine ("Test Mail sent To: >"+($toaddr.Text)+"<") -ShowDialogBox:$true
                } catch {
                    $ExitResult_local=$ExitDefinitions.SentMail
                    Write-LogError -LogMessage ("Unable to send test mail to >$($toaddr.Text)<") -CallStackFrame:(Get-PSCallStack)[0] `
                        -ErrorRecord:$_ `
                        -ExitResult:$ExitResult_local -IncludeErrorMessage:$true `
                        -ShowDialogBox:$true
                }

                $editForm.Close()
            }
        })
        $editForm.Controls.Add($btnOK)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(180,60)
        $btnCancel.Add_Click({
            $editForm.Close()
        })
        $editForm.Controls.Add($btnCancel)
        $editForm.CancelButton = $btnCancel

        $editForm.ShowDialog()
    })
    $form.Controls.Add($btnTestMail)

    # Save button
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Size = New-Object System.Drawing.Size(100,30)
    $btnSave.Location = New-Object System.Drawing.Point(450,260)
    $btnSave.Add_Click({
        Write-Log -LogLine ("Info: Save selected") -DebugLevel:$true

        $FormCFData = $CredentialsEmptyData.PSObject.Copy()
        $FormCFData.HostName   = $controls["HostName"].Text
        $FormCFData.UserName   = $controls["UserName"].Text
        $FormCFData.From       = $controls["From"].Text
        $FormCFData.Password   = $controls["Password"].Tag
        $FormCFData.smtpServer = $controls["smtpServer"].Text
        $FormCFData.Port       = $controls["Port"].Value
        $FormCFData.useSSL     = $controls["useSSL"].Checked
        $FormCFData.CreateTimeStamp = $CFData.CreateTimeStamp  # timestamp z orygialnego pliku
        $FormCFData.ModifyTimeStamp = Get-Timestamp            # aktualny timestamp
        $FormCFData.ModifiedByVersion = $ScriptVersion
        $FormCFData.ModifiedByUser = "$env:USERNAME"
        show-data -CFData $FormCFData
        if ((save-data -CFData $FormCFData -CFName $CFName) -eq 0) {
            Write-Log -LogLine ("Saved CredentialsFileName: >$CredentialsFileName<") -ShowDialogBox:$true
        }
    })
    $form.Controls.Add($btnSave)

    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Size = New-Object System.Drawing.Size(100,30)
    $btnClose.Location = New-Object System.Drawing.Point(560,260)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $form.ShowDialog() | Out-Null
}

### Main script execution starts here

# Jeżeli podano plik konfiguracyjny, próba jego otwarcia
if (-not ([string]::IsNullOrWhiteSpace($ConfigFile))) {
    $CredentialsFileName = $ConfigFile
    Write-Log -LogLine ("Open CredentialsFileName: >$CredentialsFileName<") -DebugLevel:$true
    $CredentialsFileData = import-data -CFName $CredentialsFileName
    if ($null -eq $CredentialsFileData) {
        $CredentialsFileName = $null
    } else {
        show-data -CFData $CredentialsFileData
    }
}

$StopApp = $False
do {

    Write-Log -LogLine ("CredentialsFileName: >$CredentialsFileName<") -DebugLevel:$true
    if ([string]::IsNullOrWhiteSpace($CredentialsFileName)) {

        # Obsługa wyboru
        switch (Select-NewOrOpenFile -Title $Script.basename -Prompt "Select BT-Mail-Credentials configuration file.") {
            "New" {
                Write-Log -LogLine ("Info: Option New selected") -DebugLevel:$true

                $CredentialsFileName = Show-SaveFileDialog `
                    -Title "Create new BT-Mail-Credentials file" `
                    -Filter "Credentials files (*.$default_credentials_extension)|*.$default_credentials_extension|All files (*.*)|*.*" `
                    -DefaultFileName ($default_credentials_prefix+"."+($env:COMPUTERNAME)+"."+($env:USERNAME))
                if (-not ([string]::IsNullOrWhiteSpace($CredentialsFileName))) {
                    Write-Log -LogLine ("New CredentialsFileName: >$CredentialsFileName<") -DebugLevel:$true
                    $CredentialsFileData = $CredentialsEmptyData.PSObject.Copy()
                    $CredentialsFileData.CreateTimeStamp = Get-Timestamp
                    show-data -CFData $CredentialsFileData
                    if ((save-data -CFData $CredentialsFileData -CFName $CredentialsFileName) -ne 0) {
                        $CredentialsFileName = $null
                        $CredentialsFileData = $null
                    }
                } else {
                    Write-Log -LogLine ("Info: File New canceled") -DebugLevel:$true
                }

            }
            "Open" {
                Write-Log -LogLine ("Info: Option Open selected") -DebugLevel:$true

                $CredentialsFileName = Show-OpenFileDialog `
                    -Title "Open BT-Mail-Credentials file" `
                    -Filter "Credentials files (*.$default_credentials_extension)|*.$default_credentials_extension|All files (*.*)|*.*"
                if (-not ([string]::IsNullOrWhiteSpace($CredentialsFileName))) {
                    Write-Log -LogLine ("Open CredentialsFileName: >$CredentialsFileName<") -DebugLevel:$true
                    $CredentialsFileData = import-data -CFName $CredentialsFileName
                    if ($null -eq $CredentialsFileData) {
                        $CredentialsFileName = $null
                    } else {
                        show-data -CFData $CredentialsFileData
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

    } else {

        edit-data -CFData $CredentialsFileData -CFName $CredentialsFileName
        $StopApp= $True
 
    }

} while (-not $StopApp)

Write-Log -LogLine ("Info: Finish") -DebugLevel:$true
return $($ExitDefinitions.Success).Code

} catch {
    # Wyświetla nieobsłużony wyjątek, jeśli wystąpił w bloku try-catch
    write-error "Error: (1)[$(Split-Path -Leaf $($_.InvocationInfo.ScriptName)):$($_.InvocationInfo.ScriptLineNumber)/$(Split-Path -Leaf $((Get-PSCallStack)[0].ScriptName)):$((Get-PSCallStack)[0].ScriptLineNumber)] Unhandled exception: $($_.Exception.Message)"
}
