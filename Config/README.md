# Local Configuration

This directory is reserved for configuration files used by this local Backup-Toolkit installation. In deployed setups, `Config/` is typically located under `BackupRepository/`, but it may also be located directly under `BackupToolkitHome/`.

> **Warning:** The contents of `Config/` are intentionally not stored in the Git repository; only this `README.md` is tracked. Configuration files may contain rclone settings, credentials, custom administrative scripts, or other sensitive information. Keep real secrets out of version control and use safe example files from `Examples/` where possible.
