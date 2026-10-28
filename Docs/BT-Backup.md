# BT-Backup

Runtime script of the Backup-Toolkit that executes a **Backup** — a single `rclone sync` of the source described in a `.BT-Backup` TOML file. `BT-Backup` validates the configuration and the storage layout, invokes rclone with the correct switches, versions the previous state under `archive/`, computes a compact set of summary flags and — when configured — sends an HTML e-mail report with the log files attached.

The script can be launched directly or from `BT-Plan`; when invoked with `-FromPlan`, it also streams a set of control records to stdout so that `BT-Plan` can build a consolidated report.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Backup` exists so that a single Backup can be executed with the same operational contract — validation, locking, logging, versioning, reporting — regardless of who runs it. Concretely it lets an operator:

- describe a **Backup** (source, destination, filter, rclone options, mail) in one `.BT-Backup` file,
- verify the configuration and storage layout without touching data (`-ValidateOnly`),
- perform a rehearsal without writing changes (`-DryRun`),
- run the actual sync and version the previous content under `archive/archive_<timestamp>_<PID>/`,
- collect archive and transfer statistics from the rclone log and expose them as compact `(ATDR)` flags,
- receive one HTML e-mail summary with the session log and the rclone log attached (`mail_attach_log = true`),
- integrate with `BT-Plan` by emitting control records that carry the mail body, log paths and flags.

The script does **not** manage rclone configuration or credentials directly (those are prepared with `BT-Rclone-Config`, `BT-File-Credentials`, `BT-Mail-Credentials`) and does **not** schedule anything (that's the role of `BT-Plan-Schedule`).

---

## Location

| Item | Path |
| --- | --- |
| Script | `Tools/BT-Backup.ps1` |
| CMD wrapper | `Tools/BT-Backup.cmd` |
| Bundled rclone | `Tools/Utilities/Rclone/rclone.exe` |
| Related documentation | `Docs/BT-Plan.md`, `Docs/BT-Rclone-Config.md`, `Docs/BT-File-Credentials.md`, `Docs/BT-Mail-Credentials.md`, `Docs/Glossary.md` |

---

## Requirements

- Windows PowerShell 5.1
- `BT.Common` module (`Tools/Modules/BT.Common/BT.Common.psd1`) for logging, locking, session temp folder, and controlled exit
- `PSToml` module (`Tools/Modules/PSToml/PSToml.psd1`) for parsing the `.BT-Plan` file
- `rclone.exe` — either the bundled binary or a custom one referenced via `[rclone].rclone_prog`
- A valid `.BT-Backup` configuration file (see [Configuration file](#configuration-file)) placed in the target **BackupHome** (`BackupData/<backup_name>/`)
- For remote sources / destinations: a working `.BT-Rclone-Config` (optionally protected by a `.BT-File-Credentials` file)
- For e-mail reports: a DPAPI-protected `.BT-Mail-Credentials` file readable by the current user

Network access is required only when the source or the destination is a remote rclone backend.

---

## Process Overview

1. Parses command-line parameters and validates that `-ConfigFile` points to an existing `*.BT-Backup` file.
2. Resolves the log directory (`-LogPath` or `<config-dir>/logs/`) and creates a session log file `BT-Backup_<backup_name>_<yyyy-MM-dd_HH-mm-ss>_<PID>.log`.
3. Imports the `BT.Common` and `PSToml` modules and initialises `$BTCommon` runtime flags.
4. Reads and parses the `.BT-Backup` TOML file, validates each section (`bt-backup`, `runtime`, `mail`, `source`, `destination`, `rclone`) and checks that `backup_name` and `backup_data` match the file / folder layout.
5. Resolves optional runtime folders (`temp_path`, `lock_path`) and mail settings; expands environment variables where allowed.
6. Builds the rclone source path (`source_system:source_path` or a local path) and, when `source_filter = true`, locates the matching `.BT-Filter` file.
7. Builds the destination path — either the local **BackupHome** (Colocated Backup) or a remote path derived from `destination_system` / `destination_storage` (Split Backup).
8. Optionally loads and decrypts the rclone config password from `rclone_credentials` (`.BT-Rclone-Config`) and mail credentials from `mail_credentials` (`.BT-Mail-Credentials`).
9. Acquires the session lock file (via `CreateSessionLockFile`).
10. Checks the rclone version by running `rclone --version`.
11. Validates the destination layout: `current/` and `archive/` must exist under `<destination>/<backup_name>/`. For remote destinations the check uses `rclone lsjson`.
12. Runs `rclone sync <source> <current>` with `--backup-dir <archive/archive_<timestamp>_<PID>>` plus the switches implied by the config (`--filter-from`, `--track-renames …`, `--iclouddrive-service photos`, `--fix-case` / `--create-empty-src-dirs` / `--delete-excluded` when the matching `destination_fc` / `destination_cesd` / `destination_de` flags are `true`, `--log-level INFO`, `--log-file …`, and `--dry-run` under `-DryRun`).
13. Collects archive statistics (file count and total bytes in the new `archive_<timestamp>_<PID>/` folder) and derives the `(ATDR)` summary flags from the tail of the rclone log.
14. Composes the HTML mail body, packages the session log and rclone log into a ZIP if `mail_attach_log = true`, and sends the mail via `Send-MailMessage` when e-mail is enabled and `-NoMail` was not passed.
15. When `-FromPlan` is set, streams control records to stdout so that `BT-Plan` can consume the mail body, log paths and flags.
16. Removes the session temp directory and the session lock file.
17. Exits via `Exit-Pause` with the single or aggregated exit code (see [Exit codes](#exit-codes)).

Under `-ValidateOnly` the script stops after step 11 — no rclone `sync`, no stats collection, no mail. Under `-DryRun` steps 12–14 still execute, but rclone is called with `--dry-run` so no data is written.

---

## Parameters

The parameter block uses `CmdletBinding()`, so PowerShell binding rules apply (positional or named, tab-completion available).

### `-ConfigFile <path>`

**Required.** Path to the `.BT-Backup` configuration file. The extension must be `.BT-Backup` (case-insensitive), the file's base name must match `bt-backup.backup_name`, and its parent directory must equal `<backup_data>/<backup_name>/` after environment-variable expansion.

### `-LogPath <path>`

Optional. Directory for the session log file. If not provided, the script uses `logs/` next to the configuration file. The directory must already exist.

### `-ValidateOnly`

Optional switch. Validates the configuration, credentials and destination layout, and checks the rclone version. Does **not** invoke `rclone sync`, does **not** collect statistics, and does **not** send mail.

### `-DryRun`

Optional switch. Runs `rclone sync` with `--dry-run`. No files are written, but archive stats and the transfer summary are still computed from the rclone log and the mail is still produced.

### `-NoMail`

Optional switch. Skips the e-mail report even if `mail_to` / `mail_credentials` are configured.

### `-FromPlan`

Optional switch. Marks the run as invoked by `BT-Plan`. Sets `NoPause` implicitly and enables the control records (`@BODY@`, `@ATTACHMENT@BTBACKUP@`, `@ATTACHMENT@RCLONE@`, `@FLAGS@`) written to stdout for the parent process.

### `-NoPause`

Optional switch. Skips the final `Press Enter to continue . . .` prompt (used in scheduled runs). Automatically active when `-FromPlan` is set.

### `-Debug`

Optional switch (inherited from `CmdletBinding()`). Enables `Write-Log` lines flagged with `-DebugLevel:$true` — mostly diagnostic details about parsed values and intermediate state.

---

## Configuration file

`.BT-Backup` is a TOML file. Its base name must match `bt-backup.backup_name`, and it must live in `<backup_data>/<backup_name>/` — the Backup's **BackupHome** on `BackupData/` (see [Glossary](./Glossary.md)). All keys are case-sensitive; environment variables in path values are expanded before existence checks. String values that contain Windows paths with `\` should be wrapped in single quotes (`'C:\path\to\file'`), since TOML treats `\` inside double-quoted strings as an escape sequence.

By convention, a `.BT-Backup` file lives in a **BackupHome** subfolder, together with a `logs/` subfolder, which sits inside the **BackupData** container, which sits inside the **BackupRepository** (see [Glossary](./Glossary.md)).

### `[bt-backup]`

Mandatory section.

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `backup_name` | string | yes | Name of the **Backup** as defined in the [Glossary](./Glossary.md). The Backup's **BackupHome** folder inside `BackupData/` is named after this value (`BackupData/<backup_name>/`), and the same value must be used as the base name of the `.BT-Backup` config file that lives inside it. |
| `backup_data` | string | yes | Parent **BackupData** folder that contains the `<backup_name>/` **BackupHome**. Its main purpose is a safety check: `BT-Backup` compares this value with the actual location of the `.BT-Backup` file and refuses to run when they disagree, which prevents accidental execution against a **BackupHome** or **BackupData** folder that was moved to a different path. Also used as the default local destination for **Colocated Backups** (see [Glossary](./Glossary.md)). |

### `[runtime]`

Optional section.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `temp_path` | string | `%TEMP%` | Parent folder for the session temp directory and rclone's `--temp-dir` / `--cache-dir`. |
| `lock_path` | string | folder of the `.BT-Backup` file | Folder in which the session lock file `BT-Backup_<backup_name>.lock` is created. |

### `[mail]`

Optional section. E-mail is sent only when both `mail_to` and `mail_credentials` are provided and valid.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `mail_to` | string | — | Recipient address, or a list separated by `;`. Empty entries are ignored. |
| `mail_credentials` | string | — | Path to a `.BT-Mail-Credentials` file (see [BT-Mail-Credentials](./BT-Mail-Credentials.md)). |
| `mail_attach_log` | boolean | `false` | When `true`, attach a ZIP with the session log and the rclone log. |

### `[source]`

Mandatory section describing the rclone source. At least one of `source_system` / `source_path` must be non-empty.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `source_system` | string | *(local)* | Rclone remote name (e.g. `onedrive`). Empty means local. |
| `source_path` | string | — | Source path (local or under the remote). Combined with `source_system` as `system:path`. |
| `source_filter` | boolean | `false` | When `true`, use the sibling `<backup_name>.BT-Filter` file as `--filter-from` (rclone's standard filter-file format; see [Glossary](./Glossary.md#file-types)). |
| `source_renames` | boolean | `false` | When `true`, add `--track-renames --track-renames-strategy hash` to detect and follow renames. |
| `source_iphotos` | boolean | `false` | When `true`, add `--iclouddrive-service photos` (used for iCloud Photo Library backups). |

### `[destination]`

Optional section describing the rclone destination. If both `destination_system` and `destination_storage` are empty, the destination is the local **BackupHome** in `backup_data` — a **Colocated Backup**. Otherwise the destination is a **Split Backup** on a remote or on a separate storage root (see [Glossary](./Glossary.md)).

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `destination_system` | string | *(local)* | Rclone remote name for the destination. Empty means local. |
| `destination_storage` | string | `backup_data` | Root of the destination storage. Must contain `<backup_name>/current/` and `<backup_name>/archive/`. |
| `destination_posix` | boolean | `true` | Interpreted only when `destination_system` is provided. For a remote destination, `true` uses forward slashes and `false` uses backslashes in rclone paths. |
| `destination_fc` | boolean | `true` | When `true`, add `--fix-case` so rclone renames destination entries whose case does not match the source (useful on case-insensitive backends). |
| `destination_cesd` | boolean | `true` | When `true`, add `--create-empty-src-dirs` so rclone recreates empty source directories on the destination. |
| `destination_de` | boolean | `true` | When `true`, add `--delete-excluded` so rclone removes files at the destination that are excluded by the current filter rules. |

### `[rclone]`

Optional section pointing to the rclone binary and its configuration.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `rclone_prog` | string | bundled `Tools/Utilities/Rclone/rclone.exe` | Rclone executable to invoke. |
| `rclone_config` | string | rclone default (`%APPDATA%\rclone\rclone.conf`) | Path to an rclone config file (a `.BT-Rclone-Config` — see [BT-Rclone-Config](./BT-Rclone-Config.md) — or a plain `rclone.conf` at any location), passed to rclone as `--config`. |
| `rclone_credentials` | string | — | Path to a `.BT-File-Credentials` file (see [BT-File-Credentials](./BT-File-Credentials.md)) holding the password of `rclone_config`. Decrypted in memory and injected via the `RCLONE_CONFIG_PASS` environment variable. |

---

## Exit codes

`BT-Backup` returns one of the codes below. When several conditions occur in the same run, they are accumulated and the process finally exits with code `111` (`Multiple`).

| Code | Symbol | Meaning |
| --- | --- | --- |
| `0` | `Success` | Backup completed successfully. |
| `1` | `Unhandled` | Unhandled exception in the outer `try/catch`. |
| `101` | `General` | General validation error (parameters, log directory, config file existence). Log file may not have been created. |
| `102` | `Param` | Configuration parameter error (`backup_name` / `backup_data` mismatch, invalid `[source]` / `[destination]` / `[runtime]` / `[mail]` values, missing `.BT-Filter` when required). |
| `103` | `ParamRead` | Unable to read `.BT-Backup` file. |
| `104` | `ParamShow` | Unable to render the parsed content of the `.BT-Backup` file (debug output). |
| `105` | `ParamParse` | `.BT-Backup` content violates the expected schema. |
| `106` | `ParamDest` | Destination validation failed (`current/` / `archive/` missing, remote listing failure, `rclone_config` / `rclone_credentials` unusable). |
| `111` | `Multiple` | More than one error condition occurred in the same run. |
| `121` | `RcloneVersion` | `rclone --version` failed or its output could not be parsed. |
| `122` | `RcloneListing` | `rclone lsjson` failed while probing the destination. |
| `123` | `RcloneSync` | `rclone sync` returned a non-zero exit code. |
| `131` | `StatsArchive` | Archive statistics could not be collected (local enumeration or remote listing failure). |
| `132` | `StatsRcloneLog` | Rclone log statistics could not be collected (missing log or unrecognised format). |
| `141` | `MailAttachement` | Building the mail attachment (ZIP) failed. |
| `142` | `MailCredentials` | Loading or decoding the `.BT-Mail-Credentials` password failed. |
| `143` | `MailSend` | `Send-MailMessage` failed. |

Additionally, the shared codes `801`–`804` from `BT.Common` may bubble up (`BTCommonLock`, `BTCommonUnlock`, `BTCommonSessionTemp`, `BTCommonCleanup`).

---

## Summary flags — `(ATDR)`

Every successful (or partially successful) run produces a four-character flag string used both in the mail subject and in the `@FLAGS@` control record consumed by `BT-Plan`.

| Position | Value | Meaning |
| --- | --- | --- |
| 1 — Archive | `A` | Files were moved into the new archive folder. |
| 1 — Archive | `N` | Nothing was archived. |
| 2 — Transfer | `T` | rclone transferred files to the destination. |
| 2 — Transfer | `N` | rclone had nothing to transfer. |
| 3 — Delete | `D` | rclone deleted files at the destination. |
| 3 — Delete | `N` | Nothing was deleted. |
| 4 — Rename | `R` | rclone recognised renames (only when `source_renames = true`). |
| 4 — Rename | `N` | No renames were reported. |
| any | `X` | The flag could not be computed (early error). |

---

## Control records (only under `-FromPlan`)

Under `-FromPlan`, `BT-Backup` emits the following lines to stdout, one line each. `BT-Plan` recognises them and consumes them instead of forwarding them to the console.

| Record | Content | Emitted when |
| --- | --- | --- |
| `@BODY@<Segment>@<Line>@` | One entry from `$BTCommon.MailBody` with its segment (`Header`, `Body`, `Summary`) and the raw text. | For every mail body line accumulated during the run. |
| `@ATTACHMENT@BTBACKUP@<path>@` | Absolute path to the `BT-Backup` session log. | If the session log file exists. |
| `@ATTACHMENT@RCLONE@<path>@` | Absolute path to the rclone log file. | If rclone was invoked and produced a log file. |
| `@FLAGS@(<ATDR>)@` | The four-character summary flag string. | Always as the last record. |

`BT-Plan` re-formats the mail body itself, collects the attachment paths into its own ZIP, and uses the flags to decorate the plan-level summary and mail subject.

---

## Files produced

| File | Location | Purpose |
| --- | --- | --- |
| Session log | `<LogPath>/BT-Backup_<backup_name>_<yyyy-MM-dd_HH-mm-ss>_<PID>.log` | Timestamped record of parameter validation, rclone invocation, stats and errors. |
| Rclone log | `<LogPath>/rclone_<backup_name>_<yyyy-MM-dd_HH-mm-ss>_<PID>.log` | Raw rclone `--log-file` output at `INFO` level; parsed by the script for `(ATDR)` flags. |
| Archive session folder | `<destination>/<backup_name>/archive/archive_<yyyy-MM-dd_HH-mm-ss>_<PID>/` | Previous versions of files that were changed or removed during this run (created by rclone's `--backup-dir`). |
| Session lock | `<lock_path>/BT-Backup_<backup_name>.lock` | Kept open for the whole session; contains `PID`, `COMMAND`, `LOG` and is opened with `FileShare.Read` so operators can inspect it. |
| Mail attachment (ZIP) | `<session temp dir>/<backup_name>_<yyyy-MM-dd_HH-mm-ss>_<PID>.zip` | Created when `mail_attach_log = true`; deleted with the session temp directory. |

---

## Integration Points

| Component | Relationship |
| --- | --- |
| [BT.Common](./BT.Common.md) | Provides `Initialize-BTCommon`, `Write-Log` / `Write-LogError`, `CreateSessionLockFile` / `RemoveSessionLockFile`, `CreateSessionTemporaryDir` / `RemoveSessionTemporaryDir`, `Get-ElapsedDurationString`, `Format-ByteSizeString`, and `Exit-Pause`. |
| PSToml | Parses the `.BT-Backup` TOML file (`ConvertFrom-Toml` / `ConvertTo-Toml`). |
| rclone | External binary invoked for `--version`, `lsjson` and `sync`. Password injected via `RCLONE_CONFIG_PASS` when `rclone_credentials` is configured. |
| [BT-Rclone-Config](./BT-Rclone-Config.md) | Owns the `.BT-Rclone-Config` file referenced by `[rclone].rclone_config`. |
| [BT-File-Credentials](./BT-File-Credentials.md) | Owns the `.BT-File-Credentials` file referenced by `[rclone].rclone_credentials`. |
| [BT-Mail-Credentials](./BT-Mail-Credentials.md) | Owns the `.BT-Mail-Credentials` file referenced by `[mail].mail_credentials`. |
| [BT-Plan](./BT-Plan.md) | Executes `BT-Backup.ps1` per job with `-FromPlan` and reads the control records to compose a plan-level report. |

---

## Notes

- The Backup layout must match the **Colocated** or **Split** variant defined in the [Glossary](./Glossary.md). `BT-Backup` verifies that `current/` and `archive/` exist under `<destination>/<backup_name>/` before running the sync.
- `-ValidateOnly` stops after the destination check; `-DryRun` still runs rclone (with `--dry-run`) so archive stats and transfer summary are populated but no data is written.
- The lock file uses `FileShare.Read`, so an operator can inspect `PID`, `COMMAND` and `LOG` of a running Backup at any time; the lock is *exclusive* enough to block a second `BT-Backup` on the same config.
- Rclone is invoked with `--log-level INFO`, `--log-file <rclone log>` and `--ask-password=false`. The `[destination]` boolean keys `destination_fc`, `destination_cesd` and `destination_de` control `--fix-case`, `--create-empty-src-dirs` and `--delete-excluded`, respectively; each defaults to `true`, and setting it to `false` omits the corresponding switch. Other switches are controlled by their TOML settings: `[source].source_filter` adds `--filter-from`, `[source].source_renames` adds `--track-renames --track-renames-strategy hash`, `[source].source_iphotos` adds `--iclouddrive-service photos`, `[runtime].temp_path` supplies `--temp-dir` and `--cache-dir`, and `[rclone].rclone_config` supplies `--config`.
- `RCLONE_CONFIG_PASS` and mail SMTP passwords are kept in memory only for the duration of the corresponding call and are never written to disk or to the logs.
- The mail body is HTML; log lines are stored raw in `$BTCommon.MailBody` and HTML-encoded when the body is rendered. The mail subject encodes the mode (`[VALIDATE ONLY]`, `[DRY RUN]`) and the `(ATDR)` flags.
- When invoked from `BT-Plan`, control records are the *only* structured output; regular console lines are consumed as diagnostics by the parent process.
- If the script exits before it can emit `@FLAGS@`, `BT-Plan` treats the missing record as an *invalid control record* condition (see the plan-level exit codes in [BT-Plan](./BT-Plan.md)).

---

## Example email reports

Two anonymized samples are included to show both extremes of a `BT-Backup` run. In both cases sender, recipient, hostname and user paths have been anonymized.

- No changes — `backup-example-1` was run against an already-synchronized destination, so `rclone sync` transferred nothing. The subject flags read `NNNN` (nothing added, transferred, deleted or renamed) and the report contains only counters equal to zero. Sample: [PDF](assets/mail-samples/backup-example-no-changes.pdf) · [HTM](assets/mail-samples/backup-example-no-changes.htm)
- With changes — the same backup was re-run after modifying the source, so `rclone sync` propagated changes to the destination. The subject flags read `ATDR` (files were added, transferred, deleted or renamed) and the report shows non-zero counters together with the affected files section. Sample: [PDF](assets/mail-samples/backup-example-with-changes.pdf) · [HTM](assets/mail-samples/backup-example-with-changes.htm)

Session log and rclone log are attached as a ZIP when `mail_attach_log = true`.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Plan](./BT-Plan.md)
- [BT-Plan-Schedule](./BT-Plan-Schedule.md)
- [BT.Common](./BT.Common.md)
- [BT-Rclone-Config](./BT-Rclone-Config.md)
- [BT-File-Credentials](./BT-File-Credentials.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [Glossary](./Glossary.md)
