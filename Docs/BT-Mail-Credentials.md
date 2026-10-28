# BT-Mail-Credentials

Utility for creating and managing credential files used by Backup-Toolkit to send e-mail notifications through SMTP. Passwords are stored as encrypted `SecureString` blobs in XML files together with the SMTP connection settings and consumed on demand by automation scripts.

Encryption is bound to the Windows user and machine that created the file — a credential file copied to another host or user can still be opened, but **its stored password cannot be decrypted there**.

The utility runs as an interactive Windows Forms application — all operations (creating, opening, editing, setting the password, sending a test message, saving) are performed through a **graphical menu** with buttons and dialog windows. No manual XML editing is required.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Mail-Credentials` provides a controlled way to store SMTP credentials required by backup jobs to send notification e-mails, without embedding passwords in scripts, configuration files or scheduled task definitions.

Typical scenarios:

- Sending backup job reports and error notifications via SMTP.
- Reuse of one credential file across multiple scheduled jobs on the same host/user.
- Standardized credential management per host and user in multi-machine environments.
- Password rotation without editing automation code.
- Used by Backup-Toolkit automation to send status e-mails:
  - `BT-Mail-Send` reads the `BT-Mail-Credentials` file to obtain the SMTP server, port, sender address and encrypted password, and uses them to deliver the message. `BT-Mail-Send` is invoked by [BT-Shutdown](./BT-Shutdown.md) to dispatch shutdown notification e-mails.
  - `BT-Backup.ps1` and `BT-Plan.ps1` read the `BT-Mail-Credentials` file directly (without going through `BT-Mail-Send`) to send their own status and report e-mails.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/BT-Mail-Credentials.ps1` |
| CMD wrapper | `Tools/BT-Mail-Credentials.cmd` |
| Default configuration file extension | `.BT-Mail-Credentials` |
| Companion sender | `Tools/BT-Mail-Send.ps1` |

---

## Requirements

- Windows PowerShell 5.1
- Windows Forms (loaded automatically by the script)
- Write access to the target directory where the credential file will be stored
- Network access to the SMTP server (only required to verify the credentials with the **Test Mail** function)

Encryption is based on Windows DPAPI (via `ConvertFrom-SecureString`), so the credential file **can only be decrypted by the same user on the same machine** that created it.

---

## Process Overview

1. Script starts — with or without `-ConfigFile`.
2. If `-ConfigFile` is provided, the file is opened directly; otherwise the user chooses **New** or **Open**.
3. For **New**, the user picks a target path and filename; for **Open**, an existing credential file is selected.
4. The edit form is displayed with SMTP fields (`From`, password status, `smtpServer`, `Port`, `Use SSL`). The encrypted password value is kept separately from the displayed status.
5. Optionally the user clicks **Test Mail** to send a verification message using the current form values. The password must be non-empty and readable before the recipient dialog opens.
6. On save, the password is encrypted (`SecureString` + DPAPI) and the record is serialized to XML via `Export-Clixml`.
7. The saved file is later consumed by automation:
   - `BT-Mail-Send` reads the `BT-Mail-Credentials` file to deliver notification e-mails; it is invoked by [BT-Shutdown](./BT-Shutdown.md).
   - `BT-Backup.ps1` and `BT-Plan.ps1` read the `BT-Mail-Credentials` file directly to send their own notification e-mails.

Each credential file is a standalone XML record containing metadata, SMTP connection settings, sender address and the encrypted password.

---

## Parameters

### `-ConfigFile <path>`

Optional. Path to an existing credential file to open directly, skipping the New/Open dialog.

```powershell
./BT-Mail-Credentials.ps1 -ConfigFile "<CredentialsFolder>\account.host.user.BT-Mail-Credentials"
```

### `-Debug`

Enables verbose diagnostic output on the console.

```powershell
./BT-Mail-Credentials.ps1 -Debug
```

---

## Usage

### Create a new credential file

```powershell
./BT-Mail-Credentials.ps1
```

