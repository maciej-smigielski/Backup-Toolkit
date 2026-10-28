# Backup-Toolkit Documentation

This folder contains the user and reference documentation for Backup-Toolkit, a Windows backup automation toolkit built with PowerShell and rclone.

## Getting started

- [Installation](./Installation.md) — prerequisites, installation steps, and verification.
- [Examples guide](../Examples/README.md) — runnable sample backups, plan, and shutdown to try the toolkit safely.
- [Setup Guide](./Setup-Guide.md) — step-by-step setup from an empty repository to a scheduled backup plan.

## Concepts and architecture

- [Architecture](./Architecture.md) — component responsibilities, runtime flow, and repository layout.
- [Components](./Components.md) — detailed catalog of tools, administrative utilities, modules, and their dependencies.
- [Glossary](./Glossary.md) — terminology used throughout the documentation.

## Backups and plans

- [BT-Backup](./BT-Backup.md) — configure and run an individual backup.
- [BT-Plan](./BT-Plan.md) — define and run a plan containing backup jobs.
- [BT-Plan-Schedule](./BT-Plan-Schedule.md) — schedule plans to run automatically.

## System tasks

- [BT-Shutdown](./BT-Shutdown.md) — configure controlled shutdown behavior.
- [BT-Shutdown-Schedule](./BT-Shutdown-Schedule.md) — schedule shutdown checks.

## Configuration, credentials and email

- [BT-Mail-Credentials](./BT-Mail-Credentials.md) — configure protected SMTP credentials.
- [BT-Mail-Send](./BT-Mail-Send.md) — send email using the toolkit's mail command.
- [BT-File-Credentials](./BT-File-Credentials.md) — create and manage protected file credentials.
- [BT-File-Get-Password](./BT-File-Get-Password.md) — retrieve a password from protected credentials.
- [BT-Rclone-Config](./BT-Rclone-Config.md) — create and manage encrypted rclone configuration files.

Sample email reports: **BT-Backup** — [no changes](./assets/mail-samples/backup-example-no-changes.pdf), [with changes](./assets/mail-samples/backup-example-with-changes.pdf); **BT-Plan** — [no changes](./assets/mail-samples/plan-example-no-changes.pdf), [with changes](./assets/mail-samples/plan-example-with-changes.pdf).

## Modules

- [BT.Common](./BT.Common.md) — reference for shared PowerShell module functionality.

## License

- [Licensing](../LICENSING.md) - license scope, permitted internal use, restrictions, and third-party components.
- [PolyForm Internal Use License 1.0.0](../LICENSE) - full license text.

For the project overview, start with the [main README](../README.md).
