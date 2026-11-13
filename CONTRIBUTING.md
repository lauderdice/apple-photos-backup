# Contributing

Thanks for helping. Bug reports, fixes and improvements are all welcome.

## Development setup

Requirements: a Mac with Apple silicon, macOS 14 or later, the Xcode command-line tools
(`xcode-select --install`), and [uv](https://docs.astral.sh/uv/).

```bash
uv sync          # creates the Python environment with the CLI and the test tools
make test        # Python unit, integration and contract tests, plus the Swift app tests
make install     # builds the app from the current source and installs it into /Applications
```

| Command | What it does |
|---|---|
| `make test` | All Python and Swift tests against the current source. Never touches your Photos library or any drive. |
| `make test-e2e` | End-to-end tests (see below) |
| `make app` | Builds `Photos Backup Tracker.app` into `~/Library/Caches/photos-backup-tracker/app` |
| `make dmg` | Builds the app and packages the drag-to-install `.dmg` into `~/Library/Caches/photos-backup-tracker/dist` |
| `make screenshots` | Regenerates the README screenshots in `docs/screenshots` from demo data (no real library or drive involved) |
| `make install` / `make uninstall` | Installs the app into `/Applications`, or removes it again |

The app is self-contained. `app/build.sh` embeds uv's standalone CPython, with the `photos-backup` CLI and the
dependencies locked in `uv.lock`, in `Contents/Resources/python`. Build output and caches go to
`~/Library/Caches/photos-backup-tracker`, never into the source tree.

## The command-line tool

The app drives `photos-backup`, which also works on its own:

```bash
# How many items a range has and how much must come down from iCloud (read-only)
uv run photos-backup status --from 2025-07-01 --to 2025-07-31

# What an export would do, without downloading or writing anything
uv run photos-backup export --from 2025-07-01 --to 2025-07-31 "/Volumes/MyDrive/Photos" --dry-run

# Export July 2025 (--to is inclusive; re-running skips what's already there)
uv run photos-backup export --from 2025-07-01 --to 2025-07-31 "/Volumes/MyDrive/Photos"

# Synced/total counts per day as JSON (what the app displays)
uv run photos-backup progress "/Volumes/MyDrive/Photos"
```

macOS grants Photos access per app. From the command line, exports that download from iCloud work in
**Terminal.app**. Terminals inside other apps that don't declare Photos usage get killed by macOS, and PhotoKit
export doesn't work under iTerm2.

### Safety guarantees

- The export only reads from Photos. osxphotos options that delete, overwrite or change the library are
  blocklisted in `src/photos_backup/safeguards.py`, and the CLI refuses any command that contains one.
- After every run the CLI compares the drive with how it was before. New and changed files are logged, and if
  anything disappeared the run fails with the list of files.
- Every run writes a timestamped log to `photos-backup-logs/` on the drive.
- A range is refused if downloading it would leave under 20 GB free on the Mac. Photos keeps downloaded
  originals until macOS reclaims the space, and every frame of a burst counts.
- The target must be on a connected drive under `/Volumes`.
- SIGTERM (the app's Cancel button) stops osxphotos as well. The drive check still runs and the CLI exits
  with code 143.

Keep these guarantees when you change things. If you need a new osxphotos option, check it against the
blocklist; the contract tests check that every option we use or block still exists.

## End-to-end tests

```bash
make test-e2e
PHOTOS_BACKUP_E2E_TARGET="/Volumes/<drive>/<folder>" make test-e2e
```

- **Always:** the app tests build the app from source into a temporary folder. They launch it against a fake
  CLI (its window appears for a few seconds) and check that the embedded Python runs the CLI with nothing else
  installed.
- **With `PHOTOS_BACKUP_E2E_TARGET`:** read-only tests also run against your real library and that backup
  folder, and assert that nothing on the drive changes.
- **From Terminal.app only:** two tests need Photos access. One is a dry run of a day that isn't backed up yet,
  which must report the same item count the app shows. The other re-exports a day that is backed up, which must
  change nothing.

## Releasing

1. Update the version in `app/Info.plist` (`CFBundleShortVersionString`) and `pyproject.toml`, and move the
   `CHANGELOG.md` entries under a new version heading.
2. `make test` (and `make test-e2e` from Terminal.app with your backup folder set).
3. `make dmg`.
4. Create the release with the disk image attached:

```bash
gh release create vX.Y.Z ~/Library/Caches/photos-backup-tracker/dist/Photos-Backup-Tracker-X.Y.Z-arm64.dmg \
    --title "Photos Backup Tracker X.Y.Z" --notes-file <release notes>
```

The app is ad-hoc signed, so users confirm it once under System Settings → Privacy & Security, as the README
explains. With an Apple Developer ID you could pass `SIGNING_IDENTITY` and notarize the `.dmg` to remove
that step.

## Guidelines

- Add or update tests with every change, and keep `architecture.md` in sync when modules or data flows change.
- Use self-descriptive names and fail fast on bad input.
- The README is written for non-technical users. Keep technical detail here and in `architecture.md`. After UI changes, run `make screenshots` and commit the updated images.
