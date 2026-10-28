# Glossary

Short definitions for terms used across the Backup-Toolkit documentation. See the tool references in `Docs/` for details.

## Concepts

- **Backup** — a named unit identified by `backup_name`, comprising the `.BT-Backup` config, `logs/`, and payload (`current/` + `archive/`); also known as a *Backup Set*. Comes in two layout variants: **Colocated** or **Split**. *Also*: one execution of `BT-Backup` against that config.
- **Colocated Backup** — variant where the sole **BackupHome** (`BackupData/<backup_name>/`) holds config, logs, and payload.
- **Split Backup** — variant with two **BackupHome** folders for the same Backup: `BackupData/<backup_name>/` holds only `.BT-Backup` + `logs/`, while `BackupStorage/<backup_name>/` (outside the BackupRepository) holds the payload (`current/` + `archive/`).
- **Plan** — a set of backup jobs identified by `plan_name`, defined in a `.BT-Plan` file and executed by `BT-Plan`. *Also*: one execution of `BT-Plan` against that config.
- **Job** — an entry in `[[jobs]]` of a Plan; references a **Backup** by `backup_name`.
- **RunDays** — Job setting in a Plan (`run_days` field): digit string mapping to weekdays (`1`=Mon … `7`=Sun); the Job runs on days whose digit is present.
- **Session** — one runtime instance of `BT-Backup` or `BT-Plan`; owns one lock file, one log file, one temp folder.
- **PID** — Windows process id of the session;
- **Lock** — a file in `Locks/` marking a running session (`PID`, `COMMAND`, `LOG`); prevents concurrent runs of the same backup / plan.
- **Credentials** — sensitive files containing credentials or other secrets, such as protected passwords and SMTP settings; typically stored in `Config/`.

## Paths

- **BackupToolkitHome** — installation directory of the toolkit (contains `Tools/`, `Docs/`). In scripts, this path is referred to as `BTPath`. Also informally called the *Backup-Toolkit home*. Typical folder name: `BackupToolkit/`.
- **BackupRepository** — deployment folder tree: `BackupData/`, `BackupPlan/`, `BackupSystem/`, `Locks/`, optionally `Config/`, `Temp/` and `Admin/`. Typical folder name: `BackupRepository/` (alternatively, `BTRepository/` or `Backups/`). Multiple BackupRepositories may coexist (e.g. per drive, purpose, or environment);
- **BackupData** — container inside a BackupRepository that groups all **BackupHome** folders of Backups stored in this Repository.
- **BackupStorage** — container analogous to `BackupData/` but used only for **Split Backups**, located outside the **BackupRepository** (e.g. on a separate volume). Typical folder name: `BackupStorage/` (alternatively, `BTStorage/`). Its per-Backup subfolders (each a **BackupHome**) hold only the payload (`current/` + `archive/`), not configs or logs.
- **BackupHome** — a per-Backup subfolder named `<backup_name>/`. Content depends on the Backup variant:
  - **Colocated Backup** — one BackupHome holding config + logs + the payload (`current/` + `archive/`) *(under `BackupData/`)*.
  - **Split Backup** — two BackupHomes: one holding config + logs *(under `BackupData/`)*, the other holding only the payload (`current/` + `archive/`) *(under `BackupStorage/`)*.
- **Current** — the mirror of the source after the last successful run: `current/` inside the BackupHome that holds the payload (Colocated: under `BackupData/`; Split: under `BackupStorage/`).
- **Archive** — folder `archive/` inside the BackupHome that holds the payload (Colocated: under `BackupData/`; Split: under `BackupStorage/`); each run creates a timestamped sub-folder `archive_YYYY-MM-DD_HH-MM-SS_<PID>/` holding files that were changed or removed during that run.
- **BackupPlan** — folder holding `*.BT-Plan` files and a shared `logs/` subfolder.
- **BackupSystem** — folder holding configuration and logs of system-level tasks (e.g. `*.BT-Shutdown.ini` and their `logs/`).
- **Config** — folder holding rclone configuration files (including encrypted `.BT-Rclone-Config` files), **Credentials**, and optionally custom versions of administrative scripts; typically a subfolder of the **BackupRepository**, but may also be a subfolder of **BackupToolkitHome**.

## File types

- **`.BT-Backup`** — TOML config for one backup. Read by [BT-Backup](./BT-Backup.md).
- **`.BT-Filter`** — optional rclone filter file referenced from a `.BT-Backup` when `[source].source_filter = true`. Uses rclone's standard filter-file syntax (`+` include / `-` exclude rules, one per line; see rclone's `--filter-from` documentation).
- **`.BT-Plan`** — TOML config for a plan. Read by [BT-Plan](./BT-Plan.md).
- **`.BT-Rclone-Config`** — encrypted or unencrypted rclone config. Managed by [BT-Rclone-Config](./BT-Rclone-Config.md).
- **`.BT-File-Credentials`** — DPAPI-protected secret (typically the `.BT-Rclone-Config` password). Managed by [BT-File-Credentials](./BT-File-Credentials.md).
- **`.BT-Mail-Credentials`** — DPAPI-protected SMTP settings for [BT-Mail-Send](./BT-Mail-Send.md).
- **`*.BT-Shutdown.ini`** — INI config for [BT-Shutdown](./BT-Shutdown.md).

## Runtime flags

- **NoPause** — skip the final `Press Enter to continue` prompt (used in scheduled runs).
- **DebugMode** — enable verbose logging via `Write-Log`.
- **DryRun** — invoke rclone without writing changes; summary still produced.
- **ValidateOnly** — check configuration and environment, then exit; no lock, no rclone, no mail.

## Foundations

- **Rclone** — third-party command-line program used to sync and transfer files to/from cloud storage providers; the transfer engine invoked by `BT-Backup`. See [rclone.org](https://rclone.org/) and the [rclone GitHub repository](https://github.com/rclone/rclone).
- **PSToml** — PowerShell module used to parse [TOML](https://toml.io/) (Tom's Obvious Minimal Language) configuration files (`.BT-Backup`, `.BT-Plan`). See the [PSToml GitHub repository](https://github.com/jborean93/PSToml).

## Related Documentation

- [Architecture](./Architecture.md)
- [Components](./Components.md)
