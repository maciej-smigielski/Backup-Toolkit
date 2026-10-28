# Components

This document is a detailed catalog of Backup-Toolkit's components and dependencies: runtime tools, administrative utilities, PowerShell modules, external utilities, and shell launchers. Here, **component** means a functional part of the toolkit, not just a PowerShell module.

For the overall runtime flow, repository layout, and operational data boundaries, see [Architecture](./Architecture.md). For terminology used throughout the documentation, see [Glossary](./Glossary.md). This catalog describes responsibilities and dependencies; command parameters, configuration formats, and usage instructions remain in the linked tool guides.

## Runtime tools

The following tools are located directly under `Tools/`.

### Backup execution and coordination

| Component | Implementation and launcher | Responsibility and dependencies | Guide |
| --- | --- | --- | --- |
| `BT-Backup` | [BT-Backup.ps1](../Tools/BT-Backup.ps1), [BT-Backup.cmd](../Tools/BT-Backup.cmd) | Creates and updates a backup of the selected source, preserving previous versions of changed or removed files in timestamped archives. Runs according to a `.BT-Backup` TOML configuration, validates configuration and storage, invokes `rclone sync`, and produces logs and optional email reports. Uses `BT.Common`, `PSToml`, rclone, optional `.BT-Filter` rules, and configured credentials. Can run directly or under `BT-Plan`. | [BT-Backup](./BT-Backup.md) |
| `BT-Plan` | [BT-Plan.ps1](../Tools/BT-Plan.ps1), [BT-Plan.cmd](../Tools/BT-Plan.cmd) | Coordinates multiple backup jobs and provides a consolidated view of their results. Reads a `.BT-Plan` TOML configuration, selects jobs by schedule or command-line override, launches `BT-Backup`, and aggregates results into a plan log and optional consolidated email report. Uses `BT.Common` and `PSToml`; delegates backup execution to `BT-Backup`. Does not register Windows scheduled tasks. | [BT-Plan](./BT-Plan.md) |

### Configuration and credentials

| Component | Implementation and launcher | Responsibility and dependencies | Guide |
| --- | --- | --- | --- |
| `BT-File-Credentials` | [BT-File-Credentials.ps1](../Tools/BT-File-Credentials.ps1), [BT-File-Credentials.cmd](../Tools/BT-File-Credentials.cmd) | Creates and manages `.BT-File-Credentials` files containing a protected password, including the password for an encrypted rclone configuration. Uses `BT.Common` and Windows DPAPI. The credentials are read by `BT-Backup` or retrieved through `BT-File-Get-Password`. | [BT-File-Credentials](./BT-File-Credentials.md) |
| `BT-Mail-Credentials` | [BT-Mail-Credentials.ps1](../Tools/BT-Mail-Credentials.ps1), [BT-Mail-Credentials.cmd](../Tools/BT-Mail-Credentials.cmd) | Creates and manages `.BT-Mail-Credentials` files containing SMTP settings and a protected password. Uses `BT.Common` and Windows DPAPI. These files supply mail settings to `BT-Backup`, `BT-Plan`, and `BT-Mail-Send`. | [BT-Mail-Credentials](./BT-Mail-Credentials.md) |
| `BT-Rclone-Config` | [BT-Rclone-Config.ps1](../Tools/BT-Rclone-Config.ps1), [BT-Rclone-Config.cmd](../Tools/BT-Rclone-Config.cmd) | Creates, inspects, and edits `.BT-Rclone-Config` files in rclone's configuration format; manages encryption and launches the rclone web GUI. Uses `BT.Common`, rclone, and `BT-File-Get-Password` for passwords stored in companion credentials files. Configuration encryption is performed by rclone, not by the credential utility. | [BT-Rclone-Config](./BT-Rclone-Config.md) |

DPAPI-protected credentials can only be decrypted under the same Windows user account on the same machine that created them. Scheduled runs must use a compatible account and have access to the configured files. Real credentials and local configuration are operational data, not source-code components.

### Supporting tools

