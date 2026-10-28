# BT-Rclone-Config

Utility for **managing rclone configuration files**. It lets the user create, edit and inspect encrypted or unencrypted `rclone.conf` files, launch the rclone web GUI, and encrypt or remove encryption from a configuration.

For encrypted configurations, a matching `BT-File-Credentials` file supplies the password to `rclone` at runtime through `BT-File-Get-Password`. The credentials file is optional when managing an unencrypted configuration, but is required to use an encrypted configuration or to encrypt or decrypt a file.

Encryption of the configuration is handled by `rclone`; the password is stored in a companion `BT-File-Credentials` file protected by Windows DPAPI. The file is bound to the Windows user and machine that created it, so it can only be read in that same user and machine context.

The utility uses an interactive PowerShell console menu and Windows Forms dialogs to select or create configuration files. The **g** menu action launches the rclone web GUI in a browser.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Rclone-Config` provides a controlled way to work with encrypted and unencrypted rclone configuration files. When encryption is used, it avoids exposing the password to the operator or passing the password itself on the command line.

Typical scenarios:

- Creating or editing an unencrypted configuration without a companion credentials file.
- Creating, editing, or viewing an encrypted configuration using its matching credentials file.
- Encrypting an existing configuration or removing its encryption.
- Launching the rclone web GUI for browser-based management.
- Viewing the raw configuration file for diagnostics; encrypted content remains unreadable.
- Used by Backup-Toolkit automation:
  - `BT-Backup` reads the companion `BT-File-Credentials` file directly and passes the decrypted password to `rclone` when running backup jobs against the encrypted configuration.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/BT-Rclone-Config.ps1` |
| CMD wrapper | `Tools/BT-Rclone-Config.cmd` |
| Default configuration file extension | `.BT-Rclone-Config` |
| Bundled rclone binary | `Tools/Utilities/Rclone/rclone.exe` |
| Password reader | `Tools/BT-File-Get-Password.cmd` |
| Companion credential editor | `Tools/BT-File-Credentials.ps1` |

---

## Requirements