1. Choose **New**.
2. Pick a target folder and filename in the Save dialog.
3. Fill in `From` (sender address), `smtpServer`, `Port` and `Use SSL`.
4. Click **Set Password** and enter the password.
5. Optionally click **Test Mail** to verify the settings by sending a test message.
6. Click **Save**.

### Open and edit an existing file

```powershell
./BT-Mail-Credentials.ps1
```

Choose **Open**, select the credential file, edit fields, save.

### Open a specific file directly

```powershell
./BT-Mail-Credentials.ps1 -ConfigFile "<CredentialsFolder>\account.host.user.BT-Mail-Credentials"
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

- **Save dialog** — used when creating a new file. Pre-fills the default name `NoName.<COMPUTERNAME>.<USERNAME>.BT-Mail-Credentials` and filters by the `.BT-Mail-Credentials` extension.
- **Open dialog** — used when opening an existing file. Filters by the `.BT-Mail-Credentials` extension.

### Edit form

After a file is selected or created, the main editor window is displayed. It contains:

| Field / Control | Purpose |
| --- | --- |
| `HostName` (read-only) | Host that was used to save (encrypt) the password. |
| `Current HostName` (read-only) | Host on which the script is currently running. |
| `UserName` (read-only) | User that was used to save (encrypt) the password. |
| `Current UserName` (read-only) | User currently running the script. |
| `From` (editable) | Sender e-mail address used both as the SMTP account name and as the `From` header. |
| `Password` (read-only status) | Shows whether the password is empty, readable, or cannot be read; it does not display the encrypted blob. |
| `smtpServer` (editable) | Hostname or address of the SMTP server. |
| `Port` (editable, numeric) | SMTP port number (0–65535, defaults to 587). |
| `Use SSL` (editable, checkbox) | Whether to use SSL/TLS when connecting to the SMTP server. |
| **Show Password** | Opens a small window with the decrypted password. If the password is empty, shows `ERROR: (124) Password is empty` instead. A non-empty password can be shown only if decryption succeeds. |
| **Set Password** | Opens a masked input for entering a new password. **Cancel** or `Esc` closes the dialog without applying the new password. |
| **Test Mail** | First checks that the password is non-empty and readable. If it is empty, shows `ERROR: (124) Password is empty`; if it cannot be decoded, shows `ERROR: (123) Failed to decode password`. If valid, opens a recipient dialog and sends a test message using the current form values (`From`, password, `smtpServer`, `Port`, `Use SSL`). If sending fails, shows `ERROR: (125) Failed to send test mail`. **Cancel** or `Esc` closes the recipient dialog without sending. |
| **Save** | Persists the current form data to the credential file (updates timestamps and metadata). |
| **Close** | Closes the editor without saving further changes. |

Password status text is shown in English: `Password is empty` and `Password cannot be read` appear in dark orange; `Password is set and readable` appears in green. If the password is empty or cannot be decoded, **Test Mail** shows the corresponding error code and does not open the recipient dialog. Press `Esc` to close the **Show Password** window and message dialogs.

### Message dialogs

Informational and error messages (e.g. successful save, decryption failure, test mail sent, SMTP send failure) are shown as message windows, not as console output only. Press `Esc` to close these dialogs. This makes the utility suitable for operators working without a PowerShell console.

---

## File Naming Convention

Credential file names follow a fixed **four-segment standard**:

```text
<Name>.<COMPUTERNAME>.<USERNAME>.BT-Mail-Credentials
```

| Segment | Meaning |
| --- | --- |
| `<Name>` | Logical identifier of the credential (e.g. mail account or service name). Defaults to `NoName` when creating a new file. |
| `<COMPUTERNAME>` | Host on which the credential was created (matches `$env:COMPUTERNAME`). |
| `<USERNAME>` | User that created the credential (matches `$env:USERNAME`). |
| `BT-Mail-Credentials` | Fixed file extension identifying the file type. |

Example:

```text
NoName.HOST.USER.BT-Mail-Credentials
```

This convention makes it easy to identify the host and user context of each credential file, especially in shared credential folders.

Because `<COMPUTERNAME>` and `<USERNAME>` are embedded in the filename, `BT-Mail-Send` can **automatically select the correct credential file** for the current host and user at runtime — without any additional configuration — by matching `$env:COMPUTERNAME` and `$env:USERNAME` against the file name.

---

## Stored Data Model

Each credential file contains the following fields:

| Field | Description |
| --- | --- |
| `FileType` | Fixed value `BT-Mail-Credentials`. Used for validation on load. |
| `HostName` | Machine on which the credential was created. |
| `UserName` | User context of the creator. |
| `From` | Sender e-mail address / SMTP account name. |
| `Password` | Encrypted `SecureString` blob (DPAPI). |
| `smtpServer` | Hostname or address of the SMTP server. |
| `Port` | SMTP port number (default `587`). |
| `useSSL` | Boolean flag — whether to use SSL/TLS (default `True`). |
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
| `125` | Failed to send test mail |

Handled credential errors use `BT.Common`'s `Write-LogError` helper and are shown in message dialogs. Unexpected exceptions reach the top-level handler below and are emitted with `Write-Error` on the PowerShell error stream.

The entire script body is wrapped in a top-level `try` / `catch` block. Any exception that is not handled by the inner error paths is caught by that outer handler, which emits the following line via `Write-Error`:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because the script sets `$ErrorActionPreference = 'Stop'`, this `Write-Error` raises a terminating error and ends script execution. When run with `powershell -File`, PowerShell returns a nonzero process exit code (`1`), which the CMD wrapper propagates as `%ERRORLEVEL%`. `Write-Error` does not set `$LASTEXITCODE`. This is the fallback path for unexpected runtime errors that are not covered by the dedicated exit codes above.

---

## Integration Points

`BT-Mail-Credentials` is used by other Backup-Toolkit tools:

| Component | How it uses the credential |
| --- | --- |
| [BT-Mail-Send](./BT-Mail-Send.md) | Reads the credential file and uses the stored SMTP settings and decrypted password to send notification e-mails. |
| [BT-Shutdown](./BT-Shutdown.md) | Invokes `BT-Mail-Send` with a `BT-Mail-Credentials` file to dispatch shutdown notification e-mails. |
| [BT-Backup](./BT-Backup.md) | Reads the `BT-Mail-Credentials` file directly to send backup job status and report e-mails. |
| [BT-Plan](./BT-Plan.md) | Reads the `BT-Mail-Credentials` file directly to send plan execution reports. |

---

## Operational Recommendations

- Store credential files in a dedicated folder with restricted NTFS ACLs (e.g. `Credentials/`).
- Grant access only to the service account and administrators.
- Do not commit credential files to source control.
- Keep one credential file per host/user combination and per mail account.
- Rotate passwords periodically using the same GUI workflow, and re-run **Test Mail** to confirm the new password works.
- Do not copy credential files between machines — they cannot be decrypted elsewhere.
- Prefer providers that support application-specific passwords (e.g. Gmail App Passwords) instead of the account's primary password.
- Optionally associate the `.BT-Mail-Credentials` extension in Windows with `Tools/BT-Mail-Credentials.cmd`, so double-clicking a credential file opens it directly in the tool.

---

## Notes

- The script uses a Windows Forms GUI; it is not designed for headless execution.
- File contents are XML produced by `Export-Clixml`; they are not intended for manual editing.
- The default extension `BT-Mail-Credentials` is used to distinguish these files from other XML content in the toolkit.
- The **Test Mail** function requires network access to the SMTP server and shows error code `125` if the message cannot be sent.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Mail-Send](./BT-Mail-Send.md)
- [BT-File-Credentials](./BT-File-Credentials.md)
- [BT-Shutdown](./BT-Shutdown.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan](./BT-Plan.md)
- [Glossary](./Glossary.md)
