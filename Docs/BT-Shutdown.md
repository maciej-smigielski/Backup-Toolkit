# BT-Shutdown

Command-line utility that decides whether the host should be shut down at the moment it is invoked and, if so, dispatches an optional notification e-mail and executes `shutdown /s`. All behaviour is driven by a single INI file (`*.BT-Shutdown.ini`) passed as the only argument, so the tool can be safely embedded in scheduled tasks and daily automation.

`BT-Shutdown` is implemented entirely as a **Windows batch script** (`.cmd`) — there is no PowerShell counterpart. It reads its parameters with `findstr`, evaluates a fixed set of pre-shutdown checks and produces a per-invocation log file describing every decision it made. When any check fails, the shutdown is skipped and only a log entry is written.

The utility is a **non-interactive console script**: it takes an INI file path, evaluates the checks, optionally calls [BT-Mail-Send](./BT-Mail-Send.md) and then invokes `shutdown.exe`. It has no window, no prompts and no user interaction.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Shutdown` provides a safe, auditable way to shut down a workstation at the end of an automation window (e.g. after nightly backup jobs have finished) while ensuring the machine is not used by a logged-in user, is not in the middle of a backup run and has been up long enough to be considered idle.

Typical scenarios:

- Scheduled shutdown of a backup host after the daily plan has completed.
- Automated shutdown of a shared workstation late at night once no user sessions remain.
- Guarded shutdown that respects Backup-Toolkit locks (`Locks/*.lock`) and user-defined flag files (`Locks/*.flg`).
- Sending a notification e-mail before shutdown so operators know the machine went down cleanly.

The utility is intended for **unattended, scheduled execution** (typically via Windows Task Scheduler) — it is not designed to be launched interactively by an operator.

---

## Location

| Item | Path |
| --- | --- |
| CMD script | `Tools/BT-Shutdown.cmd` |
| Input file extension | `.BT-Shutdown.ini` |
| Typical config folder | `Backups/BackupSystem/` |
| Companion mail sender | `Tools/BT-Mail-Send.cmd` |

The recommended file name for a host is `BT-Shutdown.<HOSTNAME>.ini` so that per-host configurations can coexist in the same `BackupSystem/` folder.

---

## Requirements

- Permission to invoke `shutdown /s` for the current user (member of *Administrators* or the *Shut down the system* user right)
- The INI file specified on the command line must exist and its `logpath` folder must exist
- Optional: a valid `BT-Mail-Credentials` file and access to the SMTP host, if e-mail notifications are enabled

No PowerShell modules and no network access are required unless the mail notification is configured.

---

## Process Overview

1. The script is launched with a single argument: the full path to a `*.BT-Shutdown.ini` file.
2. It verifies that the argument is provided and that the file exists; otherwise it exits with code `1`.
3. It reads `logpath` from the INI; if it is empty or the folder does not exist, it exits with code `1` before creating any log.
4. It builds the log file name `BT-Shutdown_YYYY-MM-DD_HH-MM-SS.log` inside `logpath` and writes the invocation header and all resolved parameter values to it.
5. It reads the remaining parameters from the INI (`threshold_min`, `start_hour`, `end_hour`, `shutdown_allow`, `shutdown_delay`, and the optional `flag_path`, `mail_to`, `mail_credentials`, `mail_prog`). Missing **required** values are logged as `Empty parameter: <key>` and the script jumps to the end without running any checks.
6. It queries `Get-CimInstance Win32_OperatingSystem` for `LastBootUpTime`, computes the current uptime in minutes and evaluates the five pre-shutdown checks (see [Pre-shutdown checks](#pre-shutdown-checks)).
7. If **all** checks pass and the mail parameters are complete, it calls the configured `mail_prog` (typically [BT-Mail-Send](./BT-Mail-Send.md)) with a fixed subject and body describing the host and uptime.
8. It executes `shutdown /s /t <shutdown_delay> /c "Shutdown in <shutdown_delay> seconds"` and logs the exit code returned by `shutdown.exe`.
9. If any check fails, the shutdown and the mail notification are skipped and the log records `All checks NOT-PASSED: Skip Executing Shutdown`.
10. Finally, the log file is printed to standard output so a scheduled task can capture it in its own output.

The script does **not** modify the INI file, does **not** delete lock/flag files and does **not** wait for `shutdown /s` to complete — control returns as soon as `shutdown.exe` has been scheduled.

---

## Configuration file

The INI file follows the standard `key=value` syntax under a single `[Settings]` section. Lines beginning with `#` are treated as comments (they are not parsed by `findstr`, but they should still be avoided for actively used keys — see [Notes](#notes)). Values are read verbatim, so **no quotes** should be placed around paths or numeric values.

Example:

Before using the sample below, replace the following placeholders with values from your environment:

- `<BTPath>` — absolute path to the Backup-Toolkit installation folder (the folder that contains `Tools/`, `Docs/`).
- `<BackupRepository>` — absolute path to the backup repository root (the folder that contains `BackupSystem/`, `Credentials/`).
- `mail_to` — replace `test@example.net` with the real recipient address (or list of addresses separated by `;`) that should receive the shutdown notification.
- `NoName.HOST.USER.BT-Mail-Credentials` — replace with the actual credentials file name in `<BackupRepository>\Credentials\`, typically following the naming convention `<account>.<HOSTNAME>.<username>.BT-Mail-Credentials` (see [BT-Mail-Credentials](./BT-Mail-Credentials.md)).

```ini
[Settings]
logpath=<BackupRepository>\BackupSystem\logs\
threshold_min=60
start_hour=3
end_hour=21
shutdown_allow=1
shutdown_delay=60
flag_path=<BackupRepository>\BackupSystem\Locks\
mail_to=test@example.net
mail_credentials=<BackupRepository>\Credentials\NoName.HOST.USER.BT-Mail-Credentials
mail_prog=<BTPath>\Tools\BT-Mail-Send.cmd
```

### Required keys

| Key | Type | Description |
| --- | --- | --- |
| `logpath` | folder path | Existing folder that will receive the invocation log. **Must end with a trailing backslash** because the file name is appended directly. If missing or the folder does not exist, the script exits with code `1` before any check is performed. |
| `threshold_min` | integer (minutes) | Minimum host uptime before a shutdown is allowed. The current uptime is derived from `LastBootUpTime` and rounded to whole minutes; overnight boundaries are handled by adding `1440` when the calendar day changes. |
| `start_hour` | integer 0–23 | Lower bound of the allowed shutdown hour range (inclusive). |
| `end_hour` | integer 0–23 | Upper bound of the allowed shutdown hour range (**exclusive**). If `end_hour <= start_hour`, the window is treated as spanning midnight (e.g. `start_hour=22`, `end_hour=2` allows shutdown at 22, 23, 0 and 1). |
| `shutdown_allow` | `0` / `1` | Global kill-switch. `1` enables the shutdown; any other value (including empty) blocks it. |
| `shutdown_delay` | integer (seconds) | Value passed to `shutdown /s /t <n>` — grace period between the call and the actual power-off. |

### Optional keys

| Key | Type | Description |
| --- | --- | --- |
| `flag_path` | folder path | Folder scanned for the presence of `*.flg` and `*.lock` files. If any such file exists, the shutdown is blocked. Leaving the value empty **skips** this check and passes it as `PASSED: skip check`. Typically points at the Backup-Toolkit `Locks/` folder so an in-progress backup or plan prevents shutdown. |
| `mail_to` | string | Recipient list forwarded to `mail_prog`. Multiple addresses can be separated by `;`, as accepted by [BT-Mail-Send](./BT-Mail-Send.md). |
| `mail_credentials` | file path | Full path to a `BT-Mail-Credentials` file to be used for the notification. |
| `mail_prog` | file path | Full path to the mail-sending program (usually `Tools/BT-Mail-Send.cmd`). It is invoked as `mail_prog "mail_credentials" "mail_to" "<subject>" "<body>"`. |

The notification is dispatched **only when `mail_to`, `mail_credentials` and `mail_prog` are all set**. If any of the three is empty, the log records `Skip Send Mail` and the shutdown continues without notification.

---

## Pre-shutdown checks

All five checks must pass for `shutdown.exe` to be invoked. Each check writes a `PASSED` / `NOT-PASSED` line to the log so the reason for a skipped shutdown is always visible.

| # | Check | Condition to pass |
| --- | --- | --- |
| 1 | Threshold | Current uptime (minutes) is greater than or equal to `threshold_min`. |
| 2 | Allowed time | Current hour is inside the `[start_hour, end_hour]` window; overnight ranges are supported by folding around midnight. |
| 3 | Users | No logged-in interactive users are detected on the host. |
| 4 | Flags / Locks | `flag_path` is empty (check skipped) **or** no `*.flg` / `*.lock` files exist directly in `flag_path`. |
| 5 | Shutdown allow | `shutdown_allow` equals `1`. |

---

## Usage

### Manual run against a specific INI file

```cmd
"BT-Shutdown.cmd" "BT-Shutdown.HOSTNAME.ini"
```

### From Windows Task Scheduler

Use [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md) to create and manage a task that invokes `BT-Shutdown.cmd` through `cmd.exe` with the host-specific INI file. Start the administrative menu with `Tools/Admin/BT-Shutdown-Schedule.cmd`.

The utility registers a one-time trigger for today at midnight plus `StartOffsetMinutes`, repeating every `IntervalMinutes` indefinitely. The wrapper defaults are an offset of `4` minutes and an interval of `20` minutes; a separate daily trigger is not needed. Each run re-evaluates the shutdown conditions.

The task should run with an account that has permission to shut down the machine.

---

## Output

The script writes two streams:

- **Log file** — `<logpath>\BT-Shutdown_YYYY-MM-DD_HH-MM-SS.log` receives the invocation header, all resolved parameters, the boot / current timestamps, every check outcome, the listed users and flag files, the mail call (if any) and the `shutdown` exit code.
- **Standard output** — the same log file is printed with `type` at the end of the run so any scheduled task capturing STDOUT sees the full report. A compact status token (see [Pre-shutdown checks](#pre-shutdown-checks)) is emitted before the file dump.

The log file is created fresh on every invocation (unique timestamp in the file name). No log rotation is performed by the script — cleanup of old files must be done externally.

---

## Exit / Error Handling

| Code | Meaning |
| --- | --- |
| `0` | Script finished. This includes runs that **skipped** the shutdown because a check failed or a non-critical parameter was empty; consult the log for the actual decision. |
| `1` | Fatal input error, no log written or partial log only: missing argument, INI file does not exist, `logpath` is empty, or `logpath` folder does not exist. |

The exit code of `shutdown.exe` itself is written to the log (`Shutdown executeed successfully` or `Shutdown completed with Error: <code>`) but is not propagated as the script's exit code.

---

## Integration Points

| Component | How it relates to `BT-Shutdown` |
| --- | --- |
| [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md) | Creates and manages the repeating Windows scheduled task that invokes `BT-Shutdown.cmd` with the selected INI file. The administrative scripts are not used during scheduled shutdown checks. |
| [BT-Mail-Send](./BT-Mail-Send.md) | Invoked as `mail_prog` to dispatch the shutdown notification e-mail when `mail_to`, `mail_credentials` and `mail_prog` are all configured. |
| [BT-Mail-Credentials](./BT-Mail-Credentials.md) | Produces the `BT-Mail-Credentials` file referenced by `mail_credentials`. |
| [BT-Backup](./BT-Backup.md) / [BT-Plan](./BT-Plan.md) | Create lock files in `Locks/` while running; pointing `flag_path` at that folder makes `BT-Shutdown` skip the shutdown while any backup or plan session is active. |

---

## Operational Recommendations

- Keep the `start_hour` / `end_hour` allowed shutdown window from overlapping the normal working hours of `BT-Backup` and `BT-Plan`, so the machine is not shut down while a backup or plan run is expected to be active.
- Point `flag_path` at the Backup-Toolkit `Locks/` folder so any active `.lock` file automatically vetoes the shutdown.
- Use `shutdown_delay` values large enough (e.g. `60` seconds) to let logged-in users abort the shutdown with `shutdown /a` if the check for empty user sessions was overly strict at the moment of evaluation.
- Store INI files under `Backups/BackupSystem/` and name them `BT-Shutdown.<HOSTNAME>_<user>.ini` to keep per-host configurations discoverable.
- Ensure `logpath` ends with a trailing backslash (`\`) — the script appends the log file name directly without inserting a separator.
- Test the configuration with `shutdown_allow=0` first: every check runs and is logged, but the actual shutdown is blocked, so the operator can verify the decision path before enabling it.
- Verify the mail path by running the configured `mail_prog` manually with the same credentials file — `BT-Shutdown` will not surface mail delivery failures as its own exit code.
- Rotate or archive the log folder periodically; the script never deletes old logs.

---

## Notes

- The script is a pure `cmd.exe` batch script; there is no PowerShell version. It only shells out to `powershell.exe` twice — to format the current time and to read `LastBootUpTime`.
- The uptime calculation is minute-resolution and assumes at most one day-change between boot and the current moment (a `1440`-minute correction is added when the calendar day differs). Hosts up for more than 24 hours are still handled correctly because the actual `LastBootUpTime` reflects the true boot moment.
- The `[Settings]` section header is present in the INI for readability but is not parsed — every `key=value` pair in the file is candidate for the lookup.
- `shutdown /s /t <n>` schedules the shutdown asynchronously; the script exits before the machine actually powers off, which is why the log is flushed and printed to STDOUT before the shutdown command is issued.

---

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md)
- [BT-Mail-Send](./BT-Mail-Send.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan](./BT-Plan.md)
- [Glossary](./Glossary.md)
