"""Pretends to be `python -m osxphotos`, so the CLI can be exercised without touching Photos.

The scenario comes from $FAKE_OSXPHOTOS_SCENARIO; the arguments it was called with are written as JSON to
$FAKE_OSXPHOTOS_ARGUMENTS_FILE so tests can inspect them.
"""

import json
import os
import sys
import time
from pathlib import Path


def first_existing_photo(export_folder: Path) -> Path:
    return next(path for path in sorted(export_folder.rglob("*")) if path.is_file() and not path.name.startswith("."))


def main() -> int:
    arguments = sys.argv[1:]
    Path(os.environ["FAKE_OSXPHOTOS_ARGUMENTS_FILE"]).write_text(json.dumps(arguments))
    export_folder = Path(arguments[1])
    scenario = os.environ["FAKE_OSXPHOTOS_SCENARIO"]
    print("osxphotos version: fake")

    if scenario == "export":
        day_folder = export_folder / "2026" / "02" / "14"
        day_folder.mkdir(parents=True, exist_ok=True)
        for name in ["IMG_0001.HEIC", "IMG_0001.mov"]:
            (day_folder / name).write_bytes(b"pixels")
            print(f"Exported new file {day_folder / name}")
        (export_folder / ".osxphotos_export.db").write_bytes(b"rewritten every run")
        print("Processed: 1 photos, exported: 2, error: 0")
        return 0
    if scenario == "nothing":
        print("Processed: 0 photos, exported: 0")
        return 0
    if scenario == "delete-existing":
        first_existing_photo(export_folder).unlink()
        return 0
    if scenario == "modify-existing":
        first_existing_photo(export_folder).write_bytes(b"a re-exported, edited version")
        return 0
    if scenario == "slow":
        print("Exporting IMG_0001.HEIC (1/9)", flush=True)
        Path(os.environ["FAKE_OSXPHOTOS_PID_FILE"]).write_text(str(os.getpid()))
        time.sleep(60)
        return 0
    if scenario == "fail":
        print("Error: could not get authorization to access Photos library", file=sys.stderr)
        return 3
    raise SystemExit(f"unknown scenario {scenario}")


if __name__ == "__main__":
    sys.exit(main())
