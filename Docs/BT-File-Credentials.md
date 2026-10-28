# BT-File-Credentials

Utility for creating and managing credential files used by Backup-Toolkit to access protected file resources. Passwords are stored as encrypted `SecureString` blobs in XML files and consumed on demand by automation scripts.

Encryption is bound to the Windows user and machine that created the file — a credential file copied to another host or user can still be opened, but **its stored password cannot be decrypted there**.

The utility runs as an interactive Windows Forms application — all operations (creating, opening, editing, setting the password, saving) are performed through a **graphical menu** with buttons and dialog windows. No manual XML editing is required.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-File-Credentials` provides a controlled way to store credentials required by backup jobs, without embedding passwords in scripts, configuration files or scheduled task definitions.

Typical scenarios:

- Access to protected file shares used as backup sources.
- Reuse of one credential file across multiple scheduled jobs.
- Standardized credential management per host and user in multi-machine environments.
- Credential rotation without editing automation code.
- Used by Backup-Toolkit automation to unlock `BT-Rclone-Config` files — encrypted rclone configuration files stored in the standard `rclone.conf` format:
  - `BT-Backup` reads the `BT-File-Credentials` file directly to decrypt the associated `BT-Rclone-Config`.
  - `BT-Rclone-Config` obtains the password through `BT-File-Get-Password` to unlock its own encrypted configuration.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/BT-File-Credentials.ps1` |
| CMD wrapper | `Tools/BT-File-Credentials.cmd` |
| Default configuration file extension | `.BT-File-Credentials` |
| Companion reader | `Tools/BT-File-Get-Password.ps1` |

---

## Requirements

- Windows PowerShell 5.1
- Windows Forms (loaded automatically by the script)
- Write access to the target directory where the credential file will be stored

Encryption is based on Windows DPAPI (via `ConvertFrom-SecureString`), so the credential file **can only be decrypted by the same user on the same machine** that created it.

---

## Process Overview

1. Script starts — with or without `-ConfigFile`.
2. If `-ConfigFile` is provided, the file is opened directly; otherwise the user chooses **New** or **Open**.
3. For **New**, the user picks a target path and filename; for **Open**, an existing credential file is selected.
4. The edit form is displayed with the `File` field and a password status; the encrypted password value is kept separately from the displayed status.
5. On save, the password is encrypted (`SecureString` + DPAPI) and the record is serialized to XML via `Export-Clixml`.
6. The saved file is later consumed by automation:
   - `BT-Backup` reads the `BT-File-Credentials` file directly to decrypt the associated `BT-Rclone-Config`.
   - `BT-Rclone-Config` obtains the password through `BT-File-Get-Password` to unlock its own encrypted configuration.

Each credential file is a standalone XML record containing metadata, the target file/path and the encrypted password.

---

## Parameters

### `-ConfigFile <path>`

Optional. Path to an existing credential file to open directly, skipping the New/Open dialog.

```powershell
./BT-File-Credentials.ps1 -ConfigFile "<CredentialsFolder>\NoName.host.user.BT-File-Credentials"
```

### `-Debug`

Enables verbose diagnostic output on the console.

```powershell
./BT-File-Credentials.ps1 -Debug
```

---

## Usage

### Create a new credential file

```powershell
./BT-File-Credentials.ps1
```

1. Choose **New**.
2. Pick a target folder and filename in the Save dialog.
3. Fill in `File` (the protected path or file identifier).
4. Click **Set Password** and enter the password.
5. Click **Save**.

### Open and edit an existing file

```powershell
./BT-File-Credentials.ps1
```

Choose **Open**, select the credential file, edit fields, save.

### Open a specific file directly

```powershell
./BT-File-Credentials.ps1 -ConfigFile "<CredentialsFolder>\NoName.host.user.BT-File-Credentials"
```

---

## Graphical Menu

The script is fully driven by a **Windows Forms graphical interface**. There is no interactive text prompt in the console — all decisions and edits are made in dialog windows.

### Start menu

When the script is started without `-ConfigFile`, a small window is shown with three buttons:

| Button | Action |
| --- | --- |
| **New** | Opens a Save dialog to create a new credential file. |
| **Open** | Opens an Open dialog to select an existing credential file. |
| **Close** | Exits the script without changes. |

### File dialogs

- **Save dialog** — used when creating a new file. Pre-fills the default name `NoName.<COMPUTERNAME>.<USERNAME>.BT-File-Credentials` and filters by the `.BT-File-Credentials` extension.
- **Open dialog** — used when opening an existing file. Filters by the `.BT-File-Credentials` extension.

### Edit form

After a file is selected or created, the main editor window is displayed. It contains:

| Field / Control | Purpose |
| --- | --- |
| `HostName` (read-only) | Host that was used to save (encrypt) the password. |
| `Current HostName` (read-only) | Host on which the script is currently running. |
| `UserName` (read-only) | User that was used to save (encrypt) the password. |
| `Current UserName` (read-only) | User currently running the script. |
| `File` (editable) | Optional informational field, identifier of the protected file/resource. |
| `Password` (read-only status) | Shows whether the password is empty, readable, or cannot be read; it does not display the encrypted blob. |
| **Show Password** | Opens a small window with the decrypted password. If the password is empty, an `ERROR: (124) Password is empty` dialog is shown instead. A non-empty password can be shown only if decryption succeeds. |
| **Set Password** | Opens a masked input for entering a new password. **Cancel** or `Esc` closes the dialog without applying the new password. |
| **Save** | Persists the current form data to the credential file (updates timestamps and metadata). |
| **Close** | Closes the editor without saving further changes. |

