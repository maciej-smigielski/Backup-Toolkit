# Setup Guide

This guide walks through a complete Backup-Toolkit setup, from an empty **BackupRepository** to a scheduled, reported backup plan. Each step shows the minimum required to proceed and links to the tool reference for details.

The guide assumes that Backup-Toolkit is already installed and verified; see [Installation](./Installation.md). Terms in **bold** are defined in the [Glossary](./Glossary.md).

---

## Overview

| Step | Task | Tool | Required |
| --- | --- | --- | --- |
| 1 | [Create the BackupRepository](#step-1-create-the-backuprepository) | — | yes |
| 2 | [Configure rclone remotes](#step-2-configure-rclone-remotes) | [BT-Rclone-Config](./BT-Rclone-Config.md) | only for remote sources or destinations |
| 3 | [Protect the rclone configuration](#step-3-protect-the-rclone-configuration) | [BT-File-Credentials](./BT-File-Credentials.md) | recommended for remotes with secrets |
| 4 | [Configure email reports](#step-4-configure-email-reports) | [BT-Mail-Credentials](./BT-Mail-Credentials.md) | optional |
| 5 | [Create a backup](#step-5-create-a-backup) | [BT-Backup](./BT-Backup.md) | yes |
| 6 | [Create a backup plan](#step-6-create-a-backup-plan) | [BT-Plan](./BT-Plan.md) | for scheduled runs |
| 7 | [Schedule the plan](#step-7-schedule-the-plan) | [BT-Plan-Schedule](./BT-Plan-Schedule.md) | for scheduled runs |
| 8 | [Check the results](#step-8-check-the-results) | — | yes |

> **Important:** `.BT-File-Credentials` and `.BT-Mail-Credentials` files are protected with Windows DPAPI and can be decrypted only by the Windows user and computer that created them. Create them while signed in as the account that will run the scheduled plan.

The examples below assume that Backup-Toolkit is installed in `%USERPROFILE%\BackupToolkit` and use `%USERPROFILE%\BTRepository` as the **BackupRepository**.
Before starting the configuration, run `Start-BackupToolkitShell.cmd` from the Backup-Toolkit home directory. It opens a command shell there and adds `Tools` and `Tools\Utilities\Rclone` to `PATH`; run the commands below in that shell. Replace names and paths with your own, and use absolute paths in production configurations.

---

## Step 1: Create the BackupRepository

Create the folder layout described in [Architecture](./Architecture.md#installation-and-operational-data):

```text
%USERPROFILE%\BTRepository\
   BackupData\                   # multiple BackupHomes, one per Backup (created in step 5)
   BackupPlan\                   # backup plans (created in step 6) and their logs
      logs\                      # backup plan execution logs
   Config\                       # rclone configuration and credentials
   Locks\                        # optional central location for session lock files
```

---

## Step 2: Configure rclone remotes

Skip this step if both the source and the destination are local folders.

1. Start the configuration utility:

   ```bat
   Tools\BT-Rclone-Config.cmd
   ```

2. Choose **New** and save the file as `%USERPROFILE%\BTRepository\Config\backup.BT-Rclone-Config`.
3. Choose **c** (Config) to start `rclone config`, then add a remote, for example `my-onedrive`. Follow the rclone prompts for the selected provider. For provider-specific remote configuration details, see the [rclone documentation](https://rclone.org/overview/).
4. Choose **q** to quit.

See [BT-Rclone-Config](./BT-Rclone-Config.md) for menu options and file naming rules.

---

## Step 3: Protect the rclone configuration

Rclone configuration files can contain tokens and passwords. Encrypt the configuration so that it can be used only with the matching credentials file.

1. Create the credentials file:

   ```bat
   Tools\BT-File-Credentials.cmd
   ```

2. Choose **New** and save the file in the same folder as the rclone configuration. Replace the default `NoName` prefix with the configuration's name prefix, so the file name is `backup.<COMPUTERNAME>.<USERNAME>.BT-File-Credentials`. `BT-Rclone-Config` locates the credentials by this name.
3. Click **Set Password**, enter a strong password, and click **Save**.
4. Reopen the rclone configuration and choose **e** (Encrypt):

   ```bat
   Tools\BT-Rclone-Config.cmd -ConfigFile "%USERPROFILE%\BTRepository\Config\backup.BT-Rclone-Config"
   ```

See [BT-File-Credentials](./BT-File-Credentials.md) and [BT-Rclone-Config](./BT-Rclone-Config.md#encrypt-or-decrypt-a-configuration) for details.

---

## Step 4: Configure email reports

Skip this step if email reports are not needed.

1. Start the credentials editor:

   ```bat
   Tools\BT-Mail-Credentials.cmd
   ```

2. Choose **New** and save the file as `%USERPROFILE%\BTRepository\Config\mail.<COMPUTERNAME>.<USERNAME>.BT-Mail-Credentials`.
3. Fill in `From`, `smtpServer`, `Port` and `Use SSL`, then click **Set Password**.
4. Click **Test Mail** and send a test message to verify the settings.
5. Click **Save**.

See [BT-Mail-Credentials](./BT-Mail-Credentials.md) for field descriptions.

---

## Step 5: Create a backup

### Create the BackupHome

Choose a backup name, for example `my-backup`, and create its **BackupHome**. For a **Colocated Backup**, the payload folders live in the same BackupHome:

```text
%USERPROFILE%\BTRepository\BackupData\my-backup\
  my-backup.BT-Backup
  logs\
  current\
  archive\
```

For a **Split Backup**, create `current\` and `archive\` under `<BackupStorage>\my-backup\` instead, and set `[destination].destination_storage` in the configuration.

### Create the configuration file

Build the configuration in stages. The file name must match `backup_name`, and the file must be located in `<backup_data>\<backup_name>\`. Use single quotes for Windows paths.

#### Stage 1: Define the backup

Set the backup name and the root folder that contains its BackupHome:

```toml
[bt-backup]
backup_name = "my-backup"
backup_data = '%USERPROFILE%\BTRepository\BackupData'
```

#### Stage 2: Define the source and destination

Choose a source and a destination layout. These choices are independent.

- **Source**
   - **Local**: Omit `source_system` and set `source_path` to the local folder:

      ```toml
      [source]
      source_path = 'D:\Documents'
      ```

   - **Remote**: Set `source_system` to the remote name configured in rclone:

      ```toml
      [source]
      source_system = "my-onedrive"
      source_path = "Documents"
      ```

   - **Optional filter**: To exclude files, set `[source].source_filter = true` and create `my-backup.BT-Filter` next to the configuration file. See [BT-Backup](./BT-Backup.md#configuration-file) for details.

   - **Optional rename tracking**: Local sources provide hashes, and OneDrive uses QuickXorHash by default. Set `[source].source_renames = true` if the destination supports server-side copy or move and has a hash compatible with the source. The hash strategy is not supported by encrypted destinations. See the [rclone rename-tracking requirements](https://rclone.org/docs/#track-renames) and [BT-Backup](./BT-Backup.md#configuration-file) for details.

- **Destination**
   - **Colocated**: Do not add a `[destination]` section. The destination defaults to the local **BackupHome** under `backup_data`; the `current` and `archive` directories must already exist there.

   - **Split local**: Set `destination_storage` to the local storage root and omit `destination_system`:

      ```toml
      [destination]
      destination_storage = '%USERPROFILE%\BTStorage'
      ```
      The local storage root must contain `<backup_name>\current\` and `<backup_name>\archive\` before running the backup.

   - **Split remote**: Set `destination_system` to the rclone remote name and `destination_storage` to the path on that remote:

      ```toml
      [destination]
      destination_system = "my-onedrive"
      destination_storage = "BTStorage"
      ```
      The remote storage root must contain `<backup_name>\current\` and `<backup_name>\archive\` before running the backup.

#### Stage 3: Add other settings

Append only the optional sections needed. This example points to the encrypted rclone configuration created in steps 2 and 3, enables email reports, and sets a shared lock folder:

```toml
[rclone]
rclone_config = '%USERPROFILE%\BTRepository\Config\backup.BT-Rclone-Config'
rclone_credentials = '%USERPROFILE%\BTRepository\Config\backup.HOST.USER.BT-File-Credentials'

[mail]
mail_to = "admin@example.com"
mail_credentials = '%USERPROFILE%\BTRepository\Config\mail.HOST.USER.BT-Mail-Credentials'
mail_attach_log = true

[runtime]
lock_path = '%USERPROFILE%\BTRepository\Locks'
```

Replace `HOST` and `USER` in the credentials paths with the actual computer name and Windows username used in the credential file names. They must match the computer and user that created the DPAPI-protected files.

The `[rclone]` section can be omitted when using rclone's default configuration. Omit `[mail]` if email reports are not needed; `[runtime]` is optional.

### Validate, preview, and run

> **Warning:** A normal run performs a real `rclone sync` and can modify or delete files in the destination. Always validate and preview first.

```bat
Tools\BT-Backup.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupData\my-backup\my-backup.BT-Backup" -ValidateOnly
Tools\BT-Backup.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupData\my-backup\my-backup.BT-Backup" -DryRun
Tools\BT-Backup.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupData\my-backup\my-backup.BT-Backup"
```

- `-ValidateOnly` checks the configuration, credentials, and destination layout without running `rclone sync`.
- `-DryRun` runs `rclone sync --dry-run` and reports the planned changes without writing data.
- The final command performs the first real backup.

---

## Step 6: Create a backup plan

Create `%USERPROFILE%\BTRepository\BackupPlan\nightly.BT-Plan`:

```toml
[bt-plan]
plan_name = "nightly"

[mail]
mail_to = "admin@example.com"
mail_credentials = '%USERPROFILE%\BTRepository\Config\mail.HOST.USER.BT-Mail-Credentials'
mail_attach_log = true

[runtime]
lock_path = '%USERPROFILE%\BTRepository\Locks'

[job_defaults]
backup_data = '%USERPROFILE%\BTRepository\BackupData'
run_days = "1234567"
skip_mail = true

[[jobs]]
backup_name = "my-backup"
```

The file name must match `plan_name`. `run_days` lists the weekdays on which the job runs (`1` = Monday … `7` = Sunday). `skip_mail = true` prevents each backup job from sending its own e-mail; `BT-Plan` still sends one consolidated report. See [BT-Plan](./BT-Plan.md#configuration-file) for all keys.

Validate and preview the plan:

```bat
Tools\BT-Plan.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupPlan\nightly.BT-Plan" -ValidateOnly
Tools\BT-Plan.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupPlan\nightly.BT-Plan" -ValidateJobs
Tools\BT-Plan.cmd -ConfigFile "%USERPROFILE%\BTRepository\BackupPlan\nightly.BT-Plan" -DryRun
```

- `-ValidateOnly` checks the plan file and that each job's `.BT-Backup` file exists.
- `-ValidateJobs` runs each job in `BT-Backup -ValidateOnly` mode.
- `-DryRun` runs each job in `BT-Backup -DryRun` mode.

---

## Step 7: Schedule the plan

1. Run `Tools\Admin\BT-Plan-Schedule.cmd` **as Administrator**.
2. Press `C` (Create), then `P`, and set `ConfigFilePath` to `%USERPROFILE%\BTRepository\BackupPlan\nightly.BT-Plan`. Adjust `TaskName` and `StartTime` if needed.
3. Press `C` and enter the password of the current Windows user.
4. Press `S` (Status) in the main menu to confirm that the task is registered, or `R` (Run) to start it immediately.

To keep these settings for later sessions, use a customised launcher; see [BT-Plan-Schedule](./BT-Plan-Schedule.md#customised-launcher-optional).

---

## Step 8: Check the results

| Location | Content |
| --- | --- |
| `BackupData\<backup_name>\current\` | Current copy of the source. |
| `BackupData\<backup_name>\archive\` | Files that were changed or removed during a run. |
| `BackupData\<backup_name>\logs\` | `BT-Backup` session logs and rclone logs. |
| `BackupPlan\logs\` | `BT-Plan` session logs. |
| Email report | Status, summary, and optionally attached logs. |

A non-zero exit code indicates a problem; see the exit codes in [BT-Backup](./BT-Backup.md#exit-codes) and [BT-Plan](./BT-Plan.md#exit-codes).

---

## Related Documentation

- [Installation](./Installation.md)
- [Architecture](./Architecture.md)
- [Examples guide](../Examples/README.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan](./BT-Plan.md)
- [BT-Plan-Schedule](./BT-Plan-Schedule.md)
- [BT-Rclone-Config](./BT-Rclone-Config.md)
- [BT-File-Credentials](./BT-File-Credentials.md)
- [BT-Mail-Credentials](./BT-Mail-Credentials.md)
- [Glossary](./Glossary.md)
