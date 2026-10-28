# BT-Plan-Schedule

Administrative utility for creating and managing the Windows scheduled task that runs a Backup-Toolkit plan (`BT-Plan.ps1`) on a daily basis. The tool wraps the built-in `ScheduledTasks` PowerShell cmdlets (`Register-ScheduledTask`, `Unregister-ScheduledTask`, `Start-ScheduledTask`, etc.) and drives them from a small text menu, so operators do not have to build `Action`/`Trigger`/`Settings` objects by hand.

The launcher can be customised with host-specific defaults; see [Customised launcher](#customised-launcher-optional).

The scheduled task is registered under a specific Windows user account and requires the account's password at creation time. Because the password is submitted to the Task Scheduler service, the script **must be run interactively** (it prompts for the password with `Read-Host -AsSecureString`). **Elevated privileges (Administrator) are only required for `Create` and `Delete`** — the other menu entries (Status, Run, Enable, Disable) work from a normal console. The menu header reports whether the script is running with administrator privileges. Without elevation, the actual `Create` action in the create sub-menu and `Delete` are blocked before the password or confirmation prompt; opening the create sub-menu remains available.

The utility is an **interactive text-menu console application** — all operations (setting parameters, creating, deleting, checking status, running, enabling and disabling the task) are performed through prompts printed on the console. No Windows Forms and no configuration file are involved.

Part of the **Backup-Toolkit** — a PowerShell-based backup automation platform for Windows.

---

## Purpose

`BT-Plan-Schedule` provides a controlled, repeatable way to register the Windows scheduled task that executes a Backup-Toolkit plan daily, without having to write ad-hoc `schtasks.exe` or `Register-ScheduledTask` calls for every host.

Typical scenarios:

- One-off registration of the daily `BT-Plan` scheduled task on a new host.
- Re-registering the task after changing the plan configuration file or the installation directory.
- Checking whether the task is still enabled and when it last / next runs.
- Running the task on demand for verification.
- Temporarily disabling the task without deleting it, then re-enabling it later.
- Removing the task before uninstalling Backup-Toolkit from a host.

The utility is intended for **administrators** installing or maintaining Backup-Toolkit on a machine. It is not called by other Backup-Toolkit automation at runtime.

---

## Location

| Item | Path |
| --- | --- |
| PowerShell script | `Tools/Admin/BT-Plan-Schedule.ps1` |
| CMD wrapper | `Tools/Admin/BT-Plan-Schedule.cmd` |
| Target script executed by the task | `Tools/BT-Plan.ps1` |
| Related documentation | `Docs/BT-Plan.md` |

---

## Requirements

- Windows PowerShell 5.1
- `ScheduledTasks` module (ships with Windows)
- Interactive console session (the script prompts for the user's password with `Read-Host`)
- Permission to register scheduled tasks for the target user — in practice this means running the script **elevated** (as Administrator) **only when performing `Create` or `Delete`**; `Status`, `Run`, `Enable` and `Disable` do not require elevation
- A prepared `BT-Plan` configuration file (`.BT-Plan`) and a valid Backup-Toolkit installation directory

No network access is required.

---

## Process Overview

1. The CMD wrapper (`BT-Plan-Schedule.cmd`) sets the default values for `TaskName`, `Description`, `StartTime`, `ConfigFilePath` and `BTPath` (the path to `BackupToolkitHome`), and launches the PowerShell script with those values as parameters.
2. The script normalises `ConfigFilePath` and `BTPath` (the path to `BackupToolkitHome`), verifies that they exist and prints the current parameters at the top of the main menu.
3. The main text menu is displayed with the following options: **Parameters**, **Create**, **Delete**, **Status**, **Run**, **Enable**, **Disable**, **Quit**.
4. For **Create**, a sub-menu is shown that lets the operator review / adjust the create-specific parameters and then confirm task creation; the password of the task user is entered at that step.
5. On confirmation, the script builds `New-ScheduledTaskAction`, `New-ScheduledTaskTrigger` (Daily, at `StartTime`) and `New-ScheduledTaskSettingsSet`, then calls `Register-ScheduledTask` with the current Windows user (`DOMAIN\User`) and the entered password.
6. Other menu entries invoke the matching `ScheduledTasks` cmdlet: `Unregister-ScheduledTask`, `Get-ScheduledTask` + `Get-ScheduledTaskInfo`, `Start-ScheduledTask`, `Enable-ScheduledTask`, `Disable-ScheduledTask`.
7. The script does **not** write any configuration file of its own — all state is stored in Windows Task Scheduler under the task name provided by the operator.

`BT-Plan-Schedule.cmd` is always the entry point for the operator: it carries the default values for `TaskName`, `Description`, `StartTime`, `ConfigFilePath` and `BTPath` (the path to `BackupToolkitHome`), and passes them to `BT-Plan-Schedule.ps1`. Those defaults can be reviewed and overridden from the **Parameters** menu (main menu or create sub-menu) before **Create** is confirmed — the changes apply only to the current session and are not written back to the `.cmd` file.

When **Create** is confirmed, Task Scheduler is configured to launch `Tools/BT-Plan.ps1` directly through `powershell.exe`, with the selected configuration file and `--NoPause`. The task's working directory is `BackupToolkitHome`. The administrative CMD wrapper `BT-Plan-Schedule.cmd` and `BT-Plan-Schedule.ps1` are used only to configure and manage the task, not during scheduled plan execution.

The following command is executed by Windows Task Scheduler at the configured time:

```text
powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "<BackupToolkitHome>\tools\BT-Plan.ps1" "<ConfigFilePath>" --NoPause
```

---

## Parameters

All parameters are supplied to the PowerShell script by the CMD wrapper. They can also be edited from the text menu at runtime — the menu changes affect only the current session and are not persisted back to the `.cmd` file.

### `-TaskName <string>`

**Required.** Name of the Windows scheduled task to create or manage. All non-create actions (Delete, Status, Run, Enable, Disable) operate on the task identified by this name.

Default value in the CMD wrapper: `BT-Plan`.

### `-Description <string>`

Optional. Human-readable description written to the `Description` field of the task.

Default value in the CMD wrapper: `Backup-Toolkit daily planned backups`.

### `-StartTime <string>`

**Required for Create.** Time of day at which the daily trigger fires, in a format accepted by `New-ScheduledTaskTrigger -At`, e.g. `0:20`, `02:15`, `23:30`.

Default value in the CMD wrapper: `0:20`.

### `-ConfigFilePath <path>`

**Required for Create.** Full path to the `BT-Plan` configuration file (`.BT-Plan`) that the scheduled task will execute. The script verifies that the file exists on startup and prints an error if it does not.

Default value in the CMD wrapper: empty (must be filled in the `.cmd` file or via the menu before creating the task).

### `-BTPath <path>`

**Required for Create.** Full path to `BackupToolkitHome`, the Backup-Toolkit installation directory containing the `Tools/` subfolder. It is used to locate `Tools/BT-Plan.ps1` and is set as the task's working directory. The PowerShell parameter for this path is named `-BTPath`.

Default value in the CMD wrapper: `%~dp0..\..` (two directories above the `.cmd` file, i.e. the toolkit root). The path must **not** end with a backslash.

---

## Usage

### Register the daily task on a new host

By default the standard `Tools/Admin/BT-Plan-Schedule.cmd` shipped with Backup-Toolkit is used.

1. Run `Tools/Admin/BT-Plan-Schedule.cmd` **as Administrator** (elevation is only required because this walkthrough uses `Create`).
2. In the main menu press `C` (Create).
3. Press `P` in the create sub-menu and set `TaskName`, `Description`, `StartTime` and `ConfigFilePath` to match the host (`BTPath`, the path to `BackupToolkitHome`, is derived from the `.cmd` location and normally left as-is).
4. Press `C` in the create sub-menu, then enter the password of the current Windows user when prompted.
5. Press `Q` to leave the create sub-menu, then `Q` again to exit the script.

#### Customised launcher (optional)

If the same defaults should be reused across sessions — or a host needs several `BT-Plan` tasks with different parameters — copy `Tools/Admin/BT-Plan-Schedule.cmd` to a maintenance location and edit the copy. The typical location is `BackupRepository/Config/Admin/` (see [Config in the Glossary](./Glossary.md)); another suitable administrative location may also be used.

1. Copy `Tools/Admin/BT-Plan-Schedule.cmd` to `BackupRepository/Config/Admin/` (or another maintenance location). The copy may be renamed (e.g. `BT-Plan-Schedule-<host>.cmd`, `BT-Plan-Schedule-nightly.cmd`).
2. Open the copy in a text editor and adjust `TaskName`, `Description`, `StartTime` and `ConfigFilePath`. Set `BTPath` to the actual `BackupToolkitHome` path. The default (`%~dp0..\..`) is resolved relative to the launcher's location and only points to the toolkit root when the launcher is in `Tools/Admin/`.
3. Run the copied `.cmd` **as Administrator** (required for `Create`) and follow steps 2–5 above; the operator can still override any value from the **Parameters** menu for the current session.

### Check task status

1. Run `BT-Plan-Schedule.cmd`.
2. In the main menu press `S` (Status).
3. The script prints `TaskName`, `State`, `LastRunTime`, `NextRunTime`, `LastTaskResult`, `NumberOfMissedRuns` and `Description` for the current task.

### Run the task on demand

1. Run `BT-Plan-Schedule.cmd`.
2. In the main menu press `R` (Run). The task is triggered immediately via `Start-ScheduledTask`.

### Temporarily disable / re-enable the task

- Press `X` (Disable) — asks for confirmation `Y/N` and then calls `Disable-ScheduledTask`.
- Press `E` (Enable) — calls `Enable-ScheduledTask` without extra confirmation.

### Remove the task

1. Run `BT-Plan-Schedule.cmd` **as Administrator** (required for `Delete`).
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
StartTime:      <StartTime>
ConfigFilePath: <ConfigFilePath>
BTPath:         <BTPath>
TaskUser:       <DOMAIN\User>
```

with the following options:

| Key | Action |
| --- | --- |
| `P` | **Parameters** — prompt for `TaskName`, `Description`, `StartTime`, `ConfigFilePath`, `BTPath` (press Enter to keep the current value). |
| `C` | **Create** — checks for administrator privileges, validates that the required parameters are non-empty, prompts for the current user's password, and registers the scheduled task. Without elevation, the action is blocked before validation or the password prompt. |
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
| Invalid `ConfigFilePath` / `BTPath` | `ERROR: Invalid file path for '<name>': <value>` — the operator has to press Enter. |
| Unhandled exception | The outer `try/catch` prints a `Write-Error` line, PowerShell sets `$LASTEXITCODE` / `%ERRORLEVEL%` to `1` and the script terminates. |

The unhandled-exception line has the format:

```text
Error: (1)[<script>:<line>/<caller>:<line>] Unhandled exception: <message>
```

Because it is written with `Write-Error`, PowerShell signals the failure on the error stream. This is the fallback path for unexpected runtime errors that are not covered by the inline handlers above.

---

## Integration Points

`BT-Plan-Schedule` sits at the administrative edge of the Backup-Toolkit — it does not participate in the runtime flow of a backup, but it is the tool that arms the daily execution of `BT-Plan`.

| Component | Relationship |
| --- | --- |
| [BT-Plan](./BT-Plan.md) | The scheduled task registered by `BT-Plan-Schedule` executes `Tools/BT-Plan.ps1` daily with the configured `.BT-Plan` file. |
| [BT-Backup](./BT-Backup.md) | Indirectly invoked — `BT-Plan` orchestrates one or more `BT-Backup` runs based on its configuration. |
| Windows Task Scheduler | The persistent store of the task; `BT-Plan-Schedule` only wraps the standard `ScheduledTasks` cmdlets and does not maintain its own state. |

---

## Operational Recommendations

- Run the script **elevated** (Administrator) when using `Create` or `Delete` — registering or unregistering a scheduled task requires the appropriate privileges; the script itself does not self-elevate. Other operations (`Status`, `Run`, `Enable`, `Disable`) can be executed from a regular console.
- Use a dedicated service account when possible instead of a personal user, so that password changes on the personal account do not break the schedule.
- After each Windows password change for the task user, re-run `Create` to re-register the task with the new password — Task Scheduler does not accept password changes retroactively.
- Copy `BT-Plan-Schedule.cmd` to a maintenance location and adjust `TaskName`, `Description`, `StartTime` and `ConfigFilePath` there, so that the defaults survive Backup-Toolkit upgrades.
- Keep `BTPath` pointing at the current `BackupToolkitHome`; if the toolkit is moved, re-register the task so that the `-File` argument targets the new location.
- Use `Status` regularly (or as part of monitoring) to detect missed runs (`NumberOfMissedRuns > 0`) or non-zero `LastTaskResult` values.
- Prefer `Disable` over `Delete` when temporarily suspending backups — it preserves description, trigger and history.

---

## Notes

- The utility is interactive and console-based; it is not designed to be embedded in pipelines or invoked headlessly.
- No configuration file is produced or read by the script itself — all persistent state lives in Windows Task Scheduler.
- The password entered during `Create` is never written to disk by `BT-Plan-Schedule`; it is handed directly to `Register-ScheduledTask`, which stores it inside the Task Scheduler credential store.
- The `.cmd` wrapper is the recommended entry point — it fills in sensible defaults and computes `BTPath` (the path to `BackupToolkitHome`) relative to its own location.
- The script only supports a **Daily** trigger. More complex schedules (weekly patterns, multiple triggers, boot triggers, etc.) must be configured directly in Task Scheduler after registration.

---

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Plan](./BT-Plan.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Shutdown](./BT-Shutdown.md)
- [Glossary](./Glossary.md)
