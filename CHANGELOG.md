# Changelog

Notable user-facing changes for each release. Unreleased entries summarize changes since the latest tag. Past entries are reconstructed from the repository's Git tags and commit history; GitHub release notes were not available.

## Unreleased

- No unreleased changes.

## v26.11.01.2

- **Documentation:** Updated the README's release and repository links to point to the public `Backup-Toolkit` repository.
- **Website:** Added a Primer stylesheet override to hide the default open-source footer.

## v26.11.01.1

- **Documentation:** Prepared the main README for publication on the [public Backup-Toolkit project site](https://maciej-smigielski.github.io/Backup-Toolkit/).

## v26.11.01.0

- **Feature:** Added shutdown event inspection to BT.Common, including detection of a pending system shutdown.
- **Feature:** Added coordinator lock helpers to BT.Common (`Open-CoordinatorLockFile` / `Close-CoordinatorLockFile`).
- **Feature:** `BT-Backup` and `BT-Plan` now check for a pending or ongoing system shutdown and use a coordinator lock during startup.
- **Feature:** `BT-Backup` and `BT-Plan` now reject configuration filenames beginning with `.`.
- **Feature:** Write-Log now prefixes debug messages with [Debug] in console output and message dialogs, and after the timestamp in log files.
- **Refactor:** Renamed BT.Common session helpers: `CreateSessionLockFile` → `Open-SessionLockFile`, `RemoveSessionLockFile` → `Close-SessionLockFile`, `CreateSessionTemporaryDir` → `Initialize-SessionTemporaryDirectory`, `RemoveSessionTemporaryDir` → `Remove-SessionTemporaryDirectory`.
- **Refactor:** BT.Common exit codes are now `801`–`808`.
- **Documentation:** Added a "Support and responsibilities" section to the README.
- **Documentation:** Updated all relevant documentation for the changes above.

## v26.10.28.0

- Initial public release of Backup Toolkit.
