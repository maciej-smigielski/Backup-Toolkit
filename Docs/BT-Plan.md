# BT-Plan

Runtime script of the Backup-Toolkit that executes a **Plan** — a set of `BT-Backup` jobs described in a single `.BT-Plan` TOML file. `BT-Plan` decides which jobs to run for the current day, invokes `BT-Backup` for each, aggregates results, and optionally sends an HTML e-mail summary with the per-job logs attached.

The script is designed to be launched non-interactively (from Task Scheduler via `BT-Plan-Schedule` or an equivalent wrapper) but can also be run from a console for validation, dry runs, or ad-hoc executions.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Plan` exists so that a host can run a curated set of backups from a single call and get one consolidated report. Concretely it lets an operator:

- describe several `BT-Backup` targets and their weekly schedule in one `.BT-Plan` file,
- run only the jobs scheduled for the current weekday, or force a full / single-job execution with `-RunAll` / `-RunJob`,
- validate the plan and each job's configuration without touching the storage (`-ValidateOnly`, `-ValidateJobs`),
- perform a rehearsal without writing changes (`-DryRun`),
- receive one HTML e-mail summary with per-job status, flags and attached logs,
- exit with a stable exit code that reflects the aggregated result of all jobs.

The script does **not** implement backup semantics itself — `BT-Backup` still does the actual rclone work per job.

---

## Location

| Item | Path |
| --- | --- |
| Script | `Tools/BT-Plan.ps1` |
| Wrapper for scheduled task | `Tools/Admin/BT-Plan-Schedule.cmd` |
| Invoked per job | `Tools/BT-Backup.ps1` |
| Related documentation | `Docs/BT-Backup.md`, `Docs/BT-Plan-Schedule.md`, `Docs/Glossary.md` |

---

## Requirements

- Windows PowerShell 5.1
- `BT.Common` module (`Tools/Modules/BT.Common/BT.Common.psd1`) for logging, locking, session temp folder, and controlled exit
- `PSToml` module (`Tools/Modules/PSToml/PSToml.psd1`) for parsing the `.BT-Plan` file
- A valid `.BT-Plan` configuration file (see [Configuration file](#configuration-file))
- The `BackupData` folder for every referenced Backup must exist and contain the target `<backup_name>.BT-Backup` config
- For e-mail summaries: a DPAPI-protected `.BT-Mail-Credentials` file readable by the current user

No network access is required by `BT-Plan` itself; individual `BT-Backup` runs may need network access depending on the rclone remote.

---

## Process Overview

1. Parses command-line parameters, validates that `-ConfigFile` points to an existing `*.BT-Plan` file.
2. Resolves the log directory (`-LogPath` or `<config-dir>/logs/`) and creates a session log file `BT-Plan_<plan_name>_<yyyy-MM-dd_HH-mm-ss>_<PID>.log`.
3. Imports the `BT.Common` and `PSToml` modules and initialises `$BTCommon` runtime flags.
4. Reads and parses the `.BT-Plan` TOML file, validates each section (`bt-plan`, `runtime`, `mail`, `job_defaults`, `jobs`) and each `[[jobs]]` entry.
5. Resolves the session temp directory (from `runtime.temp_path` or `%TEMP%`) and the lock file path (`<lock_path>/BT-Plan_<plan_name>.lock`).
6. Optionally loads mail credentials and split the `mail_to` address list.
7. Validates every job: checks that `backup_data` exists, that the per-Backup `<backup_name>/<backup_name>.BT-Backup` config exists, and that `run_days` has the correct format.
8. Computes the ISO weekday number (1–7) and marks each job as *scheduled* if its `run_days` contains the current day.
9. Acquires the session lock file (via `CreateSessionLockFile`).
10. For each job whose status is still *NotProcessed*:
    - Skips it if it is not scheduled and none of `-RunAll`, `-RunJob`, `-ValidateJobs`, `-DryRun` overrides it.
    - Invokes `BT-Backup.ps1` with `-FromPlan` and, when applicable, `-ValidateOnly`, `-DryRun` or `-NoMail`.
    - Captures stdout / stderr, extracts special *control records* (`@FLAGS@`, `@ATTACHMENT@BTBACKUP@`, `@ATTACHMENT@RCLONE@`, `@BODY@`) that `BT-Backup` prints for the plan.
    - Records the child exit code, final status and the paths of the log files that will be attached to the mail.
11. Resolves the per-job final statuses into plan-level exit results (e.g. `DefinitionError`, `ExecutionError`, `ExitCodeError`, `ControlRecordError`, `RunJobNotFound`).
12. Builds the HTML e-mail body (header + summary + per-job table), packages the collected log files into a ZIP in the session temp folder, and sends the mail via `Send-MailMessage` when e-mail is enabled and `-NoMail` was not passed.
13. Removes the session temp directory and the session lock file.
14. Exits via `Exit-Pause` with the single or aggregated exit code (see [Exit codes](#exit-codes)).

---

## Parameters

The parameter block is a `CmdletBinding()` script param, so PowerShell binding rules apply (positional or named, tab-completion available).

### `-ConfigFile <path>`

**Required.** Path to the `.BT-Plan` configuration file. The extension must be `.BT-Plan` (case-insensitive) and the file's base name must match `bt-plan.plan_name` inside the TOML.

### `-LogPath <path>`

Optional. Directory for the session log file. If not provided, the script uses `logs/` next to the configuration file. The directory must already exist.

### `-RunAll`

Optional switch. Runs every valid job in the plan regardless of `run_days`.

### `-RunJob <backup_name>`

Optional. Runs only the job whose `backup_name` matches this value. Overrides `-RunAll`, `-ValidateJobs` and `-DryRun` in terms of *job selection* — only that single job is processed, but the selected job still respects `-ValidateJobs` / `-DryRun` when they are combined. A missing job name yields `RunJobNotFound` (code 131).

### `-ValidateOnly`

Optional switch. Validates the plan and its jobs, does **not** run `BT-Backup` and does **not** send mail. Ends after the plan-level validation loop.

### `-ValidateJobs`

Optional switch. Runs every valid job in the plan in `BT-Backup -ValidateOnly` mode. No rclone sync is performed and no mail is sent. Overrides scheduling (`run_days`).

### `-DryRun`

Optional switch. Runs every valid job in the plan in `BT-Backup -DryRun` mode. rclone is called with `--dry-run` and no changes are written. Overrides scheduling (`run_days`).

### `-NoMail`

Optional switch. Skips the plan-level e-mail summary. Per-job e-mails inside `BT-Backup` are controlled independently by `skip_mail` in the plan or the Backup config.

### `-NoPause`

Optional switch. Skips the final `Press Enter to continue . . .` prompt (used in scheduled runs). Forwarded to `Initialize-BTCommon`.

### `-Debug`

Optional switch (inherited from `CmdletBinding()`). Enables `Write-Log` lines flagged with `-DebugLevel:$true` — mostly diagnostic details about parsed values and intermediate state.

---

## Configuration file

`.BT-Plan` is a TOML file. The base name of the file must match `bt-plan.plan_name`. All keys are case-sensitive. String values that contain Windows paths with `\` should be wrapped in single quotes (`'C:\path\to\file'`), since TOML treats `\` inside double-quoted strings as an escape sequence.

By convention, `.BT-Plan` files live in the **BackupPlan** folder of the BackupRepository, together with a shared `logs/` subfolder (see [Glossary](./Glossary.md)).

### `[bt-plan]`

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `plan_name` | string | yes | Name of the plan; must equal the config file base name. |

### `[runtime]`

Optional section.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `temp_path` | string | `%TEMP%` | Parent folder for the session temp directory. Environment variables are expanded. |
| `lock_path` | string | folder of the `.BT-Plan` file | Folder in which the session lock file `BT-Plan_<plan_name>.lock` is created. |

### `[mail]`

Optional section. When `mail_to` and `mail_credentials` are both provided and valid, `BT-Plan` sends an HTML summary at the end.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `mail_to` | string | — | Recipient address, or a list separated by `;`. Empty entries are ignored. |
| `mail_credentials` | string | — | Path to a `.BT-Mail-Credentials` file (see [BT-Mail-Credentials](./BT-Mail-Credentials.md)). Environment variables are expanded. |
| `mail_attach_log` | boolean | `false` | When `true`, attach a ZIP containing the plan log and every job's `BT-Backup` and rclone logs. |

### `[job_defaults]`

Optional section that provides defaults for every `[[jobs]]` entry.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `backup_data` | string | — | Default `BackupData` folder used by jobs that do not set their own. |
| `run_days` | string | — | Digit string over `1234567` (1 = Monday … 7 = Sunday). A job runs on days whose digit is present. |
| `skip_mail` | boolean | `false` | Default value of `skip_mail` for each job (passed to `BT-Backup` as `-NoMail`). |

### `[[jobs]]`

An array-of-tables. Each entry describes one Backup to run.

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `backup_name` | string | yes | Name of the Backup; matches `<BackupData>/<backup_name>/<backup_name>.BT-Backup`. |
| `backup_data` | string | inherited | Overrides `job_defaults.backup_data` for this job. |
| `run_days` | string | inherited | Overrides `job_defaults.run_days` for this job. |
| `skip_mail` | boolean | inherited | Overrides `job_defaults.skip_mail` for this job. |

Environment variables in path values are expanded before existence checks.

---

## Usage

### From Windows Task Scheduler

Use [BT-Plan-Schedule](./BT-Plan-Schedule.md) to create and manage a task that invokes `BT-Plan.ps1` through `powershell.exe` with the selected `.BT-Plan` configuration file and `--NoPause`. Start the administrative menu with `Tools/Admin/BT-Plan-Schedule.cmd`.

The utility registers a daily trigger at `StartTime`. The wrapper default is `0:20`. Each run evaluates the plan configuration and selects jobs according to their `run_days` settings.

The task should run with an account that has access to the plan configuration, backup data and any credentials used by the plan and its jobs.

---

## Exit codes

`BT-Plan` returns one of the codes below. When several conditions occur in the same run, they are accumulated and the process finally exits with code `111` (`Multiple`).

| Code | Symbol | Meaning |
| --- | --- | --- |
| `0` | `Success` | Plan completed successfully. |
| `1` | `Unhandled` | Unhandled exception in the outer `try/catch`. |
| `101` | `General` | General validation error (parameters, log directory, config file existence). Log file may not have been created. |
| `102` | `Param` | Configuration parameter error (`plan_name` mismatch, invalid `temp_path` / `lock_path` / `mail_to` / `mail_credentials`). |
| `103` | `ParamRead` | Unable to read `.BT-Plan` file. |
| `104` | `ParamShow` | Unable to render the parsed content of the `.BT-Plan` file (debug output). |
| `105` | `ParamParse` | `.BT-Plan` content violates the expected schema. |
| `111` | `Multiple` | More than one error condition occurred in the same run. |
| `121` | `UnprocessedError` | At least one job stayed in *NotProcessed* state (real backup run). Never raised under `-ValidateOnly`. |
| `122` | `DefinitionError` | At least one job failed pre-execution validation (missing paths, invalid `run_days`, etc.). |
| `123` | `ExecutionError` | At least one job could not be executed (exception while invoking `BT-Backup`). |
| `124` | `ExitCodeError` | At least one job returned a non-zero `BT-Backup` exit code with valid control records. |
| `125` | `ExitCodeControlError` | Non-zero `BT-Backup` exit code combined with missing / extra control records. |
| `126` | `ControlRecordError` | `BT-Backup` returned zero, but the control records emitted for the plan are invalid. |
| `131` | `RunJobNotFound` | `-RunJob <backup_name>` did not match any `[[jobs]]` entry. |
| `141` | `MailAttachement` | Building the mail attachment (ZIP) failed. |
| `142` | `MailCredentials` | Loading or decoding the `.BT-Mail-Credentials` password failed. |
| `143` | `MailSend` | `Send-MailMessage` failed. |

Additionally, the shared codes `801`–`804` from `BT.Common` may bubble up (`BTCommonLock`, `BTCommonUnlock`, `BTCommonSessionTemp`, `BTCommonCleanup`).

---

## Job final statuses

For internal reporting each job has a *final status* that ends up in the mail summary and the console output:

- `Success` — `BT-Backup` returned `0` and control records are valid.
- `Skipped` — job was not scheduled and no override applied.
- `Failed (Definition Error)` — pre-execution validation failed.
- `Failed (Execution Error)` — could not invoke `BT-Backup`.
- `Failed (Exit Code: <n>)` — `BT-Backup` returned `<n>`; control records valid.
- `Failed (Exit Code: <n>, Invalid Control Record)` — `<n>` returned and control records invalid.
- `Failed (Successful Exit Code, Invalid Control Record)` — `0` returned but control records invalid.
- `Not Processed` — internal transient state; still visible only when the loop never reached the job.

---

## Integration Points

| Component | Relationship |
| --- | --- |
| [BT-Backup](./BT-Backup.md) | Executed once per job, with `-FromPlan` and the relevant switches. Its control records (`@FLAGS@`, `@ATTACHMENT@BTBACKUP@`, `@ATTACHMENT@RCLONE@`, `@BODY@`) feed the mail summary. |
| [BT.Common](./BT.Common.md) | Provides `Initialize-BTCommon`, `Write-Log` / `Write-LogError`, `CreateSessionLockFile` / `RemoveSessionLockFile`, `CreateSessionTemporaryDir` / `RemoveSessionTemporaryDir`, `Get-ElapsedDurationString`, and `Exit-Pause`. |
| PSToml | Parses the `.BT-Plan` TOML file (`ConvertFrom-Toml` / `ConvertTo-Toml`). |
| [BT-Plan-Schedule](./BT-Plan-Schedule.md) | Registers a Windows scheduled task that launches `BT-Plan.ps1` directly through `powershell.exe` with the configured `.BT-Plan` file and `--NoPause`. |
| [BT-Mail-Credentials](./BT-Mail-Credentials.md) | Source of the DPAPI-protected credentials referenced by `mail.mail_credentials`. |

---

## Notes

- Per-job scheduling is based on the ISO weekday number computed at start; running the plan past midnight still uses the day the process started.
- `-RunJob` restricts execution to a single job; combined with `-ValidateJobs` or `-DryRun` it runs only that one job in the corresponding mode.
- `-ValidateOnly` skips job execution and mail entirely; `-ValidateJobs` still invokes `BT-Backup` but in its own validate-only mode and suppresses mail.
- Job order in the plan is preserved on output and in the mail table.
- The mail body is HTML; log lines are stored raw in `$BTCommon.MailBody` and the plan's control records are HTML-encoded before rendering.
- The ZIP attachment is written inside the session temp directory and cleaned up by `RemoveSessionTemporaryDir`; transient locks on the ZIP (antivirus, sync clients, `Send-MailMessage` finalization) are handled by that helper's retry loop.
- Special output lines from `BT-Backup` (`@…@`) are consumed by `BT-Plan` and are **not** printed to the plan log verbatim; regular stdout lines are echoed to the console but only recorded in the plan log at debug level.
- The lock file is opened with `FileShare.Read`, so an operator can inspect `PID`, `COMMAND` and `LOG` of a running plan while it is executing.

---

## Example email reports

Two anonymized samples of the consolidated `BT-Plan` report are included to show both extremes of a plan run. In both cases sender, recipient, hostname and user paths have been anonymized.

- No changes — `plan-example` finished with `Success 2 Ready 2`; both jobs completed successfully but neither had anything to transfer, so per-job counters are zero. Sample: [PDF](assets/mail-samples/plan-example-no-changes.pdf) · [HTM](assets/mail-samples/plan-example-no-changes.htm)
- With changes — `plan-example` again finished with `Success 2 Ready 2`, but this time at least one job actually transferred data, so the plan-level summary contains non-zero counters and lists the affected files per job. Sample: [PDF](assets/mail-samples/plan-example-with-changes.pdf) · [HTM](assets/mail-samples/plan-example-with-changes.htm)

Each job's session log and rclone log are attached as ZIPs when the corresponding backup has `mail_attach_log = true`.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan-Schedule](./BT-Plan-Schedule.md)
- [BT.Common](./BT.Common.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [Glossary](./Glossary.md)
