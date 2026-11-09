# Contributing

Thanks for helping. Bug reports, fixes and improvements are all welcome.

## Development setup

Requirements: macOS 14 or later, the Xcode command-line tools (`xcode-select --install`), and [uv](https://docs.astral.sh/uv/).

```bash
uv sync          # creates the Python environment with the CLI and the test tools
make test        # Python unit, integration and contract tests, plus the Swift app tests
```

`make test` runs entirely on the current source and never touches your Photos library or any drive. The Python
tests use a fake Photos library, a fake `/Volumes` and a fake osxphotos process. The Swift tests use a fake CLI.

## End-to-end tests

```bash
make test-e2e
PHOTOS_BACKUP_E2E_TARGET="/Volumes/<drive>/<folder>" make test-e2e
```

- Without the variable, only the app test runs. It builds the app from source into a temporary folder and
  launches it against a fake CLI; its window appears for a few seconds.
- With `PHOTOS_BACKUP_E2E_TARGET`, read-only tests also run against your real library and that backup folder.
  They assert that nothing on the drive changes.
- Two tests need Photos access and only run from **Terminal.app**, because macOS grants Photos access to that
  app. One is a dry run of a day that isn't backed up yet. The other re-exports a day that is, and must change nothing.

## Project layout

See [architecture.md](architecture.md) for the modules, the data flow and the test layout.

## Guidelines

- Keep the safety guarantees: an export may only add files, and anything else must be logged. If you need a new
  osxphotos option, check it against the blocklist in `src/photos_backup/safeguards.py`. The contract tests
  check that every option still exists in osxphotos.
- Add or update tests with every change, and keep `architecture.md` in sync when modules or data flows change.
- Use self-descriptive names and fail fast on bad input.
- Build output belongs outside the source tree. The scripts already put Swift builds in `~/Library/Caches/photos-backup-tracker`.
