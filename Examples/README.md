# Examples

This directory contains sample `BT-Backup`, `BT-Plan`, and `BT-Shutdown` configurations, launcher scripts, and a sample repository layout. Use the examples to explore the toolkit's configuration and command-line options before adapting them to your own environment.

## Before you run

> **Note:** The required Backup-Toolkit modules and dependencies must be installed before running the examples. See [Installation](../Docs/Installation.md) for the required setup steps.

> **Note:** Sample configurations use paths relative to the Backup-Toolkit home directory for convenience. For production deployments, use absolute paths for local filesystem locations (such as local source folders, `backup_data`, and config or credential files) so their resolution does not depend on the current working directory. Paths within a remote, such as `source_path` for a configured cloud source, are relative to that remote and should remain remote-relative.

> **Warning:** A normal run performs a real `rclone sync` and can modify or delete files in the configured destination. Start with `-ValidateOnly`, then use `-DryRun` to inspect the planned operation before running without either option.

- The examples are designed to run from the Backup-Toolkit home directory. The launcher scripts change to that directory automatically; `Start-ExamplesShell.cmd` opens a command shell there.
- The `call-*.cmd` scripts are for manual testing: they display the tool's `ERRORLEVEL` and pause before closing. For normal or scheduled operation, invoke `Tools\BT-Backup.cmd` or `Tools\BT-Plan.cmd` directly with the appropriate configuration; use `-NoPause` for unattended runs.
- Explore the paired backup scenarios below: local files in [example 1](#backup-example-1-back-up-local-files) and [example 2](#backup-example-2-back-up-local-files-with-separate-storage), and remote files in [example 3](#backup-example-3-back-up-files-from-a-remote) and [example 4](#backup-example-4-back-up-remote-files-with-separate-storage). See also the [Backup plan example](#backup-plan-example-schedule-selected-backups) and the [shutdown example](#shutdown-example-simulate-a-conditional-shutdown).
- Email is disabled in the sample configurations. See [Email reports](#email-reports) before enabling it.
- The examples use the preconfigured public DWD remote. See [Sample remote](#sample-remote) for details.
- Treat all sample destinations as disposable. The examples write under `Examples/BTRepository/BackupData/` or `Examples/BTStorage/` and may change their `current/` and `archive/` contents.

## Email reports

Email settings are commented out in the sample `.BT-Backup` and `.BT-Plan` files, so the examples do not send email by default. To enable reports, configure both `mail_to` and `mail_credentials` in the relevant `[mail]` section. The credentials file must be a valid `.BT-Mail-Credentials` file available to the current Windows user.

## Quick start

Open a command shell at the Backup-Toolkit home directory:

```bat
Examples\Start-ExamplesShell.cmd
```

Validate the local-source backup example. This checks the backup configuration and destination without running `rclone sync`:

```bat
Examples\call-backup-example-1.cmd -ValidateOnly
```

Validate the plan structure and its job references. This checks that each job's `backup_data` folder and matching `.BT-Backup` file exist, and that `run_days` has a valid format. It does not read or validate the contents of the backup configurations or check their destinations:

```bat
Examples\call-plan-example.cmd -ValidateOnly
```

Validate each job by invoking `BT-Backup` in validation-only mode. This validates each backup configuration and destination without running `rclone sync`:

```bat
Examples\call-plan-example.cmd -ValidateJobs
```

## Example scenarios

The four backup examples form two pairs, each showing the same source with a different storage layout:

| Source | Colocated Backup | Split Backup |
| --- | --- | --- |
| Local files in `Examples/Source/` | Example 1 | Example 2 |
| Public DWD weather forecasts | Example 3 | Example 4 |

In a **Colocated Backup**, the configuration, logs, and backed-up data (`current/` + `archive/`) share one backup home under `BackupData/`. In a **Split Backup**, the configuration and logs stay under `BackupData/`, while the backed-up data resides in a separate **BackupStorage** outside the repository. Here, `Examples/BTStorage/` serves as BackupStorage; in a deployment, it could be on another volume. See the [Glossary](../Docs/Glossary.md#concepts) for the layout terminology.

### Backup example 1: Back up local files

This is a basic local-to-local copy: it copies files from `Examples/Source/` into its own backup folder and does not connect to the internet. It demonstrates the tool's basic operation without requiring a remote service. The sample source folder is empty by default, so add disposable test files before running it. Previous versions are kept in the example's archive folder.

This is a **Colocated Backup**: its configuration, logs, `current/`, and `archive/` are all stored in `Examples/BTRepository/BackupData/backup-example-1/`.

#### Preview with `-DryRun`

Preview the planned transfer without writing files. This passes `--dry-run` to `rclone`; the source folder is empty by default, so add disposable files to `Examples/Source/` to see the planned transfers:

```bat
Examples\call-backup-example-1.cmd -DryRun
```

Run it with `Examples\call-backup-example-1.cmd`.

### Backup example 2: Back up local files with separate storage

This is the **Split Backup** variant of [example 1](#backup-example-1-back-up-local-files). It backs up the same local source, `Examples/Source/`, but separates the backed-up data from the configuration and logs:

- Configuration, filter, and logs: `Examples/BTRepository/BackupData/backup-example-2/`.
- Backed-up data: `Examples/BTStorage/backup-example-2/current/` and `Examples/BTStorage/backup-example-2/archive/`.

The `[destination].destination_storage` setting points to `Examples\BTStorage`, the BackupStorage root. The toolkit appends the backup name to select this example's data folder. This layout keeps backup configuration and logs in the repository while allowing the data to be stored elsewhere. Examples 1 and 2 have independent destinations; running one does not update the other's backup.

As with example 1, no internet connection is needed. Add disposable files to `Examples/Source/`, then validate and preview the backup:

```bat
Examples\call-backup-example-2.cmd -ValidateOnly
Examples\call-backup-example-2.cmd -DryRun
```

Run it with `Examples\call-backup-example-2.cmd`.

### Backup example 3: Back up files from a remote

This example downloads public weather forecast text files from the German Meteorological Service (DWD) open-data server. It reads `weather/text_forecasts/txt/` from `https://opendata.dwd.de/` and saves the files in this example's separate backup folder. The data is publicly available and does not require credentials. The connection uses rclone's `http` backend with an `https://` URL, so the transfer is protected by TLS.

This is a **Colocated Backup**: its configuration, logs, `current/`, and `archive/` are all stored in `Examples/BTRepository/BackupData/backup-example-3/`.

DWD publishes new forecast data throughout the day, making this a useful source for repeated tests. As files change, rclone puts the latest copies in `current/` and stores replaced or removed destination versions in `archive/`.

This example also demonstrates the `source_filter` parameter: set to `true`, it applies the sibling `.BT-Filter`, which excludes `.gitkeep` and `*.pdf` files.

`destination_de = false` disables rclone's `--delete-excluded` option. This preserves destination files that match the filter, such as a destination-side `.gitkeep`, instead of deleting them during sync.

> **Note:** `destination_de` defaults to `true`.

For production backups that should be a strict mirror of the source, keep this default enabled so `rclone sync` removes destination files excluded by the filter as well.

Preview the download first with `-DryRun`. This lists the planned transfers without writing files:

```bat
Examples\call-backup-example-3.cmd -DryRun
```

Run it to download the files:

```bat
Examples\call-backup-example-3.cmd
```

### Backup example 4: Back up remote files with separate storage

This is the **Split Backup** variant of [example 3](#backup-example-3-back-up-files-from-a-remote). It downloads the same public DWD forecast files over HTTPS and uses the same source filtering and `destination_de = false` behavior. The difference is where the backed-up data is stored:

- Configuration, filter, and logs: `Examples/BTRepository/BackupData/backup-example-4/`.
- Backed-up data: `Examples/BTStorage/backup-example-4/current/` and `Examples/BTStorage/backup-example-4/archive/`.

The `[destination].destination_storage` setting points to `Examples\BTStorage`. The configuration and logs remain in the repository, while current files and archived versions reside in BackupStorage. Examples 3 and 4 have independent destinations, so you can compare the two layouts without either example modifying the other's backup.

Validate the configuration and preview the download before transferring files:

```bat
Examples\call-backup-example-4.cmd -ValidateOnly
Examples\call-backup-example-4.cmd -DryRun
```

Run it with `Examples\call-backup-example-4.cmd`.

### Backup plan example: Schedule selected backups

The sample plan includes all four backup examples, but only the two Colocated Backups are scheduled to run. This demonstrates how a plan can keep alternative jobs available without including them in its regular runs.

| Backup examples | Layout | Scheduled days |
| --- | --- | --- |
| 1 and 3 | Colocated Backup | Every day, inherited from `[job_defaults].run_days = "1234567"`. |
| 2 and 4 | Split Backup | None, explicitly set with `run_days = ""` in each job. |

During a normal plan run, examples 1 and 3 are eligible every day; examples 2 and 4 are skipped because they have no scheduled days. To include a Split variant in regular runs, set its `run_days` to the desired weekdays or remove the override to inherit the daily default. The day settings select jobs when the plan is invoked; they do not launch the plan automatically.

You can validate the plan and all its jobs using the commands in [Quick start](#quick-start). To preview all four backups regardless of their scheduled days, use:

```bat
Examples\call-plan-example.cmd -RunAll -DryRun
```

Run it with `Examples\call-plan-example.cmd`.

### Shutdown example: Simulate a conditional shutdown

This example runs `BT-Shutdown` against `Examples/BTRepository/BackupSystem/BT-Shutdown.example.ini`. The INI defaults to **simulation mode** (`shutdown_allow=0`), so the script evaluates every pre-condition (minimum uptime, allowed hour range, logged users, and flag/lock files under `Examples/BTRepository/Locks/`) and writes the full decision to a log in `Examples/BTRepository/BackupSystem/logs/`, but logs `Skip Shutdown: SIMULATION MODE` instead of invoking `shutdown /s`. Change `shutdown_allow=1` in the INI to arm a real shutdown.

E-mail notification is disabled by default (`mail_to` and `mail_credentials` are empty). The example does not depend on any backup example and is safe to run at any time.

Run it with `Examples\call-shutdown-example.cmd`.

### Task Scheduler examples: Schedule plan and shutdown

These launchers demonstrate how to manage scheduled tasks for the sample plan and shutdown configurations. They are customized examples of the standard [BT-Plan-Schedule.cmd](../Tools/Admin/BT-Plan-Schedule.cmd) and [BT-Shutdown-Schedule.cmd](../Tools/Admin/BT-Shutdown-Schedule.cmd) launchers. They show how to set task options and point each task at an example configuration using paths relative to the Backup-Toolkit home directory. Run the example launcher as Administrator when creating a task.

- [BT-Plan-Schedule-example.cmd](BTRepository/Config/Admin/BT-Plan-Schedule-example.cmd) manages a daily scheduled task for `Examples/BTRepository/BackupPlans/plan-example.BT-Plan`.
- [BT-Shutdown-Schedule-example.cmd](BTRepository/Config/Admin/BT-Shutdown-Schedule-example.cmd) manages a repeating scheduled task for `Examples/BTRepository/BackupSystem/BT-Shutdown.example.ini`.

See [BT-Plan-Schedule](../Docs/BT-Plan-Schedule.md) and [BT-Shutdown-Schedule](../Docs/BT-Shutdown-Schedule.md) for the full task-management instructions.

## Sample remote

The sample `Examples/BTRepository/Config/example-rclone.BT-Rclone-Config` defines the `dwd` remote and points it to the public DWD open-data server at `https://opendata.dwd.de/`. This is the German Meteorological Service's public directory for weather and climate data. The remote uses rclone's `http` backend; because its URL is `https://`, connections use HTTPS (TLS). All four backup examples reference this file through their `[rclone].rclone_config` setting; only examples 3 and 4 use the DWD remote as their source.

This is an unencrypted configuration and contains no username, password, token, or other credentials; none are needed to access the public data. From the Backup-Toolkit home directory, inspect or edit it with `BT-Rclone-Config`:

```bat
Tools\BT-Rclone-Config.cmd Examples\BTRepository\Config\example-rclone.BT-Rclone-Config
```

Do not add private credentials or personal service details to this sample configuration. If you add any sensitive values, protect the file appropriately or use an encrypted configuration.

## Files

| Path | Description |
| --- | --- |
| `Start-ExamplesShell.cmd` | Opens a command shell at the Backup-Toolkit home directory and prints common commands. |
| `call-backup-example-1.cmd`, `call-backup-example-2.cmd`, `call-backup-example-3.cmd`, `call-backup-example-4.cmd` | Launch the four sample backup configurations. |
| `call-plan-example.cmd` | Launches the sample plan configuration. |
| `call-shutdown-example.cmd` | Launches the sample shutdown configuration (simulation mode by default). |
| `BTRepository/Config/Admin/BT-Plan-Schedule-example.cmd` | Example customized launcher for scheduling the sample plan. |
| `BTRepository/Config/Admin/BT-Shutdown-Schedule-example.cmd` | Example customized launcher for scheduling the sample shutdown configuration. |
| `BTRepository/BackupData/` | Configurations, filters, and logs for all four backups; also holds the data for Colocated examples 1 and 3. |
| `BTStorage/` | Separate BackupStorage holding `current/` and `archive/` for Split examples 2 and 4. |
| `BTRepository/BackupPlans/` | Sample plan configuration. |
| `BTRepository/BackupSystem/` | Sample `BT-Shutdown` configuration (`BT-Shutdown.example.ini`) and its log folder. |
| `BTRepository/Config/example-rclone.BT-Rclone-Config` | Shared unencrypted rclone configuration defining the public DWD source used by examples 3 and 4. |
| `Source/` | Local source for Backup examples 1 and 2. Add disposable test files here to try either example. |

## Related Documentation

- [Architecture](../Docs/Architecture.md)
- [Components](../Docs/Components.md)
- [Installation](../Docs/Installation.md)
- [BT-Backup](../Docs/BT-Backup.md)
- [BT-Plan](../Docs/BT-Plan.md)
- [BT-Shutdown](../Docs/BT-Shutdown.md)
- [BT-Mail-Credentials](../Docs/BT-Mail-Credentials.md)
- [BT-File-Credentials](../Docs/BT-File-Credentials.md)
- [BT-Rclone-Config](../Docs/BT-Rclone-Config.md)
- [Glossary](../Docs/Glossary.md)
