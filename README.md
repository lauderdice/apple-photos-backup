# Photos Backup Tracker

Back up your whole iCloud Photos library to an external drive, even when most of it isn't on your Mac.

With "Optimize Mac Storage" turned on, most originals exist only in iCloud, and your Mac may not have room to
download them all. Photos Backup Tracker copies the library to an external drive **one date range at a time**.
Each item comes down from iCloud through the Photos app and is written to the drive. Your Mac's library stays
optimized, and Advanced Data Protection can stay on.

It has two parts:

- **Photos Backup Tracker.app**: shows how many photos and videos are on the drive and how many are missing,
  for the whole library and for every year, month and day. It can sync a year, a month or a day with one click.
- **`photos-backup`**: the command-line tool that does the work, built on [osxphotos](https://github.com/RhetTbull/osxphotos).

## What ends up on the drive

```
<your backup folder>/
├── Photos Library/
│   └── 2025/
│       └── 07/
│           └── 04/
│               ├── IMG_0001.HEIC
│               ├── IMG_0001.mov          ← the Live Photo's video
│               └── IMG_0001_edited.jpeg  ← only if edited in Photos
├── photos-backup-logs/      ← one .log per run, plus a CSV report per date range
└── photos-backup-staging/   ← temporary download folder, emptied after each item
```

Bursts are backed up in full: every frame, not just the one Photos shows, and the counts include them.

Originals keep their own date, location and camera metadata, so importing the folder into Photos (or any other
app) restores your timeline. Albums, people names and favourites live only in the Photos database and are not
copied.

## Requirements

- macOS 14 Sonoma or later, with iCloud Photos turned on.
- An external drive, formatted APFS or exFAT, with room for your library.
- The Xcode command-line tools: `xcode-select --install`.
- [uv](https://docs.astral.sh/uv/getting-started/installation/).

## Install

```bash
git clone <this repository>
cd <repository folder>
make install
```

This installs **Photos Backup Tracker** into `/Applications`, and its own copy of the `photos-backup` CLI into
`~/Library/Application Support/Photos Backup Tracker/`. Run `make uninstall` to remove both; that leaves your
drive and your Photos library untouched.

## Use the app

1. Open **Photos Backup Tracker** from Applications or Spotlight.
2. Choose your backup folder: any folder on your external drive. The app remembers it.
3. The window shows **Photos Library — N synced · M missing**. Click through years, then months, then days.
4. Click **Sync** on a year, a month or a day. The live log appears at the bottom, and the counts refresh when it finishes.
   A range too big for your Mac's free space is refused (see Safety); sync it a month at a time instead.

The first time, macOS asks whether the app may access your Photos library and your external drive. Allow both.
macOS remembers your answers until the app is reinstalled.

**Synced** means the item is recorded in the backup's export database *and* its file is still on the drive.
**Missing** means it's in your Photos library but not on the drive.

## Use the command line

From the project folder (`uv run photos-backup …`), or anywhere with the installed copy:

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

macOS only grants Photos access to apps that ask for it. From the command line, exports therefore work in
**Terminal.app**, but not in iTerm2 or in terminals built into other apps. The app has no such limitation.

## Safety

- **Nothing in Photos or iCloud is modified.** The export only reads from Photos. osxphotos options that
  would change the library, delete files or overwrite them are blocklisted, and the CLI refuses to start if
  one appears.
- **Nothing on the drive is deleted.** After every run, the CLI compares the drive with how it was before.
  If any file disappeared, it stops with an error naming the files.
- **Every run is logged** on the drive. The log records the date range, item counts, free space before and
  after, every line osxphotos printed, and every file that is new, changed or gone.
- **The Mac's disk can't fill up.** A range is refused if downloading it would leave less than 20 GB free,
  because Photos keeps each downloaded original until macOS reclaims the space.
- **The target must be on an external drive** (under `/Volumes`), and that drive must be connected.

## Privacy

Everything runs on your Mac. Photos downloads originals from iCloud with your own account. osxphotos's
update check is switched off, and nothing else is sent anywhere.

## Limitations

- Photos keeps a local copy of each original it downloads, until macOS needs the space. For a large library,
  sync in ranges and give macOS time to reclaim space.
- Albums, people names, favourites and other Photos-only metadata aren't exported.
- The app is ad-hoc signed by default, so macOS asks for its permissions again after every reinstall.
  Set `SIGNING_IDENTITY` to a code-signing identity to keep them across rebuilds (see `app/build.sh`).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and tests (`make test`, `make test-e2e`), and
[architecture.md](architecture.md) for how it fits together.

## License

[MIT](LICENSE)
