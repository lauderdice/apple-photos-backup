# Architecture

Photos Backup Tracker copies an iCloud Photos library to an external drive in `Photos Library/YYYY/MM/DD`
folders, one date range at a time. The Mac's own library can stay optimized ("Optimize Mac Storage"), and
Advanced Data Protection can stay on, because every download goes through the Photos app.

## Components

```
Photos Backup Tracker.app (SwiftUI)
   │  runs  ~/Library/Application Support/Photos Backup Tracker/cli/bin/photos-backup
   │        progress TARGET              → JSON per day {day, total_items, synced_items}
   │        export --from --to TARGET    → log lines streamed into the app
   ▼
photos-backup CLI (Python)  ──reads──►  Photos library database (read-only copy, via osxphotos PhotosDB)
   │  runs  python -m osxphotos export … --download-missing --use-photokit
   ▼
osxphotos ──(PhotoKit / Photos.app)──► iCloud
   │
   ▼
TARGET/photos-backup-staging/        one item at a time, deleted after it's copied
TARGET/Photos Library/YYYY/MM/DD/*   the backup
TARGET/Photos Library/.osxphotos_export.db   osxphotos' record of what was exported
TARGET/photos-backup-logs/<run>_<from>_to_<to>_<timestamp>.log
TARGET/photos-backup-logs/export_<from>_to_<to>.csv   osxphotos report, appended per run
```

- The CLI sizes a range from the Photos database, then runs `osxphotos export` for it. Items missing locally
  are fetched through PhotoKit, staged on the target drive (`--tmpdir`) and copied into place.
- Photos keeps downloaded originals in the local library until macOS reclaims the space, so the CLI refuses
  ranges that would leave less than 20 GB free on the Mac.
- osxphotos's version check against pypi.org is disabled (`OSXPHOTOS_NO_VERSION_CHECK=1`). Apart from
  Photos's own iCloud traffic, nothing leaves the Mac.
- PhotoKit access is granted per app. The app declares `NSPhotoLibraryUsageDescription`, so osxphotos, running
  as its child process, inherits the app's Photos permission. From the command line, Terminal.app works.
  Terminals inside other apps that don't declare Photos usage get killed by macOS (SIGABRT, exit -6), and
  PhotoKit export doesn't work under iTerm2.

## Python package: `src/photos_backup/`

- `library.py`
  - `including_every_burst_frame()` adds the frames hidden behind each burst's key photo. `PhotosDB.photos()` lists
    only the key photo, but osxphotos export writes every frame, so every count and size estimate goes through it.
  - `DateRange` holds an inclusive first/last day and is validated on creation.
  - `RangeStatus` holds item count, iCloud-only count, bytes to download, and free space on the library volume.
  - `read_range_status()` computes it.
- `progress.py`
  - `read_synced_uuids()` copies `.osxphotos_export.db` (and its `-wal`/`-shm`) to a temp folder, so a
    running export is never disturbed. It returns the UUIDs whose exported file still exists on the drive.
  - `compute_day_progress()` counts library items and synced items per day, using each photo's own date.
- `safeguards.py`
  - `FORBIDDEN_OSXPHOTOS_OPTIONS` blocklists options that delete or overwrite on the drive or change the
    library. `require_only_safe_options()` refuses any command containing one.
  - `fingerprint_files()` snapshots the size and mtime of every exported file; `.DS_Store` and
    `.osxphotos_export.db*` are ignored because Finder and osxphotos rewrite them.
  - `compare_drive()` turns two snapshots into new, changed and disappeared lists.
  - `require_no_files_disappeared()` fails the run if anything vanished.
- `cli.py`: the `photos-backup` entry point.
  - `status --from --to`: prints the range status, read-only.
  - `export --from --to TARGET [--dry-run]`:
    - requires a connected drive under `/Volumes` and enough room on the Mac;
    - opens a timestamped log on the drive (console and file);
    - runs `osxphotos export` with `--directory {created.year}/{created.mm}/{created.dd} --download-missing
      --use-photokit --update --touch-file --retry 3 --report --append --tmpdir --verbose --no-progress`,
      logging every output line;
    - afterwards logs new, changed and gone files and the Mac's free space, then runs the disappearance check.
  - `progress TARGET`: prints `{"days": [...]}` JSON for the app.

## macOS app: `app/`

A SwiftUI app for macOS 14+, built with SwiftPM. No Xcode project is needed; the command-line tools are enough.

- `ProgressTree.swift`: decodes the JSON and builds the Library → year → month → day tree of `ProgressNode`s
  (synced/total counts, inclusive date ranges, newest first). Only months and days can be synced.