| Component | Implementation and launcher | Responsibility and dependencies | Guide |
| --- | --- | --- | --- |
| `BT-File-Get-Password` | [BT-File-Get-Password.ps1](../Tools/BT-File-Get-Password.ps1), [BT-File-Get-Password.cmd](../Tools/BT-File-Get-Password.cmd) | Additional helper utility that retrieves a password from a `.BT-File-Credentials` file for use by another command. Uses `BT.Common` and Windows DPAPI. Called by `BT-Rclone-Config` to unlock encrypted configurations; it is not a credential editor. | [BT-File-Get-Password](./BT-File-Get-Password.md) |
| `BT-Mail-Send` | [BT-Mail-Send.ps1](../Tools/BT-Mail-Send.ps1), [BT-Mail-Send.cmd](../Tools/BT-Mail-Send.cmd) | Additional helper utility that sends a message using SMTP settings and protected credentials from a `.BT-Mail-Credentials` file. Uses `BT.Common`, Windows DPAPI, and an SMTP server. Can run independently and is called by `BT-Shutdown` for notifications. | [BT-Mail-Send](./BT-Mail-Send.md) |

### System tasks

| Component | Implementation and launcher | Responsibility and dependencies | Guide |
| --- | --- | --- | --- |
| `BT-Shutdown` | [BT-Shutdown.cmd](../Tools/BT-Shutdown.cmd) | Shuts down the computer when configured conditions permit it, skipping shutdown when a pre-shutdown check fails. When `flag_path` points to the session lock directory used by `BT-Backup` and `BT-Plan`, checks for their `.lock` files and skips shutdown if any are present. Reads a `.BT-Shutdown.ini` configuration, evaluates the checks, logs the decision, optionally calls `BT-Mail-Send` for a notification, and invokes Windows `shutdown.exe` when shutdown is permitted. Implemented entirely in batch, with no PowerShell counterpart. Scheduling is handled separately by `BT-Shutdown-Schedule`. | [BT-Shutdown](./BT-Shutdown.md) |

## Administrative utilities

Administrative tools are located under `Tools/Admin/`. They configure Windows integration rather than perform backups. Each has a `.cmd` entry point and a PowerShell implementation.

| Component | Implementation and launcher | Responsibility and dependencies | Guide |
| --- | --- | --- | --- |
| `BT-Plan-Schedule` | [BT-Plan-Schedule.ps1](../Tools/Admin/BT-Plan-Schedule.ps1), [BT-Plan-Schedule.cmd](../Tools/Admin/BT-Plan-Schedule.cmd) | Provides an interactive menu for creating, inspecting, starting, enabling, disabling, and removing a daily Windows scheduled task that runs `BT-Plan.ps1`. Uses the Windows `ScheduledTasks` cmdlets; task settings and launch parameters are distinct from job selection inside `.BT-Plan`. | [BT-Plan-Schedule](./BT-Plan-Schedule.md) |
| `BT-Shutdown-Schedule` | [BT-Shutdown-Schedule.ps1](../Tools/Admin/BT-Shutdown-Schedule.ps1), [BT-Shutdown-Schedule.cmd](../Tools/Admin/BT-Shutdown-Schedule.cmd) | Provides an interactive menu for managing a repeating Windows scheduled task that launches `BT-Shutdown.cmd` through `cmd.exe` with an INI configuration. Uses the Windows `ScheduledTasks` cmdlets; the PowerShell script manages the task but does not decide whether to shut down. | [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md) |
| `BT-File-Associations` | [BT-File-Associations.ps1](../Tools/Admin/BT-File-Associations.ps1), [BT-File-Associations.cmd](../Tools/Admin/BT-File-Associations.cmd) | Manages per-user Windows file associations for `.BT-Backup`, `.BT-Plan`, `.BT-Mail-Credentials`, `.BT-File-Credentials`, and `.BT-Rclone-Config`. Registers toolkit handlers linked to the corresponding `.cmd` launchers using the Windows registry. It is an installation/integration utility, not a configuration parser. | [Installation](./Installation.md) |

Scheduling and file association changes have their own permission and confirmation requirements. Review the relevant guide before changing Windows integration or starting a task.

## PowerShell modules

Modules are located under `Tools/Modules/`. They are imported by scripts rather than used as standalone toolkit commands.

### Internal modules

