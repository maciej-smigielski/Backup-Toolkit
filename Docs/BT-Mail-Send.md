# BT-Mail-Send

Command-line helper that sends an e-mail message from PowerShell using SMTP settings and credentials stored in a `BT-Mail-Credentials` file. It is the headless counterpart of the interactive `BT-Mail-Credentials` editor and is used by other Backup-Toolkit components that need to dispatch notification e-mails without loading a GUI.

The stored password is decrypted with DPAPI at send time, so the script **must run under the same Windows user on the same machine** that originally saved the credential file — otherwise decryption fails and the message is not sent.

The utility is a **non-interactive console script**: it takes a credential file path, a recipient list, a subject and a body, sends the message via `Send-MailMessage` and returns a numeric exit code. It has no window, no prompts and no user interaction.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Mail-Send` provides a scriptable way to send notification e-mails from Backup-Toolkit automation, so that other tools can dispatch messages without duplicating the SMTP and credential-loading logic.

Typical scenarios:

- Sending shutdown notification e-mails from `BT-Shutdown`.
- Sending ad-hoc status or alert messages from scheduled tasks and jobs.
- Reusing one `BT-Mail-Credentials` file across multiple automation scripts on the same host/user.
- Delivering plain-text notifications with UTF-8 body without embedding SMTP passwords in scripts.
- Used by Backup-Toolkit automation:
  - `BT-Shutdown` invokes `BT-Mail-Send` to dispatch shutdown notification e-mails.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/BT-Mail-Send.ps1` |
| CMD wrapper | `Tools/BT-Mail-Send.cmd` |
| Input file extension | `.BT-Mail-Credentials` |
| Companion editor | `Tools/BT-Mail-Credentials.ps1` |

---

## Requirements

- Windows PowerShell 5.1
- Read access to the `BT-Mail-Credentials` file
- Network access to the SMTP server defined in the credential file
- The script must run under the **same Windows user on the same machine** that originally saved the credential file (DPAPI constraint)

No Windows Forms and no elevated privileges are required.

---

## Process Overview

1. Script starts with the mandatory arguments `-ConfigFile`, `-MailTo`, `-Subject` and `-Body`.
2. The console output encoding is switched to UTF-8.
3. The `-MailTo` string is split on `;`, trimmed and de-duplicated of empty entries; at least one recipient is required.
4. The credential file is loaded via `Import-Clixml`.
5. The stored `Password` blob is converted back to a `SecureString` via `ConvertTo-SecureString` (DPAPI) and wrapped in a `PSCredential`.
6. The message is sent with `Send-MailMessage` using `From`, `smtpServer`, `Port` and `useSSL` from the credential file and the `PSCredential` built above; the body is transmitted as UTF-8.
7. The script returns an exit code indicating success or the type of failure.

The script does **not** modify the credential file, does **not** send attachments and does **not** log the message body to disk.

---

## Parameters

### `-ConfigFile <path>`

**Required.** Path to an existing `BT-Mail-Credentials` file that provides SMTP settings and the encrypted password.

```powershell
./BT-Mail-Send.ps1 -ConfigFile "<CredentialsFolder>\account.host.user.BT-Mail-Credentials" -MailTo "user@example.com" -Subject "Test mail" -Body "Message body"
```

### `-MailTo <string>`

**Required.** One or more recipient e-mail addresses. Multiple recipients are separated by `;`; surrounding whitespace is trimmed and empty entries are ignored.

### `-Subject <string>`

**Required.** Subject line of the e-mail message.

### `-Body <string>`

**Required.** Plain-text body of the e-mail message. The body is transmitted with UTF-8 encoding.

### `-Debug`

Enables verbose diagnostic output on the console (script metadata, arguments, credential fields, parsed recipient list).

```powershell
./BT-Mail-Send.ps1 -ConfigFile ".\account.host.user.BT-Mail-Credentials" -MailTo "user@example.com" -Subject "Test mail" -Body "Message body" -Debug
```

---

## Usage

### Send a message to a single recipient

```powershell
./BT-Mail-Send.ps1 -ConfigFile ".\account.host.user.BT-Mail-Credentials" -MailTo "user@example.com" -Subject "Test mail" -Body "Job completed successfully."
```

### Send a message to multiple recipients

