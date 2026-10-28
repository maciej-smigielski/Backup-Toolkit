# Installation

Backup-Toolkit is a Windows PowerShell toolkit. This guide covers preparing the toolkit folder, installing its local dependencies, and validating an example before running a real backup.

## Requirements

- Windows 10 or later.
- Windows PowerShell 5.1.
- .NET Framework 4.7.2 or later, required by the bundled `PSToml` module.
- Network access to download dependencies and, when applicable, reach configured remote storage.
- A Windows account with read/write access to the toolkit folder and the backup source/destination.

Administrator rights are not normally required to install or run the toolkit from a folder writable by the current user. They are required when using `BT-Plan-Schedule` to create or delete a Windows scheduled task; checking its status, running, enabling, or disabling it does not require elevation. See [BT-Plan-Schedule](BT-Plan-Schedule.md).

## Installation steps

| Step | Task | Details |
| --- | --- | --- |
| 1 | Create a stable, writable folder | Create a folder for the toolkit, for example `%USERPROFILE%\BackupToolkit`. |
| 2 | Download and extract the Backup-Toolkit release archive | Download the expected Backup-Toolkit release archive, for example `Backup-Toolkit-<release-number>.tar.gz`, and extract its contents into the folder created in step 1. This archive contains the Backup-Toolkit files and directories, including `Docs/`, `Examples/`, `Tools/`, and the top-level toolkit scripts. Keep the repository layout unchanged: scripts resolve relative paths to `Tools/` and other local assets. |
| 3 | Install rclone | Download the Windows release for your processor from the [official rclone downloads page](https://rclone.org/downloads/), extract the archive, and copy the extracted rclone directory contents into `%USERPROFILE%\BackupToolkit\Tools\Utilities\Rclone`. The resulting file `Tools/Utilities/Rclone/rclone.exe` must exist. This is the default location used by `BT-Backup`. If you keep rclone elsewhere, set `[rclone].rclone_prog` in each `.BT-Backup` configuration to the executable's path. |
| 4 | Upgrade PSToml (optional) | Backup-Toolkit is bundled with and tested against `PSToml` v0.5.0. If you want to use the bundled version, ensure the module is available in `Tools\Modules\PSToml\`. If you want to install a newer version instead, this is an optional step. For a manual install, download the NuGet package from https://github.com/jborean93/PSToml, rename `*.nupkg` to `*.zip`, extract it, and copy the extracted contents into `%USERPROFILE%\BackupToolkit\Tools\Modules\PSToml\`. The resulting file `Tools/Modules/PSToml/PSToml.psd1` must exist. |

### Preserve local data

> **Warning:** `Config/` is typically located under `BackupRepository/`, but it may also be located directly under `BackupToolkitHome/` (see [Config](Glossary.md)). A local `Tests/` directory may also be present under `BackupToolkitHome/`. Before replacing a folder that contains either directory—including when extracting a release into `BackupToolkitHome`—back up and preserve any existing `Config/` and `Tests/` directories. They may contain credentials, rclone configuration files, custom administrative scripts, or other sensitive test data; do not delete or replace them with release contents, and restore them after installation if their parent folder was replaced. See the [Tests README](../Tests/README.md) for details about local test data.

A clean checkout does not include the local `rclone.exe` binary or any private rclone/credential configuration. Prepare those locally as described above; do not commit private credentials. The bundled `PSToml` module is included with the toolkit and is installed in `Tools\Modules\PSToml\`.


## Verify the installation

Open Windows PowerShell 5.1 at the toolkit root and check the dependencies:

```powershell
$PSVersionTable.PSVersion
Test-Path '.\Tools\Modules\PSToml\PSToml.psd1'
Test-Path '.\Tools\Utilities\Rclone\rclone.exe'
.\Tools\Utilities\Rclone\rclone.exe version
```

## File associations

To manage Explorer associations for Backup-Toolkit configuration files, run the utility from the toolkit root:

```bat
Tools\Admin\BT-File-Associations.cmd
```

The utility applies to `.BT-Backup`, `.BT-Plan`, `.BT-Mail-Credentials`, `.BT-File-Credentials`, and `.BT-Rclone-Config`. It changes associations for the current Windows user and does not normally require administrator rights.

- `S` shows the current associations.
- `A` registers Backup-Toolkit as an application for these file types. If Windows has a different protected default, select Backup-Toolkit in **Settings > Apps > Default apps**.
- `R` removes the per-user association data after confirmation. This also clears saved default and **Open with** choices for other applications for these extensions.
- `Q` exits the utility.

## Examples included

The installation package includes ready-to-use example configurations and scripts. See the [Examples guide](../Examples/README.md) for local backup examples, public DWD remote examples, and a sample plan. Start with validation and `-DryRun` before running a real backup.

## Related Documentation

- [Setup Guide](./Setup-Guide.md)
- [Architecture](./Architecture.md)
- [Components](./Components.md)
- [BT-Backup](./BT-Backup.md)
- [BT-Plan](./BT-Plan.md)
- [BT-Plan-Schedule](./BT-Plan-Schedule.md)
- [BT-Shutdown](./BT-Shutdown.md)
- [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md)
- [Glossary](./Glossary.md)
