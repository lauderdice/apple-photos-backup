# Architecture

Photos Backup Tracker copies an iCloud Photos library to an external drive in `Photos Library/YYYY/MM/DD`
folders, one date range at a time. The Mac's own library can stay optimized ("Optimize Mac Storage"), and
Advanced Data Protection can stay on, because every download goes through the Photos app.

## Components

```
Photos Backup Tracker.app (SwiftUI)
   │  runs  Contents/Resources/python/bin/python3 -I -m photos_backup.cli   (Python embedded in the app)
   │        progress TARGET              → JSON per day {day, total_items, synced_items}
   │        export --from --to TARGET    → log lines streamed into the app; Cancel sends SIGTERM
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
    - afterwards logs new, changed and gone files and the Mac's free space, then runs the disappearance check;
    - on SIGTERM (the app's Cancel), `run_osxphotos_logging_every_line()` stops osxphotos (terminate, then kill
      after 30 s) and returns `CANCELLED_EXIT_CODE` (143). The drive check still runs.
  - `progress TARGET`: prints `{"days": [...]}` JSON for the app.

## macOS app: `app/`

A SwiftUI app for macOS 14+, built with SwiftPM. No Xcode project is needed; the command-line tools are enough.

- `ProgressTree.swift`: decodes the JSON and builds the Library → year → month → day tree of `ProgressNode`s
  (synced/total counts, inclusive date ranges, newest first). Years, months and days can be synced; the whole library can't, since it would rarely fit the free-space check.
- `PhotosBackupCommand.swift`
  - `CommandRunning` is the protocol for running the CLI.
  - `ProcessCommandRunner` either collects output (`run`) or streams it line by line through an async
    callback (`stream`, with every line delivered before it returns). Cancelling the calling task terminates
    the process. It sets `PYTHONDONTWRITEBYTECODE=1`, so the embedded runtime never writes into the signed
    bundle, and fails fast with `CommandNotInstalled` when the executable is missing.
  - `BackupConfiguration` points at the embedded Python (`-I -m photos_backup.cli`) and the saved backup
    folder (UserDefaults key `backupTargetPath`). `PHOTOS_BACKUP_TRACKER_CLI` and
    `PHOTOS_BACKUP_TRACKER_TARGET` override both for tests.
- `SyncProgress.swift`
  - `SyncProgress.parse()` reads "current of total · file name" from osxphotos's `Exporting NAME (UUID) (n/N)`
    log lines.
  - `SyncOutcome` describes how a sync ended: finished, failed, cancelled or couldn't start.
  - `BackupDriveInfo` reads the backup drive's name and free space, or nil when it's unplugged.
  - `FriendlyError` turns CLI error output into plain-language titles and advice.
- `BackupStore.swift`: `@Observable` state, created with a `CommandRunning` and an optional backup folder.
  - `chooseBackupTarget()` saves the folder and recounts.
  - `reload()` loads the counts.
  - `sync()` runs one export at a time, streams the log (last 2,000 lines kept) and updates `syncProgress`. It
    returns its `Task` and reloads the counts afterwards.
  - `cancelSync()` cancels that task. `lastSyncOutcome`/`lastSyncTitle` stay until `dismissSyncResult()`.
- `Views.swift`
  - The overview is a card with a progress ring, "N of M backed up", the missing count, the backup drive's
    name and free space (`store.backupDrive`, injectable through the store's `readDriveInfo`), and "Browse by Year".
  - Numbers are formatted with `Text(…, format:)` interpolations, so they follow the SwiftUI `\.locale`. The
    screenshots use that to render in English.
  - `ProgressBar` is a SwiftUI capsule bar, green when complete and accent-coloured otherwise. Unlike AppKit's
    progress indicator, it looks the same whether or not the window is active. List rows align their
    separators to the row's leading edge (`listRowSeparatorLeading`).
  - First launch shows a three-step welcome; errors show `FriendlyError` text with Try Again.
  - Year, month and day screens have a header (ring, counts, Sync for the whole period) and rows with a status
    icon, "N of M backed up", a progress bar, and a Sync button or "Backed up".
  - The bottom panel shows the running sync (progress bar, current file, Cancel) or the last result, with the
    raw log under a collapsed "Details".
- `Info.plist`: bundle ID `io.github.photos-backup-tracker`, the Photos usage description and the icon file name.
- `icon/render-icon.swift`: draws the 1024×1024 icon with Core Graphics. `app/build.sh` renders it, scales it into
  an `.iconset` with `sips`, converts it with `iconutil` and caches the `.icns` until the script changes.

## Build and install

- `Makefile` provides `test`, `test-e2e`, `app`, `dmg`, `install` and `uninstall`.
- `app/build.sh OUTPUT_FOLDER` builds a self-contained `.app` (release):
  - **Embedded runtime:** it copies uv's standalone (relocatable) CPython for `.python-version`, strips its
    test folders and `EXTERNALLY-MANAGED`, and installs the dependencies locked in `uv.lock` plus the project
    (not editable). It precompiles everything and caches the result in `python-runtime-<fingerprint>`, keyed
    on the Python version, `uv.lock`, `pyproject.toml` and the CLI's source. The runtime goes into
    `Contents/Resources/python`.
  - **Icon:** draws it, or reuses the cached `.icns`.
  - **Signing:** signs every Mach-O in the runtime, then the bundle, with `SIGNING_IDENTITY` (ad hoc by
    default). Ad-hoc signatures change with every build, so macOS asks for permissions again after an update;
    a real identity avoids that.
- `scripts/package-dmg.sh [OUTPUT_FOLDER]` builds the app and wraps it, next to an `Applications` link, in a
  compressed `Photos-Backup-Tracker-<version>-<arch>.dmg`. The version comes from `Info.plist`.
- `scripts/install.sh` builds the app and copies it to `/Applications` (`INSTALL_FOLDER` overrides). It also
  removes the separate CLI copy that earlier development builds kept in Application Support.
- `scripts/uninstall.sh` removes the app and its preferences, leaving the drive and the Photos library untouched.
- All build output goes to `~/Library/Caches/photos-backup-tracker` (`SWIFT_SCRATCH_PATH` overrides the Swift
  part), keeping it out of the source tree.
- Releases are GitHub releases with the `.dmg` attached (see CONTRIBUTING.md). The app runs on Apple silicon
  only, because the embedded runtime is arm64.

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
  nothing, delete-existing, modify-existing, fail, or slow (used to test SIGTERM cancelling).
- The contract tests check the installed osxphotos's `export --help`, its template fields and the `ExportDB` schema.
- The end-to-end tests:
  - `test_tracker_app.py` builds the app from the current source into a temp folder and launches it against
    a fake CLI. It also checks that the embedded Python runs the CLI with an empty environment and resolves
    everything inside the bundle;
  - `test_real_backup.py` runs against the real library and the folder in `PHOTOS_BACKUP_E2E_TARGET`, and
    skips without it. Its `needs_photos_access` tests also skip unless `TERM_PROGRAM=Apple_Terminal`.
- The Swift tests inject an actor-based fake `CommandRunning` into `BackupStore`, and test
  `ProcessCommandRunner` with `/bin/sh` scripts.
- `ScreenshotTests.swift` renders the README screenshots in `docs/screenshots`. It runs only when
  `PHOTOS_BACKUP_SCREENSHOTS_FOLDER` is set (`make screenshots`). It uses a demo library (2014–2026), a demo
  "Backup Drive" and a demo runner. Each screen is hosted in an always-active `NSWindow` with the toolbar
  bridged and the locale set to `en_US`, then captured with `cacheDisplay`.
- `app/test.sh` adds the command-line tools' Swift Testing framework and `lib_TestingInterop.dylib` paths when
  they're present; full Xcode finds them on its own.
- CI (`.github/workflows/test.yml`) runs `make test` on a macOS runner.

## Dependencies

- Python ≥ 3.12 (3.14 pinned in `.python-version`), managed with `uv`. osxphotos ≥ 0.77.2, with the exact
  version locked in `uv.lock`.
- Swift 5.10+ toolchain (Xcode or the command-line tools), macOS 14+.