```powershell
./BT-Mail-Send.ps1 -ConfigFile ".\account.host.user.BT-Mail-Credentials" -MailTo "user@example.com;admin@example.com" -Subject "Test mail" -Body "Job completed successfully."
```

### Call from a CMD wrapper or scheduled task

```cmd
call "%~dp0..\Tools\BT-Mail-Send.cmd" -ConfigFile "%MAIL_CREDENTIALS%" -MailTo "%MAIL_TO%" -Subject "%MAIL_SUBJECT%" -Body "%MAIL_BODY%"
if not "%ERRORLEVEL%"=="0" echo Mail delivery failed with code %ERRORLEVEL%
```

The `.cmd` wrapper simply forwards all arguments to the PowerShell script with `-ExecutionPolicy Bypass`.

---

## Output

The script produces text on the standard PowerShell output stream:

| When | Content |
| --- | --- |
| Success | A single `Mail sent successfully` confirmation line. |
| Debug mode | Additional diagnostic lines (script path, version, arguments, parsed recipients, loaded SMTP fields) before the confirmation. |
| Failure | An `Error: (<code>)[<line>] <message>; <details>` line describing the failure. |

There is **no GUI, no prompt, no confirmation dialog** — the script is designed to be embedded in pipelines and scheduled jobs.

---

## Exit / Error Handling

Internal exit codes used by the script:

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully — the message was accepted by the SMTP server. |
| `1` | Unhandled exception. |
| `101` | General error, process stopped (e.g. any of `-ConfigFile`, `-MailTo`, `-Subject` or `-Body` is empty). |
| `102` | Configuration parameter error, process stopped (e.g. `-MailTo` produced no recipients after parsing, or the credential file cannot be loaded by `Import-Clixml`). |
| `103` | Mail credentials error, process stopped (the stored password cannot be decrypted — usually because the file was created by a different user or on a different host). |
| `104` | Mail send error, process stopped (SMTP delivery failed — e.g. authentication rejected, TLS handshake failed, network unreachable). |

Handled failures are formatted by `BT.Common`'s `Write-LogError`, written to the host, and returned with the documented exit code. They are not emitted to the PowerShell error stream. Unexpected exceptions reach the top-level handler below and are emitted with `Write-Error`.

The entire script body is wrapped in a top-level `try` / `catch` block. Any exception that is not handled by the inner error paths is caught by that outer handler, which emits the following line via `Write-Error`:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because it is written with `Write-Error`, PowerShell signals the failure on the error stream and sets `$LASTEXITCODE` / `%ERRORLEVEL%` to `1`. This is the fallback path for unexpected runtime errors that are not covered by the dedicated exit codes above; reaching this handler immediately terminates script execution.

---

## Integration Points

`BT-Mail-Send` is consumed by other Backup-Toolkit tools:

| Component | How it uses the script |
| --- | --- |
| [BT-Shutdown](./BT-Shutdown.md) | Invokes `BT-Mail-Send` with a `BT-Mail-Credentials` file to dispatch shutdown notification e-mails. |
| [BT-Mail-Credentials](./BT-Mail-Credentials.md) | Produces the `BT-Mail-Credentials` files that `BT-Mail-Send` reads. |

---

## Operational Recommendations

- Always call the script under the same Windows user and on the same host that created the credential file.
- Store `BT-Mail-Credentials` files in a dedicated folder with restricted NTFS ACLs (e.g. `Credentials/`).
- Prefer providers that support application-specific passwords (e.g. Gmail App Passwords) instead of the account's primary password.
- Ensure outbound access to the SMTP host and port defined in the credential file is allowed by the local firewall.
- Check `$LASTEXITCODE` (PowerShell) or `%ERRORLEVEL%` (CMD) after every invocation and treat any non-zero value as a hard failure.
- Do not copy credential files between machines — `BT-Mail-Send` will return a non-zero exit code because the password cannot be decrypted.
- Keep the message body free of secrets; the script does not encrypt the payload beyond the SMTP transport itself.

---

## Notes

- The script is headless and non-interactive; it never opens a window or prompts the user.
- Only plain-text bodies with UTF-8 encoding are supported by this version; attachments are not sent even though internal fields for them exist.
- The full recipient list is parsed from `-MailTo` at runtime — separators, whitespace and empty entries are normalised before delivery.

---

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [BT-Shutdown](./BT-Shutdown.md)
- [Glossary](./Glossary.md)
