# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Hidden photos showed up as "missing" forever: Photos never hands them to other apps. They're now counted
  separately ("N hidden photos aren't included"), skipped by the export, and left out of the free-space check.
- "Shared with You" items that were never saved to the library counted as missing, although the export (rightly)
  skips them. Counts now follow exactly what the export writes.

## [0.1.1] - 2026-11-13

### Added

- A step-by-step user guide in the README with screenshots, a routine for keeping the backup up to date, and a
  troubleshooting section.
- `make screenshots` renders the README screenshots from demo data.

### Changed

- Progress bars are green when a period is complete and blue while in progress.
- Numbers follow the language and region settings consistently.

### Fixed

- Row separators were drawn only under the Sync button instead of across the whole row.

## [0.1.0] - 2026-11-13

First public release.

### Added

- **Photos Backup Tracker**, a self-contained macOS app for Apple silicon, distributed as a drag-to-install `.dmg`:
  - an overview with a progress ring, the number of photos and videos backed up and missing, and the backup
    drive's name and free space;
  - year → month → day browsing with status icons, and one-click Sync of a year, a month or a day;
  - a live progress bar while syncing, a Cancel button, and the full log under "Details";
  - a welcome screen that asks for the backup folder, and plain-language error messages;
  - an embedded Python runtime, so nothing else needs installing.
- `photos-backup` command-line tool: `status`, `export` and `progress` for a date range of the Photos library,
  exporting to `Photos Library/YYYY/MM/DD` on an external drive. iCloud-only originals are downloaded through
  Photos, and every frame of a burst is included.
- Safety checks:
  - refuses targets outside `/Volumes`, ranges that would fill the Mac's disk, and osxphotos options that
    delete or overwrite;
  - logs every run on the drive, and fails a run if any file on the drive disappears;
  - Cancel stops osxphotos cleanly.
- `make test`, `make test-e2e`, `make app`, `make dmg`, `make install`, `make uninstall`, and unit, integration,
  contract and end-to-end tests.
