# BT-Shutdown-Schedule

Administrative utility for creating and managing the Windows scheduled task that periodically runs `BT-Shutdown.cmd` with a selected configuration file. The tool wraps the built-in `ScheduledTasks` PowerShell cmdlets (`Register-ScheduledTask`, `Unregister-ScheduledTask`, `Start-ScheduledTask`, etc.) and drives them from a small text menu, so operators do not have to build `Action`/`Trigger`/`Settings` objects by hand.

The launcher can be customised with host-specific defaults; see [Customised launcher](#customised-launcher-optional).

The task's first trigger is set to today's configurable minute offset from midnight, then repeats at a configurable interval indefinitely. For example, an offset of `4` and interval of `20` starts at 00:04 and repeats every 20 minutes. If 00:04 has already passed when the task is created, `StartWhenAvailable` allows it to start as soon as possible. A separate daily trigger is not needed.

The scheduled task is registered under a specific Windows user account and requires the account's password at creation time. Because the password is submitted to the Task Scheduler service, the script **must be run interactively** (it prompts for the password with `Read-Host -AsSecureString`). **Elevated privileges (Administrator) are only required for `Create` and `Delete`** — the other menu entries (Status, Run, Enable, Disable) work from a normal console. The menu header reports whether the script is running with administrator privileges. Without elevation, the actual `Create` action in the create sub-menu and `Delete` are blocked before the password or confirmation prompt; opening the create sub-menu remains available.

The utility is an **interactive text-menu console application** — all operations (setting parameters, creating, deleting, checking status, running, enabling and disabling the task) are performed through prompts printed on the console. No Windows Forms and no configuration file are involved.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Shutdown-Schedule` provides a controlled, repeatable way to register the Windows scheduled task that periodically runs `BT-Shutdown.cmd`, without having to write ad-hoc `schtasks.exe` or `Register-ScheduledTask` calls for every host. The task invokes the batch utility directly; the PowerShell script is used only to configure and manage the task.

Typical scenarios:

- One-off registration of the repeating `BT-Shutdown` task on a new host.
- Re-evaluating shutdown conditions every 20 minutes after the host's nightly work is expected to finish.
- Re-registering the task after changing the configuration file path, the interval or the installation directory.
- Checking whether the task is still enabled and when it last / next runs.
- Running the task on demand for verification.
- Temporarily disabling the task without deleting it, then re-enabling it later.
- Removing the task before uninstalling Backup-Toolkit from a host.

The utility is intended for **administrators** installing or maintaining Backup-Toolkit on a machine. It is not called by other Backup-Toolkit automation at runtime.

---

## Location

| Item | Path |
| --- | --- |
| CMD wrapper | `Tools/Admin/BT-Shutdown-Schedule.cmd` |
| PowerShell task manager | `Tools/Admin/BT-Shutdown-Schedule.ps1` |
| Program executed by the task | `Tools/BT-Shutdown.cmd` |
| Related documentation | `Docs/BT-Shutdown.md` |

---

## Requirements

- Windows PowerShell 5.1
- `ScheduledTasks` module (ships with Windows)
- Interactive console session (the script prompts for the user's password with `Read-Host`)
- Permission to register scheduled tasks for the target user — in practice this means running the script **elevated** (as Administrator) **only when performing `Create` or `Delete`**; `Status`, `Run`, `Enable` and `Disable` do not require elevation
- A prepared `BT-Shutdown` configuration file (`*.BT-Shutdown.ini`) and a valid Backup-Toolkit installation directory
- Permission for the task user to run `shutdown.exe` (member of *Administrators* or the *Shut down the system* user right), as required by [BT-Shutdown](./BT-Shutdown.md)

No network access is required by the scheduler itself. Network access may be needed by the optional e-mail notification configured in the `BT-Shutdown` configuration file.

---

## Process Overview

1. `BT-Shutdown-Schedule.cmd` supplies defaults for `TaskName`, `Description`, `StartOffsetMinutes`, `IntervalMinutes`, `ConfigFilePath` and `BTPath`, then starts the PowerShell task manager.
2. The manager normalizes and checks configured paths, then displays its text menu.
3. For Create, the create sub-menu allows the operator to review and change task settings. The manager validates the required values and the numeric ranges for the offset and interval.
4. The operator enters the current Windows user's password. The manager creates a one-time trigger for today at midnight plus `StartOffsetMinutes` and sets it to repeat every `IntervalMinutes` indefinitely. If that time has passed, the task is configured to start as soon as possible.
5. The scheduled task runs `BT-Shutdown.cmd` through `cmd.exe`, passing `ConfigFilePath` as its argument. Its working directory is set to `BackupToolkitHome`.
6. Other menu actions call the corresponding `ScheduledTasks` cmdlets to delete, inspect, run, enable or disable the task.

`BT-Shutdown-Schedule.cmd` is always the entry point for the operator: it carries the default values and passes them to `BT-Shutdown-Schedule.ps1`. Those defaults can be reviewed and overridden from the **Parameters** menu (main menu or create sub-menu) before **Create** is confirmed — the changes apply only to the current session and are not written back to the `.cmd` file.

When **Create** is confirmed, Task Scheduler is configured to launch `cmd.exe` with `BT-Shutdown.cmd` and the configuration file as its argument, with `BackupToolkitHome` as the working directory. The administrative CMD wrapper `BT-Shutdown-Schedule.cmd` and `BT-Shutdown-Schedule.ps1` are used only to configure and manage the task, not during scheduled shutdown checks.

The following command is executed by Windows Task Scheduler at the configured time:

```text
cmd.exe /c ""<BackupToolkitHome>\tools\BT-Shutdown.cmd" "<ConfigFilePath>""
```

The task is registered with a single **one-time** trigger set to today at midnight plus `StartOffsetMinutes`. The trigger's repetition interval is `IntervalMinutes` with no duration limit, which Task Scheduler shows as repeating *indefinitely*; a separate daily trigger is therefore not needed. The task settings allow starting on batteries, do not stop it when the host switches to battery power and run it as soon as possible after a missed start (`StartWhenAvailable`).

---

## Parameters

The CMD wrapper passes these values to the PowerShell manager. The create sub-menu can override them for the current session.

### `-TaskName <string>`

**Required.** Name of the Windows scheduled task to create or manage.

Default: `BT-Shutdown`.

### `-Description <string>`

Optional. Human-readable description stored with the task.

Default: `Backup-Toolkit scheduled shutdown`.

### `-StartOffsetMinutes <integer>`

**Required for Create.** Number of minutes after midnight for the first trigger. Valid range: `0` to `1439`. For example, `4` sets the trigger for 00:04 today. If that time has passed, `StartWhenAvailable` allows the task to start as soon as possible after registration.

Default: `4`.

### `-IntervalMinutes <integer>`

**Required for Create.** Number of minutes between repeated runs. Valid range: `1` to `1440`.

Default: `20`.

### `-ConfigFilePath <path>`

**Required for Create.** Full path to the configuration file passed to `BT-Shutdown.cmd`. The file must exist.

Default: empty; set it in the wrapper or from the create sub-menu before creating the task.

### `-BTPath <path>`

**Required.** Path to `BackupToolkitHome`, which contains `Tools/`. It is used to locate `BT-Shutdown.cmd` and is also set as the task's working directory.

Default: `%~dp0..\..`, resolved relative to the wrapper in `Tools/Admin/`.

---

## Usage

### Create the task

1. Set `ConfigFilePath` in `Tools/Admin/BT-Shutdown-Schedule.cmd`, or leave it empty and set it in the create sub-menu.
2. Run `BT-Shutdown-Schedule.cmd` as Administrator.
3. Select `C` (Create), then `P` (Parameters) to review or change `TaskName`, `Description`, `StartOffsetMinutes`, `IntervalMinutes`, `ConfigFilePath` and `BTPath`.
4. Select `C` to create the task and enter the current Windows user's password when prompted.
5. Select `Q` to leave the create sub-menu, then `Q` again to exit.

For a first verification, set `shutdown_allow=0` in the shutdown configuration. This exercises the checks without allowing the computer to shut down. See [BT-Shutdown](./BT-Shutdown.md).

#### Customised launcher (optional)

If the same defaults should be reused across sessions — or a host needs several `BT-Shutdown` tasks with different parameters — copy `Tools/Admin/BT-Shutdown-Schedule.cmd` to a maintenance location and edit the copy. The typical location is `BackupRepository/Config/Admin/` (see [Config in the Glossary](./Glossary.md)); another suitable administrative location may also be used.

1. Copy `Tools/Admin/BT-Shutdown-Schedule.cmd` to `BackupRepository/Config/Admin/` (or another maintenance location). The copy may be renamed (e.g. `BT-Shutdown-Schedule-<host>.cmd`).
2. Open the copy in a text editor and adjust `TaskName`, `Description`, `StartOffsetMinutes`, `IntervalMinutes` and `ConfigFilePath`. Set `BTPath` to the actual `BackupToolkitHome` path. The default (`%~dp0..\..`) is resolved relative to the launcher's location and only points to the toolkit root when the launcher is in `Tools/Admin/`.
3. Run the copied `.cmd` **as Administrator** (required for `Create`) and follow steps 2–5 above; the operator can still override any value from the **Parameters** menu for the current session.

### Check task status

1. Run `BT-Shutdown-Schedule.cmd`.
2. In the main menu press `S` (Status).
3. The script prints `TaskName`, `State`, `LastRunTime`, `NextRunTime`, `LastTaskResult`, `NumberOfMissedRuns` and `Description` for the current task.

### Run the task on demand

1. Run `BT-Shutdown-Schedule.cmd`.
2. In the main menu press `R` (Run). The task is triggered immediately via `Start-ScheduledTask`.

> **Warning:** Run executes `BT-Shutdown.cmd` exactly as a scheduled run would. If all pre-shutdown checks pass and `shutdown_allow=1`, the host **is shut down**. Use `shutdown_allow=0` in the configuration file to test safely.

### Temporarily disable / re-enable the task

- Press `X` (Disable) — asks for confirmation `Y/N` and then calls `Disable-ScheduledTask`.
- Press `E` (Enable) — calls `Enable-ScheduledTask` without extra confirmation.

### Remove the task

1. Run `BT-Shutdown-Schedule.cmd` **as Administrator** (required for `Delete`).
2. In the main menu press `D` (Delete).
3. Confirm with `Y`. The script calls `Unregister-ScheduledTask -Confirm:$false`.

---

## Text Menu

The script is driven by a **hierarchical text menu** printed on the console. There is no GUI, no clickable control and no file dialog — every action is triggered by a single-letter choice.

### Header

Before the main menu is redrawn, the script prints:

```text
Parameters
ScriptVersion:  <version>
TaskName:       <TaskName>
```

If any of the configured paths (`ConfigFilePath`, `BTPath`) is invalid, an `ERROR:` line is printed above and the operator is asked to press Enter to continue — the menu is still shown afterwards.

### Main menu

| Key | Action |
| --- | --- |
| `P` | **Parameters** — prompt to change `TaskName` for the current session. |
| `C` | **Create** — open the create sub-menu (see below). |
| `D` | **Delete** — checks for administrator privileges, then asks for confirmation and calls `Unregister-ScheduledTask`. |
| `S` | **Status** — shows the task's state, last / next run time, last result and number of missed runs. |
| `R` | **Run** — triggers the task immediately via `Start-ScheduledTask`. |
| `E` | **Enable** — enables the task via `Enable-ScheduledTask`. |
| `X` | **Disable** — asks for confirmation and calls `Disable-ScheduledTask`. |
| `Q` | **Quit** — exits the script. |

### Create sub-menu

After selecting `C` in the main menu, a create-specific view is displayed:

```text
Create Parameters
TaskName:       <TaskName>
Description:    <Description>
First run:      midnight + <StartOffsetMinutes> min
Interval:       every <IntervalMinutes> minutes
ConfigFilePath: <ConfigFilePath>
BTPath:         <BTPath>
TaskUser:       <DOMAIN\User>
```

with the following options:

| Key | Action |
| --- | --- |
| `P` | **Parameters** — prompt for `TaskName`, `Description`, `StartOffsetMinutes`, `IntervalMinutes`, `ConfigFilePath`, `BTPath` (press Enter to keep the current value). |
| `C` | **Create** — checks for administrator privileges, validates the required parameters, prompts for the current user's password, and registers the scheduled task. Without elevation, the action is blocked before validation or the password prompt. |
| `Q` | **Quit** — return to the main menu. |

### Prompts and confirmations

- `Read-Host` is used both for menu choices and for parameter values.
- Password entry uses `Read-Host -AsSecureString` — the password is not echoed to the console.
- Destructive actions (Delete, Disable) require a `Y/N` confirmation before the underlying cmdlet is called.
- Every action ends with a `Press Enter to continue` prompt so that the console output remains visible before the menu is redrawn.

---

## Exit / Error Handling

The script does not define numeric exit codes for individual operations. Instead:

| Situation | Behaviour |
| --- | --- |
| Successful `Quit` | The script exits with code `0`. |
| `Create` or `Delete` selected without administrator privileges | `ERROR: Administrator privileges are required to create or delete scheduled tasks.` — the action is not performed and the menu resumes. |
| Missing required parameter for Create | `ERROR: Required parameter '<name>' is empty.` — no task is created, menu resumes. |
| `StartOffsetMinutes` not an integer in `0`–`1439` | `ERROR: 'StartOffsetMinutes' must be an integer between 0 and 1439.` — no task is created. |
| `IntervalMinutes` not an integer in `1`–`1440` | `ERROR: 'IntervalMinutes' must be an integer between 1 and 1440.` — no task is created. |
| Invalid `ConfigFilePath` / `BTPath` | `ERROR: Invalid file path for '<name>': <value>` — the operator has to press Enter. |
| Task Scheduler call fails (e.g. wrong password, task not found) | `Unable to <register / unregister / get / start / enable / disable> scheduled task '<TaskName>': <message>` — the menu resumes. |
| Delete or Disable not confirmed | `Operation cancelled.` — the task is left unchanged. |
| Unknown menu key | `Invalid choice.` — the menu is shown again. |
| Unhandled exception | The outer `try/catch` prints a `Write-Error` line, PowerShell sets `$LASTEXITCODE` / `%ERRORLEVEL%` to `1` and the script terminates. |

The existence of `ConfigFilePath` and `BTPath` is checked whenever the main menu header is displayed. `Create` itself verifies only that the required values are non-empty and that the offset and interval are in range, so a path changed in the create sub-menu is not re-checked before the task is registered; verify it in the header after returning to the main menu.

The unhandled-exception line has the format:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because it is written with `Write-Error`, PowerShell signals the failure on the error stream. This is the fallback path for unexpected runtime errors that are not covered by the inline handlers above.

---

## Integration Points

`BT-Shutdown-Schedule` sits at the administrative edge of the Backup-Toolkit — it does not participate in the runtime flow of a backup, but it is the tool that arms the periodic execution of `BT-Shutdown`.

| Component | Relationship |
| --- | --- |
| [BT-Shutdown](./BT-Shutdown.md) | The scheduled task registered by `BT-Shutdown-Schedule` executes `Tools/BT-Shutdown.cmd` with the configured file at every repetition. |
| [BT-Backup](./BT-Backup.md) / [BT-Plan](./BT-Plan.md) | Create lock files in `Locks/` while running; when `flag_path` points at that folder, `BT-Shutdown` skips the shutdown while any session is active. |
| [BT-Mail-Send](./BT-Mail-Send.md) | Invoked by `BT-Shutdown` (not by the scheduler) when notification settings are configured. |
| Windows Task Scheduler | The persistent store of the task; `BT-Shutdown-Schedule` only wraps the standard `ScheduledTasks` cmdlets and does not maintain its own state. |

---

## Operational Recommendations

- Run the script **elevated** (Administrator) when using `Create` or `Delete` — registering or unregistering a scheduled task requires the appropriate privileges; the script itself does not self-elevate. Other operations (`Status`, `Run`, `Enable`, `Disable`) can be executed from a regular console.
- Choose the offset and interval so shutdown checks run after backup or plan jobs are expected to finish. For a 20-minute interval beginning at 00:04, runs continue at 00:04, 00:24, 00:44, and so on, without a daily repetition limit.
- Point `flag_path` in the shutdown configuration at the toolkit `Locks/` folder so active backup or plan jobs can prevent shutdown.
- Test with `shutdown_allow=0` before enabling real shutdowns; `Run` from the menu behaves like a scheduled run.
- Use a dedicated account that is allowed to shut the machine down instead of a personal user, so that password changes on the personal account do not break the schedule.
- After each Windows password change for the task user, re-run `Create` to re-register the task with the new password — Task Scheduler does not accept password changes retroactively.
- Copy `BT-Shutdown-Schedule.cmd` to a maintenance location and adjust the settings there, so that the defaults survive Backup-Toolkit upgrades.
- Keep `BTPath` pointing at the current `BackupToolkitHome` and `ConfigFilePath` at the current configuration file; if either is moved, re-register the task.
- Use `Status` regularly (or as part of monitoring) to detect missed runs (`NumberOfMissedRuns > 0`) or non-zero `LastTaskResult` values.
- Prefer `Disable` over `Delete` when temporarily suspending shutdowns — it preserves description, trigger and history.

---

## Notes

- The utility is interactive and console-based; it is not designed to be embedded in pipelines or invoked headlessly.
- No configuration file is produced or read by the script itself — all persistent state lives in Windows Task Scheduler.
- The password entered during `Create` is never written to disk by `BT-Shutdown-Schedule`; it is handed directly to `Register-ScheduledTask`, which stores it inside the Task Scheduler credential store.
- The task is registered with `Register-ScheduledTask -Force`: running `Create` with an existing `TaskName` **replaces** that task.
- The `.cmd` wrapper is the recommended entry point — it fills in sensible defaults and computes `BTPath` relative to its own location.
- The registered task starts `BT-Shutdown.cmd` through `cmd.exe`; the administrative wrapper `BT-Shutdown-Schedule.cmd` and `BT-Shutdown-Schedule.ps1` are not used at run time.
- The script registers a single trigger. More complex schedules (several triggers, weekday limits, boot triggers, etc.) must be configured directly in Task Scheduler after registration.

---

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Shutdown](./BT-Shutdown.md)
- [BT-Plan-Schedule](./BT-Plan-Schedule.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [BT-Mail-Send](./BT-Mail-Send.md)
- [Glossary](./Glossary.md)