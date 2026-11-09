# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Sync a whole year from the app.
- App icon, drawn by `app/icon/render-icon.swift` at build time.

### Fixed

- Counts now include every frame of a burst. Photos shows a burst as one photo, but the export writes all of
  its frames, so months with bursts showed fewer items than were exported, and the free-space check
  underestimated downloads.

## [0.1.0]

### Added

- `photos-backup` CLI: `status`, `export` and `progress` for a date range of the Photos library, exporting
  to `Photos Library/YYYY/MM/DD` on an external drive. iCloud-only originals are downloaded through Photos.
- Safety checks: refuses targets outside `/Volumes`, ranges that would fill the Mac's disk, and osxphotos
  options that delete or overwrite. Every run is logged on the drive, and a run fails if a file disappears.
- Photos Backup Tracker, a macOS app showing synced and missing counts per year, month and day, with one-click
  sync of a month or a day.
- `make install` / `make uninstall`, and unit, integration, contract and end-to-end tests.
