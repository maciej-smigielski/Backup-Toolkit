# BT.Common

Shared PowerShell 5.1 module used by the core runtime tools and supporting utilities, including `BT-Backup`, `BT-Plan`, `BT-File-Credentials`, `BT-Mail-Credentials`, `BT-File-Get-Password`, `BT-Mail-Send`, and `BT-Rclone-Config`. It bundles common building blocks that scripts should not reimplement:

- a shared `$BTCommon` PSCustomObject for communication between the module and its consumers,
- a common logger with e-mail hooks (`Write-Log`, `Write-LogError`),
- a message dialog with a caller-supplied title and message (`Show-MessageDialog`),
- save and open file dialogs with caller-supplied titles and filters; the save dialog also accepts a default filename and both return the selected path or `$null` if canceled,
- a New/Open/Close choice dialog with a caller-supplied title and prompt (`Select-NewOrOpenFile`),
- a common timestamp format,
- helpers for reading shutdown events from the Windows System log and checking whether shutdown is pending,
- session and coordinator lock helpers, plus session temporary directory helpers,
- formatting helpers for elapsed time and byte size,
- a controlled exit routine that respects the `NoPause` / non-interactive contract.

The module is loaded by every consumer script via `Import-Module` and exposes both its state variable and its functions.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT.Common` exists so that every Backup-Toolkit script sees the same logging, locking and cleanup semantics without copy-pasting boilerplate. Concretely it lets a script:

- initialise a session by calling `Initialize-BTCommon` (sets `NoPause`, `DebugMode`, `DebugToConsole`, and `ApplicationTitle` on `$BTCommon`),
- write a single line to console, log file and outgoing mail body with one `Write-Log` call,
- turn any caught exception into a uniform `Error: (code)[file:line/…]` line via `Write-LogError`,
- show a message dialog or prompt for a file path through shared Windows Forms helpers,
- create timestamps in the common `yyyy-MM-dd HH:mm:ss` format with `Get-Timestamp`,
- read shutdown events since boot with `Get-ShutdownEventsSinceBoot` and determine pending shutdown state with `Test-ShutdownPending`,
- acquire and release a per-session lock file that records `PID`, `COMMAND` and `LOG`,
- acquire and release a coordinator lock file derived from the lock directory name,
- create and reliably clean up a per-session temporary directory (with retry),
- format durations (`Get-ElapsedDurationString`) and byte sizes (`Format-ByteSizeString`) consistently across summary lines and logs,
- exit with a stable exit code while honouring `NoPause` / `NonInteractive` (`Exit-Pause`).

The module does **not** manage backup semantics (rclone, plans, credentials); those live in the individual tools.

---

## Location

| Item | Path |
| --- | --- |
| Module manifest | `Tools/Modules/BT.Common/BT.Common.psd1` |
| Module script | `Tools/Modules/BT.Common/BT.Common.psm1` |
| Related documentation | `Docs/Glossary.md` |

---

## Requirements

- Windows PowerShell 5.1
- Read access to the Windows System event log is required when using the shutdown event helpers.
- Windows Forms is required when using the dialog helpers.
- `Set-StrictMode -Version Latest` compatible callers (the module runs in strict mode itself)

No network access. No external modules.

---

## Module State — `$BTCommon`

The module exports a single `PSCustomObject` named `$BTCommon` that carries the session state between the module and its consumers:

- `NoPause` — pause flag for `Exit-Pause`; set by `Initialize-BTCommon`.
- `DebugMode` — enables `-DebugLevel` log lines; set by `Initialize-BTCommon`.
- `DebugToConsole` — writes debug-level lines to the console; set by `Initialize-BTCommon`.
- `ApplicationTitle` — title used by message dialogs requested through the logger; set by `Initialize-BTCommon`.
- `LogDir` — session log directory; set by the consumer script.
- `LogFile` — session log file; set by the consumer script.
- `MailBody` — accumulated `Segment`/`Line` entries for the outgoing mail; filled by `Write-Log`.
- `LockDir` — session lock directory; set by the consumer script.
- `SessionLockFile` — session lock file path; set by the consumer script.
- `SessionLockFileHandle` — open handle held while the session lock is active; set by `Open-SessionLockFile`.
- `CoordinatorLockFile` — coordinator lock file path; derived from `LockDir` by `Open-CoordinatorLockFile`.
- `CoordinatorLockFileHandle` — open handle held while the coordinator lock is active; set by `Open-CoordinatorLockFile`.
- `TempDir` — parent temp directory; set by the consumer script.
- `ProcessTempDir`, `ProcessTempDirCreated` — per-session temp folder and its created flag; set by `Initialize-SessionTemporaryDirectory`.

`$BTCommon` is exported by `Export-ModuleMember -Variable BTCommon`, so all assignments in a consumer script mutate the module's own state.

---

## Lock Files

The session lock path is supplied by the consumer in `SessionLockFile`. `Open-SessionLockFile` writes `PID`, `COMMAND` and `LOG`, then keeps the file open with `FileShare.Read`; `Close-SessionLockFile` closes the handle and deletes the file.

The coordinator lock is separate. `Open-CoordinatorLockFile` derives its filename from the leaf name of `LockDir`, prefixes it with a dot, and places it inside `LockDir`. It writes the same metadata and keeps the file open with `FileShare.Read`; `Close-CoordinatorLockFile` closes the handle and deletes it.

---

## Exit Definitions — `$BTCommonExitDefinitions`

The module publishes a hashtable of exit codes it may raise from its helpers:

| Key | Code | Message |
| --- | --- | --- |
| `BTCommonCoordinatorLock` | 801 | Coordinator lock process failed |
| `BTCommonCoordinatorUnlock` | 802 | Coordinator unlock process failed |
| `BTCommonSessionLock` | 803 | Session lock process failed |
| `BTCommonSessionUnlock` | 804 | Session unlock process failed |
| `BTCommonSessionTempDirCreate` | 805 | Temporary directory creation failed |
| `BTCommonSessionTempDirRemove` | 806 | Temporary directory cleanup failed |
| `BTCommonShutdownStarted` | 807 | Operating system is shutting down |
| `BTCommonShutdownPending` | 808 | Operating system shutdown is pending |

Lock and temporary-directory helpers return `$null` on success or one of these definitions on failure. `Test-ShutdownPending` returns `$null` when no shutdown is pending, otherwise `BTCommonShutdownStarted` or `BTCommonShutdownPending`. Consumer scripts propagate the returned object into their own exit / error handling.

---

## Functions

- `Initialize-BTCommon` — sets `NoPause`, `DebugMode`, `DebugToConsole`, and `ApplicationTitle` on `$BTCommon`.
- `Exit-Pause` — exits the script with the given code, pausing for Enter only when `$BTCommon.NoPause -eq $false`.
- `Write-Log` — writes one line to any combination of host, log file and mail body, with an optional debug level and `-ShowDialogBox` option. A `-DebugLevel` line reaches the console only when both `DebugMode` and `DebugToConsole` are enabled.
- `Write-LogError` — builds a uniform error / warning line (with call-stack and optional exit code), forwards it to `Write-Log`, and supports `-ShowDialogBox`.
- `Get-ShutdownEventsSinceBoot` — reads Windows System log events since the last boot: shutdown requests (1074), cancellations (1075), and shutdown-start events (13). Returns objects with `RecordId`, `TimeCreated`, `Id`, `Description`, and `Message`, and writes diagnostic details through `Write-Log`.
- `Test-ShutdownPending` — returns `$null` when no shutdown is pending; returns `BTCommonShutdownStarted` if shutdown has started (event 13), or `BTCommonShutdownPending` if the latest shutdown request (event 1074) has not been followed by a cancellation (event 1075).
- `Open-CoordinatorLockFile` — derives and creates the coordinator lock file in `LockDir`, retrying up to 30 times at one-second intervals; logs the successful attempt number, writes `PID`, `COMMAND` and `LOG`, and keeps its handle open.
- `Close-CoordinatorLockFile` — releases the coordinator lock handle and deletes the coordinator lock file.
- `Open-SessionLockFile` — creates the session lock file with `PID`, `COMMAND` and `LOG`, and keeps the handle open.
- `Close-SessionLockFile` — releases the handle and deletes the session lock file.
- `Initialize-SessionTemporaryDirectory` — creates a per-session `<TempDir>/{GUID}` folder.
- `Remove-SessionTemporaryDirectory` — deletes the per-session temp folder, retrying on transient failures.
- `Get-ElapsedDurationString` — formats an elapsed time as a compact `d h m s` string.
- `Format-ByteSizeString` — formats a byte count as `B`, `KiB`, `MiB`, `GiB` or `TiB`.
- `Get-Timestamp` — returns the current time as `yyyy-MM-dd HH:mm:ss`.
- `Show-MessageDialog` — shows a message using the supplied `-Title` and `-Message`.
- `Show-ConfirmationDialog` — asks for confirmation using `-Title` and `-Message`; returns `$true` when confirmed, otherwise `$false`.
- `Show-SaveFileDialog` — shows a save dialog with `-Title`, `-Filter`, and `-DefaultFileName`; returns the selected path or `$null` if canceled.
- `Show-OpenFileDialog` — shows an open dialog with `-Title` and `-Filter`; returns the selected path or `$null` if canceled.
- `Select-NewOrOpenFile` — displays New/Open/Close choices using `-Title` and `-Prompt`; returns `New`, `Open`, or `Close`.

---

## Exported Members

`Export-ModuleMember` declares the public surface explicitly:

- **Functions**: `Initialize-BTCommon`, `Exit-Pause`, `Write-Log`, `Write-LogError`, `Get-ShutdownEventsSinceBoot`, `Test-ShutdownPending`, `Open-CoordinatorLockFile`, `Close-CoordinatorLockFile`, `Open-SessionLockFile`, `Close-SessionLockFile`, `Initialize-SessionTemporaryDirectory`, `Remove-SessionTemporaryDirectory`, `Get-Timestamp`, `Get-ElapsedDurationString`, `Format-ByteSizeString`, `Show-MessageDialog`, `Show-ConfirmationDialog`, `Show-SaveFileDialog`, `Show-OpenFileDialog`, `Select-NewOrOpenFile`.
- **Variables**: `BTCommon`, `BTCommonExitDefinitions`.

Members not on these lists (e.g. internal helpers, `$BTCommonExitDefinitions` keys used only inside the module) are inaccessible from the consumer scope.

---

## Integration Points

| Component | Relationship |
| --- | --- |
| [BT-Backup](./BT-Backup.md) | Uses every helper — logging, locking, session temp, byte / duration formatting. |
| [BT-Plan](./BT-Plan.md) | Same lifecycle as `BT-Backup`; also drives plan-level `MailBody` segments. |
| [BT-File-Credentials](./BT-File-Credentials.md) | Uses the shared logger, error reporting, and credential-file dialogs. |
| [BT-Mail-Credentials](./BT-Mail-Credentials.md) | Uses the shared logger, error reporting, and credential-file dialogs. |
| [BT-File-Get-Password](./BT-File-Get-Password.md) | Uses the shared logger and error reporting. |
| [BT-Mail-Send](./BT-Mail-Send.md) | Uses the shared logger and error reporting. |
| [BT-Rclone-Config](./BT-Rclone-Config.md) | Uses the shared logger and error reporting. |

---

## Notes

- The module is strict-mode-safe (`Set-StrictMode -Version Latest` inside the module and expected on the caller side).
- `Write-Log` swallows nothing — it only writes; failures on `Add-Content` propagate to the caller.
- Log lines carry a `yyyy-MM-dd HH:mm:ss:` timestamp prefix.
- The mail body stores raw lines and lets `BT-Mail-Send` decide on formatting.
- Retry logic in `Remove-SessionTemporaryDirectory` is intentional — files in the temp directory may still be transiently held after use (for example, an attachment file after `Send-MailMessage` completes or fails, or files being scanned by antivirus or a sync client).
- No function opens files with `FileShare.None` — the lock file is intentionally readable while held so operators can inspect `PID`, `COMMAND`, `LOG` of a running session.

---

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan](./BT-Plan.md)
- [Glossary](./Glossary.md)