- `PhotosBackupCommand.swift`
  - `CommandRunning` is the protocol for running the CLI.
  - `ProcessCommandRunner` either collects output (`run`) or streams it line by line through an async
    callback (`stream`, with every line delivered before it returns). It fails fast with `CommandNotInstalled`
    when the CLI is missing.
  - `BackupConfiguration` locates the installed CLI and the saved backup folder (UserDefaults key
    `backupTargetPath`). `PHOTOS_BACKUP_TRACKER_CLI` and `PHOTOS_BACKUP_TRACKER_TARGET` override both for tests.
- `BackupStore.swift`: `@Observable` state, created with a `CommandRunning` and an optional backup folder.
  - `chooseBackupTarget()` saves the folder and recounts.
  - `reload()` loads the counts.
  - `sync()` runs one export at a time, streams the log (last 2,000 lines kept), returns its `Task`, and
    reloads the counts afterwards.
- `Views.swift`: a NavigationStack drill-down with a folder picker shown on first launch and a "Backup Folder…"
  toolbar button. Rows show synced, missing and a progress bar; month and day rows have Sync buttons. The
  bottom panel shows the sync status and live log.
- `Info.plist`: bundle ID `io.github.photos-backup-tracker`, plus the Photos usage description.

## Build and install

- `Makefile` provides `test`, `test-e2e`, `app`, `install` and `uninstall`.
- `app/build.sh OUTPUT_FOLDER` builds the `.app` (release) and signs it with `SIGNING_IDENTITY` (ad hoc by
  default). Ad-hoc signatures change with every build, so macOS asks for permissions again after a rebuild;
  a real identity avoids that.
- `scripts/install.sh` creates the CLI environment in `~/Library/Application Support/Photos Backup Tracker/cli`
  with the Python version from `.python-version`. It installs the dependencies locked in `uv.lock`, then the
  project itself (not editable), builds the app and copies it to `/Applications` (`INSTALL_FOLDER` overrides).
- `scripts/uninstall.sh` removes the app, its CLI environment and its preferences, leaving the drive and the
  Photos library untouched.
- Swift build output goes to `~/Library/Caches/photos-backup-tracker/swift-build` (`SWIFT_SCRATCH_PATH`
  overrides), keeping it out of the source tree.

## Tests

| Suite | Location | Runs on |
|---|---|---|
| Python unit | `tests/unit/` | `make test` |
| Python integration | `tests/integration/` | `make test` |
| osxphotos contract | `tests/contract/` | `make test` |
| Swift unit | `app/Tests/PhotosBackupTrackerTests/` via `app/test.sh` | `make test` |
| End-to-end | `tests/e2e/` (marker `e2e`) | `make test-e2e` |

- `tests/conftest.py` provides the fixtures:
  - `FakePhotosDB` stands in for `osxphotos.PhotosDB`;
  - `fake_volumes_root` replaces `/Volumes` with a temp folder whose children count as mounted drives;
  - `write_export_database()` builds genuine export databases with osxphotos's `ExportDB`.
- The integration tests run `cli.main()` with `cli.OSXPHOTOS_INVOCATION` pointed at
  `tests/integration/fake_osxphotos.py`. The fake's behaviour comes from `$FAKE_OSXPHOTOS_SCENARIO`: export,
  nothing, delete-existing, modify-existing or fail.
- The contract tests check the installed osxphotos's `export --help`, its template fields and the `ExportDB` schema.
- The end-to-end tests:
  - `test_tracker_app.py` builds the app from the current source into a temp folder and launches it against
    a fake CLI;
  - `test_real_backup.py` runs against the real library and the folder in `PHOTOS_BACKUP_E2E_TARGET`, and
    skips without it. Its `needs_photos_access` tests also skip unless `TERM_PROGRAM=Apple_Terminal`.
- The Swift tests inject an actor-based fake `CommandRunning` into `BackupStore`, and test
  `ProcessCommandRunner` with `/bin/sh` scripts.
- `app/test.sh` adds the command-line tools' Swift Testing framework and `lib_TestingInterop.dylib` paths when
  they're present; full Xcode finds them on its own.
- CI (`.github/workflows/test.yml`) runs `make test` on a macOS runner.

## Dependencies

- Python ≥ 3.12 (3.14 pinned in `.python-version`), managed with `uv`. osxphotos ≥ 0.77.2, with the exact
  version locked in `uv.lock`.
- Swift 5.10+ toolchain (Xcode or the command-line tools), macOS 14+.
