# Backup-Toolkit
Backup automation toolkit for hybrid and multi-cloud data protection, powered by rclone and orchestrated with PowerShell, running on Windows.

## Features

- Supports data transfers in any direction: local-to-local, local-to-cloud, cloud-to-local, and cloud-to-cloud
- Declarative backup and plan configuration
- Graphical and interactive tools for credential management and rclone configuration
- Centralized orchestration and scheduling of backup plans
- Archiving of replaced or removed files
- Automated shutdown with configurable safety checks
- Protected credential storage, detailed logging, and email reporting

## Installation

Backup-Toolkit is delivered as a release archive. In short:

- Extract it into a writable folder such as `%USERPROFILE%\BackupToolkit`.
- Provide rclone in `Tools\Utilities\Rclone` (not bundled).
- The bundled `PSToml` module is ready to use out of the box.

To open a command shell at the Backup-Toolkit home directory, run:

```bat
Start-BackupToolkitShell.cmd
```

For the full step-by-step guide, requirements, and verification, see [Installation](Docs/Installation.md).

## Quick start

1. Complete the [installation](Docs/Installation.md).
2. From the Backup-Toolkit home directory, open the examples shell:

	```bat
	Examples\Start-ExamplesShell.cmd
	```

3. Continue with the [Examples guide](Examples/README.md) to explore the sample backup and plan scenarios.
4. Follow the [Setup Guide](Docs/Setup-Guide.md) to set up your own backup, credentials, and a scheduled plan.

## Examples

The [Examples guide](Examples/README.md) covers sample `BT-Backup`, `BT-Plan`, and `BT-Shutdown` configurations, launcher scripts, and a sample repository layout.

Before running the examples, install the required modules and dependencies as described in [Installation](Docs/Installation.md). A normal run performs a real `rclone sync` and can modify or delete files in the configured destination. Start with `-ValidateOnly`, then use `-DryRun` to preview the operation. Treat the sample destinations under `Examples/BTRepository/BackupData/` and `Examples/BTStorage/` as disposable.

The examples include:

- **Backup example 1** copies files between local folders. It needs no internet connection. The sample source is empty by default; add disposable files to `Examples/Source/` to see a transfer preview.
- **Backup example 2** is the Split Backup variant of example 1: backed-up data resides in **BackupStorage** outside **BackupRepository**, while configuration and logs remain in **BackupRepository**.
- **Backup example 3** downloads public weather forecast files from the German Meteorological Service (DWD) over HTTPS and demonstrates source filtering. The source requires no credentials and is updated throughout the day; repeated runs demonstrate how rclone keeps current files and archives replaced or removed versions.
- **Backup example 4** is the Split Backup variant of example 3: the same DWD files are stored in **BackupStorage** outside **BackupRepository**, while configuration and logs remain in **BackupRepository**.
- **Plan example** includes all four backup examples: examples 1 and 3 are scheduled every day, while examples 2 and 4 have no scheduled days and are skipped during normal plan runs.
- **Shutdown example** evaluates shutdown conditions in simulation mode by default. It logs its decision without shutting down the computer; changing `shutdown_allow=1` enables real shutdown behavior.
- **Task Scheduler examples** show how to schedule the sample plan and shutdown.

Sample email reporting is disabled. To enable it, configure `mail_to` and `mail_credentials` in the relevant configuration.

## Documentation

- [Setup Guide](Docs/Setup-Guide.md) — step-by-step setup of a backup, credentials, and a scheduled plan.
- [Architecture](Docs/Architecture.md) — describes the toolkit's components, runtime flow, and repository layout.
- [Components](Docs/Components.md) — detailed catalog of tools, administrative utilities, modules, and their dependencies.
- [Glossary](Docs/Glossary.md) — explains terminology used throughout the documentation.

For a complete documentation overview, see the [Documentation index](Docs/README.md).

## Release History

- [Changelog](CHANGELOG.md)

## Requirements

- Windows PowerShell 5.1

## Built With

- [Rclone GitHub](https://github.com/rclone/rclone) ([Rclone.org](https://rclone.org/)) - command-line program used to sync and transfer files to/from cloud storage providers. Backup Toolkit is tested against Rclone v1.75.1, but this version is not bundled with the toolkit and must be downloaded and installed separately; see [Installation](Docs/Installation.md).
- [PSToml GitHub](https://github.com/jborean93/PSToml) - PowerShell module used to read and write TOML configuration files. Backup Toolkit is bundled with and tested against PSToml v0.5.0. Newer PSToml versions may also be installed when needed; see [Installation](Docs/Installation.md).

## License

Backup-Toolkit is licensed under the [PolyForm Internal Use License 1.0.0](LICENSE).
It permits use and modification for your and your company's internal business
operations, but does not permit distribution. This is a source-available license,
not an open-source license. See [Licensing](LICENSING.md) for scope, restrictions,
and third-party license information.