- Windows PowerShell 5.1
- The bundled `rclone.exe` located under `Tools/Utilities/Rclone/`
- `Tools/BT-File-Get-Password.cmd` (installed automatically alongside `BT-Rclone-Config`; checked when the script starts)
- A matching `BT-File-Credentials` file created by `BT-File-Credentials.ps1` under the same Windows user on the same host, when using encrypted configurations or the **e**/**d** actions
- Network access to the remotes defined in the configuration (only for the `g)` GUI action and for any rclone command that touches a remote)

Encryption is handled by `rclone` for the configuration content and by Windows DPAPI for the password stored in the optional `BT-File-Credentials` file.

---

## Process Overview

1. `-ConfigFile` is optional. If it names an existing valid configuration, that file is opened; otherwise, the script offers **New**, **Open**, or **Close**.
2. **New** opens a save-file dialog and creates a `.BT-Rclone-Config` file; **Open** opens a file-selection dialog. The extension is validated case-insensitively.
3. The companion credentials path is derived as `<BaseNamePrefix>.<COMPUTERNAME>.<USERNAME>.BT-File-Credentials`. If the file is missing, the script continues and can manage an unencrypted configuration.
4. The script verifies that `rclone.exe` and `BT-File-Get-Password.cmd` are installed, then displays the configuration's encryption status and whether the credentials file exists.
5. The main menu offers **Config**, **Encrypt**, **Decrypt**, **Gui**, **View**, and **Quit**, regardless of whether the credentials file exists. **Encrypt** and **Decrypt** require that file; **Config** and **Gui** add `--password-command` only when it exists. A matching credentials file is needed for those actions to access an encrypted configuration.
6. After each action, the script refreshes the encryption status. The menu remains open until the user chooses **Quit**.
7. The script returns its own exit code; a non-zero code from an rclone action is reported but does not by itself close the menu.

The script does **not** modify the credentials file and does **not** cache the password anywhere on disk.

---

## Parameters

### `-ConfigFile <path>`

Optional path to an existing rclone configuration file. The extension must be `.BT-Rclone-Config` (case-insensitive). If omitted, use the file-selection dialog to open or create a configuration. To create a new file, select **New** and choose its location in the save-file dialog.

```powershell
./BT-Rclone-Config.ps1 -ConfigFile "<ConfigFolder>\remote.BT-Rclone-Config"
```

### `-Debug`

Enables verbose diagnostic output on the console (script metadata, arguments, resolved paths, computed credential file name, `rclone` command line).

```powershell
./BT-Rclone-Config.ps1 -ConfigFile ".\remote.BT-Rclone-Config" -Debug
```

---

## Usage

### Create or open a configuration

```powershell
./BT-Rclone-Config.ps1
```

Choose **New** to create a configuration or **Open** to select an existing one. An unencrypted configuration can be edited without a credentials file. To use an encrypted configuration, its matching credentials file must be available to the current Windows user on the current machine.

### Edit a configuration

```powershell
./BT-Rclone-Config.ps1 -ConfigFile ".\remote.BT-Rclone-Config"
```

Choose **Config** to launch the interactive `rclone config` menu. If a credentials file exists, the wrapper supplies it through `--password-command`; encrypted configurations require matching credentials to unlock.

### Encrypt or decrypt a configuration

Create a matching `BT-File-Credentials` file with `BT-File-Credentials.ps1`, then choose **Encrypt** to run `rclone config encryption set` or **Decrypt** to run `rclone config encryption remove`. These actions do not run if the credentials file is missing.

### Launch the rclone web GUI

```powershell
./BT-Rclone-Config.ps1 -ConfigFile ".\remote.BT-Rclone-Config"
```

Choose **Gui** — `rclone gui` starts and opens the web GUI in the default browser. For an encrypted configuration, the matching credentials file must be available to unlock it.

### View the raw configuration

```powershell
./BT-Rclone-Config.ps1 -ConfigFile ".\remote.BT-Rclone-Config"
```

Choose **View** — the configuration file is displayed page by page through `more`. Encrypted content remains encrypted and unreadable; use this action for diagnostics only.

### Call from a CMD wrapper

```cmd
call "%~dp0..\Tools\BT-Rclone-Config.cmd" -ConfigFile "%RCLONE_CONFIG%"
```

The `.cmd` wrapper forwards arguments to the PowerShell script with `-ExecutionPolicy Bypass`. The script is interactive and uses dialogs, so this workflow is intended for an interactive session, not an unattended scheduled task.

---

## Interactive Menu

The main menu is displayed in the PowerShell console after a configuration is selected. Windows Forms dialogs handle New/Open/Close selection and the save/open file pickers. Before the menu, the script reports whether the selected configuration is encrypted and whether the companion credentials file exists. Encrypted configurations and existing credentials files are shown as `Note` (cyan); unencrypted configurations and missing credentials files are shown as `Warning` (yellow).

| Option | Action |
| --- | --- |
| **c** | Launch `rclone config`. The password command is supplied only if the companion credentials file exists. |
| **e** | Encrypt the configuration with `rclone config encryption set`. Requires the companion credentials file. |
| **d** | Remove configuration encryption with `rclone config encryption remove`. Requires the companion credentials file. |
| **g** | Launch `rclone gui`. The password command is supplied only if the companion credentials file exists. |
| **v** | Display the raw configuration file with `more`. |
| **q** | Quit the script. |

Any input other than the listed options prints `Invalid option.` and the menu is re-displayed.

---

## File Naming Convention

Configuration file names follow a fixed **two-segment standard**:

```text
<Name>.BT-Rclone-Config
```

| Segment | Meaning |
| --- | --- |
| `<Name>` | Logical identifier of the configuration (e.g. remote or service name). Only the first dot-separated token of `<Name>` is used to derive the credential file. |
| `BT-Rclone-Config` | Fixed file extension identifying the file type. Validated case-insensitively. |

The companion credential file is derived automatically from `-ConfigFile`:

```text
<BaseNamePrefix>.<COMPUTERNAME>.<USERNAME>.BT-File-Credentials
```

| Segment | Meaning |
| --- | --- |
| `<BaseNamePrefix>` | The part of the configuration file base name before the first `.` (e.g. `rclone-test` for `rclone-test.config-a.BT-Rclone-Config`). |
| `<COMPUTERNAME>` | The current host (matches `$env:COMPUTERNAME`). |
| `<USERNAME>` | The current user (matches `$env:USERNAME`). |
| `BT-File-Credentials` | Fixed extension recognised by `BT-File-Get-Password`. |

Because `<COMPUTERNAME>` and `<USERNAME>` are embedded in the credential file name, `BT-Rclone-Config` automatically derives the matching credentials path for the current host and user. The credentials file is optional and its absence does not prevent opening an unencrypted configuration.

### Example 1: Single configuration

On host `HOST` under user `USER`:

| Configuration file | Derived credentials file |
| --- | --- |
| `.\rclone-test.BT-Rclone-Config` | `.\rclone-test.HOST.USER.BT-File-Credentials` |

### Example 2: Two configurations sharing credentials

Two configuration files in the same folder can share one credentials file when their base names have the same prefix before the first dot. For example, on host `HOST` under user `USER`:

| Configuration file | Derived credentials file |
| --- | --- |
| `.\rclone-test.config-a.BT-Rclone-Config` | `.\rclone-test.HOST.USER.BT-File-Credentials` |
| `.\rclone-test.config-b.BT-Rclone-Config` | `.\rclone-test.HOST.USER.BT-File-Credentials` |

The `config-a` and `config-b` suffixes distinguish the configurations but do not affect credentials lookup. If both configurations are encrypted, they must use the same password stored in the shared credentials file.

---

## Rclone Invocation

Rclone actions use `--config <file> --ask-password=false`. When the companion credentials file exists, **Config** and **Gui** also pass a `--password-command` that invokes `BT-File-Get-Password.cmd`. The password itself is not passed as a command-line argument. **Encrypt** and **Decrypt** require the credentials file.

Per-action mapping:

| Menu action | rclone command |
| --- | --- |
| **c** | `rclone --config "<ConfigFile>" config --ask-password=false`; includes `--password-command "..."` when the credentials file exists. |
| **e** | `rclone --config "<ConfigFile>" config encryption set --ask-password=false --password-command "..."` (requires credentials). |
| **d** | `rclone --config "<ConfigFile>" config encryption remove --ask-password=false --password-command "..."` (requires credentials). |
| **g** | `rclone --config "<ConfigFile>" gui --ask-password=false`; includes `--password-command "..."` when the credentials file exists. |
| **v** | `more "<ConfigFile>"` (no rclone invocation). |

The wrapper logs `Rclone executed successfully.` when an rclone command exits with code `0`, or `Rclone execution failed with exit code: <code>` otherwise. An rclone failure does not close the menu or become the script's exit code.

---

## Exit / Error Handling

Internal exit codes used by the script:

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully — the user quit the menu after any number of actions. |
| `1` | Unhandled exception. |
| `101` | General startup error. Missing `rclone.exe` or `BT-File-Get-Password.cmd` stops the script. |
| `121` | Read or configuration-file validation error, such as an empty file name, unsupported extension, missing file, or a path that points to a directory. The error is reported and file selection is shown again. |
| `122` | Configuration-file write error, such as failure to create the selected file. The error is reported and file selection is shown again. |
| `123` | Rclone command error. The failure and rclone's exit code are logged; the menu remains active and the wrapper does not return `123` as its own exit code. |

Handled validation and action errors are formatted by `Write-LogError` and written to the console. Read and write errors while selecting or creating a configuration return the user to file selection; rclone action errors leave the menu active. These handled log messages are not themselves written to the PowerShell error stream. Unexpected exceptions reach the top-level handler described below and are emitted with `Write-Error`.

The entire script body is wrapped in a top-level `try` / `catch` block. Any exception that is not handled by the inner error paths is caught by that outer handler, which emits the following line via `Write-Error`:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because it is written with `Write-Error`, PowerShell signals the failure on the error stream and sets `$LASTEXITCODE` / `%ERRORLEVEL%` to `1`. This is the fallback path for unexpected runtime errors that are not covered by the dedicated exit codes above; reaching this handler immediately terminates script execution.

Non-zero exit codes returned by `rclone` itself (e.g. wrong password, corrupted configuration, unreachable remote) are logged but **do not** stop the wrapper — the interactive menu is redisplayed.

---

## Integration Points

`BT-Rclone-Config` is used by other Backup-Toolkit tools:

| Component | How it uses the script |
| --- | --- |
| [BT-File-Credentials](./BT-File-Credentials.md) | Produces the optional `BT-File-Credentials` file used to access encrypted configurations and perform encryption/decryption actions. |
| [BT-File-Get-Password](./BT-File-Get-Password.md) | Invoked by rclone (through `--password-command`) to retrieve the password from `BT-File-Credentials` at runtime when needed. |
| [BT-Backup](./BT-Backup.md) | Uses the encrypted `BT-Rclone-Config` file for actual backup runs, reading the associated `BT-File-Credentials` file directly to unlock it. |

---

## Operational Recommendations

- Create the `BT-File-Credentials` file on the same host and under the same Windows user that will access an encrypted configuration or run **Encrypt**/**Decrypt**.
- Protect configuration files with appropriate NTFS permissions. Unencrypted rclone configurations may contain sensitive remote credentials.
- Keep encrypted `.BT-Rclone-Config` and matching `.BT-File-Credentials` files side by side in a dedicated folder with restricted NTFS ACLs (e.g. `Credentials/`).
- Do not commit configuration or credentials files to source control.
- To rotate an encryption password, remove encryption with **Decrypt** while the old credentials are available, update the credentials file, then apply encryption again with **Encrypt**.
- The credentials file is DPAPI-bound to its original Windows user and machine; copying it elsewhere does not make it usable there.
- Use the **View** action for diagnostics only. Encrypted configuration contents remain unreadable; unencrypted contents may expose sensitive data.
- Optionally associate the `.BT-Rclone-Config` extension in Windows with `Tools/BT-Rclone-Config.cmd` so that double-clicking a configuration file opens it directly in the wrapper.

---

## Notes

- The wrapper uses a text menu on the PowerShell console and Windows Forms dialogs for file selection; only the **g** action launches the rclone web GUI in a browser.
- The credentials file path is computed from the selected configuration file and current environment; it cannot be overridden through a parameter.
- `rclone.exe` is expected to be present under `Tools/Utilities/Rclone/`; if it is missing, the script exits with a non-zero exit code before showing the menu.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-File-Credentials](./BT-File-Credentials.md)
- [BT-File-Get-Password](./BT-File-Get-Password.md)
- [BT-Backup](./BT-Backup.md)
- [Glossary](./Glossary.md)