Password status text is shown in English: `Password is empty` and `Password cannot be read` appear in dark orange; `Password is set and readable` appears in green. Press `Esc` to close the **Show Password** window and message dialogs.

### Message dialogs

Informational and error messages (e.g. successful save, decryption failure, invalid file type) are shown as message windows, not as console output only. Press `Esc` to close these dialogs. This makes the utility suitable for operators working without a PowerShell console.

---

## File Naming Convention

Credential file names follow a fixed **four-segment standard**:

```text
<Name>.<COMPUTERNAME>.<USERNAME>.BT-File-Credentials
```

| Segment | Meaning |
| --- | --- |
| `<Name>` | Logical identifier of the credential (e.g. remote/service name). Defaults to `NoName` when creating a new file. |
| `<COMPUTERNAME>` | Host on which the credential was created (matches `$env:COMPUTERNAME`). |
| `<USERNAME>` | User that created the credential (matches `$env:USERNAME`). |
| `BT-File-Credentials` | Fixed file extension identifying the file type. |

Example:

```text
NoName.HOST.USER.BT-File-Credentials
```

This convention makes it easy to identify the host and user context of each credential file, especially in shared credential folders.

Because `<COMPUTERNAME>` and `<USERNAME>` are embedded in the filename, `BT-Rclone-Config` can **automatically select the correct credential file** for the current host and user at runtime — without any additional configuration — by matching `$env:COMPUTERNAME` and `$env:USERNAME` against the file name.

---

## Stored Data Model

Each credential file contains the following fields:

| Field | Description |
| --- | --- |
| `FileType` | Fixed value `BT-File-Credentials`. Used for validation on load. |
| `HostName` | Machine on which the credential was created. |
| `UserName` | User context of the creator. |
| `File` | Optional informational field, identifier of the protected file/resource. |
| `Password` | Encrypted `SecureString` blob (DPAPI). |
| `CreateTimeStamp` | Creation date/time. |
| `ModifyTimeStamp` | Last modification date/time. |
| `ModifiedByVersion` | Script version that last wrote the file. |
| `ModifiedByUser` | User that last saved the file. |

Serialization uses `Export-Clixml` / `Import-Clixml`.

---

## Exit / Error Handling

Internal error codes used by the script:

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully |
| `1` | Unhandled exception |
| `101` | General error, process stopped |
| `121` | Read error |
| `122` | Write error |
| `123` | Failed to decode password |
| `124` | Password is empty |

Handled credential errors use `BT.Common`'s `Write-LogError` helper and are shown in message dialogs. Unexpected exceptions reach the top-level handler below and are emitted with `Write-Error` on the PowerShell error stream.

The entire script body is wrapped in a top-level `try` / `catch` block. Any exception that is not handled by the inner error paths is caught by that outer handler, which emits the following line via `Write-Error`:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because the script sets `$ErrorActionPreference = 'Stop'`, this `Write-Error` raises a terminating error and ends script execution. When run with `powershell -File`, PowerShell returns a nonzero process exit code (`1`), which the CMD wrapper propagates as `%ERRORLEVEL%`. `Write-Error` does not set `$LASTEXITCODE`. This is the fallback path for unexpected runtime errors that are not covered by the dedicated exit codes above.

---

## Integration Points

`BT-File-Credentials` is used by other Backup-Toolkit tools:

| Component | How it uses the credential |
| --- | --- |
| [BT-File-Get-Password](./BT-File-Get-Password.md) | Reads the credential file and returns the plain-text password. |
| [BT-Rclone-Config](./BT-Rclone-Config.md) | Obtains the password through `BT-File-Get-Password` to unlock its own encrypted rclone configuration. |
| [BT-Backup](./BT-Backup.md) | Runs backup jobs that require access to protected sources. |

---

## Operational Recommendations

- Store credential files in a dedicated folder with restricted NTFS ACLs (e.g. `Credentials/`).
- Grant access only to the service account and administrators.
- Do not commit credential files to source control.
- Keep one credential file per host/user combination and per type of encrypted file.
- Rotate passwords periodically using the same GUI workflow.
- Do not copy credential files between machines — they cannot be decrypted elsewhere.
- Optionally associate the `.BT-File-Credentials` extension in Windows with `Tools/BT-File-Credentials.cmd`, so double-clicking a credential file opens it directly in the tool.

---

## Notes

- The script uses a Windows Forms GUI; it is not designed for headless execution.
- File contents are XML produced by `Export-Clixml`; they are not intended for manual editing.
- The default extension `BT-File-Credentials` is used to distinguish these files from other XML content in the toolkit.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-File-Get-Password](./BT-File-Get-Password.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [BT-Rclone-Config](./BT-Rclone-Config.md)
- [BT-Backup](./BT-Backup.md)
- [Glossary](./Glossary.md)
