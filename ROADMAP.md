# Roadmap

This document outlines the planned direction of **Backup-Toolkit**. It is a living document and reflects current intent, not a commitment. Priorities and timing may change as the project evolves.

For shipped changes, see the [Changelog](CHANGELOG.md). For day-to-day working notes and completed tasks, see [WORKLOG](WORKLOG.md).

## Legend

- **Now** — actively worked on, targeted for the next release.
- **Next** — short-term, planned right after the current milestone.
- **Later** — mid-term, scheduled but not yet designed in detail.
- **Future** — long-term ideas under consideration; may change scope or be dropped.

Status markers used per item:
- `[ ]` planned
- `[~]` in progress
- `[?]` under consideration

---

## Now

---

## Next

- [ ] Reimplement `BT-Shutdown` in PowerShell (currently `.cmd`).

---

## Later

- [ ] Create the specified file when it does not exist for command-line invocations of `BT-Rclone-Config`, `BT-File-Credentials`, and `BT-Mail-Credentials`.
- [ ] Allow launching `BT-File-Credentials` in `BT-Rclone-Config`.
- [ ] Show password ststus (empty, readable) from `BT-File-Credentials` in `BT-Rclone-Config`.
- [ ] Fix Windows Task Scheduler path handling in `BT-Plan-Schedule`, including backslashes and quoting in the generated action arguments.
- [ ] Log the contents of the active filter file in `BT-Backup`.
- [ ] Add configurable retention policies for archive and log files.

---

## Future

- [?] Expose `--max-depth` as a configurable parameter.
- [?] Support a maximum run duration (e.g. `--max-duration 60m`) with a soft cutoff mode (`--cutoff-mode SOFT`).
- [?] Allow a free-form list of additional rclone parameters in the backup configuration.
- [?] Support rclone `crypt` remotes for backup sources and destinations.
- [?] Sending mail when running with `-ValidateOnly` / `-ValidateJobs`.
- [ ] Move shared `BT-Plan-Schedule` functions into a library.
- [ ] Coordinate locking between `BT-Backup` and `BT-Shutdown`, including the case where a backup starts exactly as shutdown begins.
- [ ] Move variable initialization from `BTCommon` script bootstrap into the `BT.Common` library.
- [ ] Move mail handling into the `BT.Common` library.
- [ ] Move credential handling into a shared library.
- [ ] Reuse the credential file-type check consistently across `BT-File-Credentials` and `BT-Mail-Credentials`.
- [?] Separate minimal configuration loading from loading the remaining settings in `BT-Backup` and `BT-Plan`.
- [?] Allow `BT-Plan` to reference separate configuration files for individual `BT-Backup` jobs instead of defining them in the main plan configuration.
- [?] Run BT-Backup with ConfigDir (BackupHome) parameter in place of ConfigFile.
- [?] Add UX to configure BT-Backup and BT-Plan including TOML files content.
- [?] Add a unique backup hash

---

## Contributing

Have a suggestion or want to help move an item forward? Please open an issue describing the use case. Items marked `[?]` are especially open to feedback on scope and priority.