| Module | Location | Responsibility and consumers | Reference |
| --- | --- | --- | --- |
| `BT.Common` | [Tools/Modules/BT.Common/](../Tools/Modules/BT.Common/) | Toolkit-owned shared services: logging and mail-body accumulation, dialogs, timestamps, session locks, temporary directories, formatting, and controlled exit behavior. Used by `BT-Backup`, `BT-Plan`, `BT-File-Credentials`, `BT-File-Get-Password`, `BT-Mail-Credentials`, `BT-Mail-Send`, and `BT-Rclone-Config`. Exports shared state and helper functions; does not implement backup, credential, or SMTP workflows. | [BT.Common](./BT.Common.md) |

### External PowerShell modules

| Module | Location | Responsibility and consumers | Reference |
| --- | --- | --- | --- |
| `PSToml` | [Tools/Modules/PSToml/](../Tools/Modules/PSToml/) | Third-party TOML parser and writer, bundled with and tested against Backup-Toolkit at version v0.5.0. Newer versions may also be installed when needed; see [Installation](./Installation.md). `BT-Backup` and `BT-Plan` use it to parse their configuration files; it does not execute jobs or validate toolkit-specific configuration semantics. | [Bundled PSToml information](../Tools/Modules/PSToml.md), [upstream project](https://github.com/jborean93/PSToml) |

## External utilities

| Utility | Location | Responsibility and consumers | Reference |
| --- | --- | --- | --- |
| `rclone` | [Tools/Utilities/Rclone/](../Tools/Utilities/Rclone/) | External file-transfer engine and remote configuration utility. `BT-Backup` uses it for synchronization, remote storage checks, and archive statistics; `BT-Rclone-Config` uses it for configuration management, encryption, and the web GUI. `BT-Backup` can also use a custom executable configured through `[rclone].rclone_prog`. The rclone executable is not bundled with Backup-Toolkit and must be downloaded and installed separately; see [Installation](./Installation.md). `Tools/Utilities/Rclone/` is its default installation location. | [Rclone information](../Tools/Utilities/Rclone.md), [official documentation](https://rclone.org/docs/) |

## Shell launchers and examples

- [Start-BackupToolkitShell.cmd](../Start-BackupToolkitShell.cmd) opens a command shell with **BackupToolkitHome** as its current working directory. It adds the `Tools/` directory and the standard rclone directory in Backup-Toolkit (`Tools/Utilities/Rclone/`) to that shell's `PATH`. It is a convenience entry point, not a backup engine or installer.
- The `.cmd` launchers listed above start their corresponding PowerShell scripts and provide command-shell entry points and, where applicable, default parameters. `BT-Shutdown.cmd` is the exception: it contains the implementation itself.
- [Examples/](../Examples/README.md) contains runnable calls, sample configurations, and a sample backup repository. These demonstrate how to compose the components; they are not additional runtime modules.
- [Tests/](../Tests/README.md) is a local validation workspace, not a shipped test engine or a tracked automated test suite.

## Component collaboration

1. **Prepare configuration:** `BT-Rclone-Config` manages remote definitions; `BT-File-Credentials` stores passwords for encrypted `.BT-Rclone-Config` files; `BT-Mail-Credentials` stores SMTP settings and passwords.
2. **Run backups:** `BT-Plan` selects jobs and invokes `BT-Backup`, or the operator runs `BT-Backup` directly. Both parse TOML through `PSToml` and use `BT.Common` for shared session services. Only `BT-Backup` performs the rclone backup work.
3. **Report results:** When run by `BT-Plan`, `BT-Backup` returns status and control records that the plan uses to aggregate job results. `BT-Backup` can send an individual backup report, while `BT-Plan` can send a consolidated plan report. Email reporting must be enabled in the respective configuration and requires `.BT-Mail-Credentials`.
4. **Shut down the system (optional):** `BT-Shutdown` reads its `.BT-Shutdown.ini` configuration and evaluates pre-shutdown checks. When the checks permit shutdown, it optionally calls `BT-Mail-Send` to send a notification and invokes Windows `shutdown.exe`.
5. **Automate execution:** `BT-Plan-Schedule` registers a Windows task for plan execution. `BT-Shutdown-Schedule` separately registers periodic shutdown checks; `BT-Shutdown` evaluates its INI settings on each invocation.
6. **Integrate with Windows:** `BT-File-Associations` connects supported file extensions to command launchers. The shell launcher makes commands easier to invoke without changing the component responsibilities.

## Related Documentation

- [Architecture](./Architecture.md)
- [Glossary](./Glossary.md)
- [Installation](./Installation.md)
- [Documentation index](./README.md)
