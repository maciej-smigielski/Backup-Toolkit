# BT-File-Get-Password

Command-line helper that reads a `BT-File-Credentials` file, decrypts the stored password and writes it to standard output as plain text. It is the headless counterpart of the interactive `BT-File-Credentials` editor and is used by other Backup-Toolkit components that need the password at runtime without loading a GUI.

Decryption is bound to the Windows user and machine that created the credential file — if the file is executed on another host or under another user, decryption fails and the password is **not** returned.

The utility is a **non-interactive console script**: it takes a credential file path, prints the decrypted password on `stdout` and returns a numeric exit code. It has no window, no prompts and no user interaction.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-File-Get-Password` provides a scriptable way to retrieve a password stored in a `BT-File-Credentials` file, so that other tools can consume it directly in a pipeline without duplicating the decryption logic.

Typical scenarios:

- Passing the decrypted password to `rclone` to unlock an encrypted `BT-Rclone-Config` file.
- Reusing a single credential file across multiple automation scripts on the same host/user.
- Retrieving the password on demand from scheduled jobs without embedding it in code or configuration.
- Used by Backup-Toolkit automation:
  - `BT-Rclone-Config` invokes `BT-File-Get-Password` to obtain the password that unlocks its own encrypted `rclone.conf`.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/BT-File-Get-Password.ps1` |
| CMD wrapper | `Tools/BT-File-Get-Password.cmd` |
| Input file extension | `.BT-File-Credentials` |
| Companion editor | `Tools/BT-File-Credentials.ps1` |

---

## Requirements

- Windows PowerShell 5.1
- Read access to the `BT-File-Credentials` file
- The script must run under the **same Windows user on the same machine** that originally saved the credential file (DPAPI constraint)

No Windows Forms, no network access and no elevated privileges are required.

---

## Process Overview

1. Script starts with a mandatory `-ConfigFile` argument.
2. The console output encoding is switched to UTF-8.
3. The credential file is loaded via `Import-Clixml`.
4. The stored `Password` blob is converted back to a `SecureString` via `ConvertTo-SecureString` (DPAPI).
5. The `SecureString` is marshalled to a plain-text string.
6. The plain-text password is written to standard output (`Write-Host`).
7. The script returns an exit code indicating success or the type of failure.

The script does **not** modify the credential file and does **not** cache the password anywhere on disk.

---

## Parameters

### `-ConfigFile <path>`

**Required.** Path to an existing `BT-File-Credentials` file to read.

```powershell
./BT-File-Get-Password.ps1 -ConfigFile "<CredentialsFolder>\NoName.host.user.BT-File-Credentials"
```

### `-Debug`

Enables verbose diagnostic output on the console (script metadata, arguments, loaded fields). The decrypted password is always written on the last output line regardless of this flag.

```powershell
./BT-File-Get-Password.ps1 -ConfigFile ".\example.BT-File-Credentials" -Debug
```

---

## Usage

### Retrieve a password on the console

```powershell
./BT-File-Get-Password.ps1 -ConfigFile ".\example.BT-File-Credentials"
```

The plain-text password is printed on `stdout`.

### Capture the password into a variable

```powershell
$password = ./BT-File-Get-Password.ps1 -ConfigFile ".\example.BT-File-Credentials"
```

On success `$password` contains the decrypted password. On failure the script writes an error line to the host and returns a non-zero exit code — check `$LASTEXITCODE` before using the value.

### Call from a CMD wrapper or scheduled task

```cmd
call "%~dp0..\Tools\BT-File-Get-Password.cmd" -ConfigFile "%CREDENTIALS_FILE%"
```

The `.cmd` wrapper simply forwards all arguments to the PowerShell script with `-ExecutionPolicy Bypass`.

---

## Output

The script produces text on the standard PowerShell output stream:

| When | Content |
| --- | --- |
| Success | The decrypted password as a single plain-text line. |
| Debug mode | Additional diagnostic lines (script path, version, arguments, loaded `File` field) before the password. |
| Failure | An `Error: (<code>)[<line>] <message>; <details>` line describing the failure. |

There is **no GUI, no prompt, no confirmation dialog** — the script is designed to be embedded in pipelines and scheduled jobs.

---

## Exit / Error Handling

Internal exit codes used by the script:

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully — the password was written to standard output. |
| `1` | Unhandled exception. |
| `101` | General error, process stopped (e.g. `-ConfigFile` parameter is empty). |
| `102` | Parameter error, process stopped (e.g. the credential file cannot be loaded by `Import-Clixml`). |
| `103` | Credentials error, process stopped (the stored password cannot be decrypted — usually because the file was created by a different user or on a different host). |

Handled failures are formatted by `BT.Common`'s `Write-LogError`, written to the host, and returned with the documented exit code. They are not emitted to the PowerShell error stream. Unexpected exceptions reach the top-level handler below and are emitted with `Write-Error`.

The entire script body is wrapped in a top-level `try` / `catch` block. Any exception that is not handled by the inner error paths is caught by that outer handler, which emits the following line via `Write-Error`:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because it is written with `Write-Error`, PowerShell signals the failure on the error stream and sets `$LASTEXITCODE` / `%ERRORLEVEL%` to `1`. This is the fallback path for unexpected runtime errors that are not covered by the dedicated exit codes above; reaching this handler immediately terminates script execution.

---

## Integration Points

`BT-File-Get-Password` is consumed by other Backup-Toolkit tools:

| Component | How it uses the script |
| --- | --- |
| [BT-Rclone-Config](./BT-Rclone-Config.md) | Invokes `BT-File-Get-Password` to obtain the password that unlocks its own encrypted `rclone.conf`. |
| [BT-File-Credentials](./BT-File-Credentials.md) | Produces the `BT-File-Credentials` files that `BT-File-Get-Password` reads. |

---

## Operational Recommendations

- Always call the script under the same Windows user and on the same host that created the credential file.
- Do not persist the decrypted password to disk — pass it directly to the consuming command and discard the variable as soon as possible.
- Store `BT-File-Credentials` files in a dedicated folder with restricted NTFS ACLs (e.g. `Credentials/`).
- Redirect only the last output line to the consumer when running with `-Debug`, so that diagnostic messages are not mistaken for the password.
- Check `$LASTEXITCODE` (PowerShell) or `%ERRORLEVEL%` (CMD) after every invocation and treat any non-zero value as a hard failure.
- Do not copy credential files between machines — `BT-File-Get-Password` will return a non-zero exit code.

---

## Notes

- The script is headless and non-interactive; it never opens a window or prompts the user.
- It does not write the password to any log file — diagnostic output is limited to script metadata and error messages.
- Consumers must handle the plain-text password securely; once it leaves this script, protection is the caller's responsibility.

---

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-File-Credentials](./BT-File-Credentials.md)
- [BT-Rclone-Config](./BT-Rclone-Config.md)
- [Glossary](./Glossary.md)
