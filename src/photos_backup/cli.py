"""photos-backup: export the photos and videos taken in a date range to an external drive.

Items that exist only in iCloud are fetched through Photos (PhotoKit) and written straight to the drive.
"""

import argparse
import json
import logging
import os
import shlex
import shutil
import subprocess
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

from photos_backup.library import DateRange, RangeStatus, read_range_status, system_library_path
from photos_backup.progress import compute_day_progress
from photos_backup.safeguards import (
    compare_drive,
    fingerprint_files,
    require_no_files_disappeared,
    require_only_safe_options,
)

EXTERNAL_VOLUMES_ROOT = Path("/Volumes")
EXPORT_FOLDER_NAME = "Photos Library"
LOGS_FOLDER_NAME = "photos-backup-logs"
DOWNLOAD_STAGING_FOLDER_NAME = "photos-backup-staging"
FOLDER_PER_DAY_TEMPLATE = "{created.year}/{created.mm}/{created.dd}"
MINIMUM_FREE_BYTES_AFTER_DOWNLOAD = 20_000_000_000
GIGABYTE = 1_000_000_000
OSXPHOTOS_INVOCATION = [sys.executable, "-m", "osxphotos"]

log = logging.getLogger("photos-backup")


def start_logging(log_path: Path | None) -> None:
    for previous_handler in list(log.handlers):
        log.removeHandler(previous_handler)
        previous_handler.close()
    log.setLevel(logging.INFO)
    timestamped = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s")
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(timestamped)
    log.addHandler(console_handler)
    if log_path is not None:
        file_handler = logging.FileHandler(log_path, encoding="utf-8")
        file_handler.setFormatter(timestamped)
        log.addHandler(file_handler)


def require_external_target(target: Path) -> Path:
    resolved_target = target.resolve()
    if not resolved_target.is_relative_to(EXTERNAL_VOLUMES_ROOT) or resolved_target == EXTERNAL_VOLUMES_ROOT:
        raise SystemExit(f"Target must be on an external drive under /Volumes: {target}")
    volume_root = EXTERNAL_VOLUMES_ROOT / resolved_target.relative_to(EXTERNAL_VOLUMES_ROOT).parts[0]
    if not volume_root.is_mount():
        raise SystemExit(f"Drive is not connected: {volume_root}")
    return resolved_target


def require_room_to_download(status: RangeStatus) -> None:
    free_bytes_after_download = status.library_volume_free_bytes - status.bytes_to_download
    if free_bytes_after_download < MINIMUM_FREE_BYTES_AFTER_DOWNLOAD:
        raise SystemExit(
            f"This range needs {status.bytes_to_download / GIGABYTE:.1f} GB from iCloud, but only "
            f"{status.library_volume_free_bytes / GIGABYTE:.1f} GB is free on this Mac, and Photos may keep a local "
            "copy until macOS reclaims the space. Pick a shorter date range."
        )


def build_export_command(library_path: Path, date_range: DateRange, target: Path, dry_run: bool) -> list[str]:
    day_after_range = date_range.last_day + timedelta(days=1)
    report_path = target / LOGS_FOLDER_NAME / f"export_{date_range.first_day}_to_{date_range.last_day}.csv"
    command = [
        *OSXPHOTOS_INVOCATION, "export", str(target / EXPORT_FOLDER_NAME),
        "--library", str(library_path),
        "--from-date", date_range.first_day.isoformat(),
        "--to-date", day_after_range.isoformat(),
        "--directory", FOLDER_PER_DAY_TEMPLATE,
        "--download-missing",
        "--use-photokit",
        "--update",
        "--touch-file",
        "--retry", "3",
        "--report", str(report_path),
        "--append",
        "--tmpdir", str(target / DOWNLOAD_STAGING_FOLDER_NAME),
        "--verbose",
        "--no-progress",
    ]
    if dry_run:
        command.append("--dry-run")
    return command


def log_range_status(date_range: DateRange, status: RangeStatus) -> None:
    log.info(f"Library:          {status.library_path}")
    log.info(f"Date range:       {date_range.first_day} to {date_range.last_day} (inclusive)")
    log.info(f"Photos & videos:  {status.item_count}")
    log.info(f"Only in iCloud:   {status.items_only_in_icloud} ({status.bytes_to_download / GIGABYTE:.2f} GB to download)")
    log.info(f"Free on this Mac: {status.library_volume_free_bytes / GIGABYTE:.2f} GB")


def range_status(library_path: Path, date_range: DateRange) -> RangeStatus:
    return read_range_status(library_path, date_range, before_day=date_range.last_day + timedelta(days=1))


def run_osxphotos_logging_every_line(command: list[str]) -> int:
    osxphotos_environment = os.environ | {"OSXPHOTOS_NO_VERSION_CHECK": "1"}
    osxphotos_process = subprocess.Popen(
        command, env=osxphotos_environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    for line in osxphotos_process.stdout:
        log.info(f"osxphotos | {line.rstrip()}")
    return osxphotos_process.wait()


def run_status(library_path: Path, date_range: DateRange) -> int:
    start_logging(log_path=None)
    log_range_status(date_range, range_status(library_path, date_range))
    return 0


def run_progress(library_path: Path, target: Path) -> int:
    target = require_external_target(target)
    day_progress = compute_day_progress(library_path, export_folder=target / EXPORT_FOLDER_NAME)
    print(json.dumps({"days": [day.as_json() for day in day_progress]}))
    return 0


def run_export(library_path: Path, date_range: DateRange, target: Path, dry_run: bool) -> int:
    target = require_external_target(target)
    export_folder = target / EXPORT_FOLDER_NAME
    logs_folder = target / LOGS_FOLDER_NAME
    logs_folder.mkdir(parents=True, exist_ok=True)
    export_folder.mkdir(exist_ok=True)
    (target / DOWNLOAD_STAGING_FOLDER_NAME).mkdir(exist_ok=True)

    run_kind = "dry-run" if dry_run else "export"
    log_path = logs_folder / f"{run_kind}_{date_range.first_day}_to_{date_range.last_day}_{datetime.now():%Y-%m-%d_%H-%M-%S}.log"
    start_logging(log_path)
    log.info(f"Started {run_kind}; this log: {log_path}")

    status = range_status(library_path, date_range)
    log_range_status(date_range, status)
    require_room_to_download(status)

    command = build_export_command(library_path, date_range, target, dry_run)
    require_only_safe_options(command)
    files_before = fingerprint_files(export_folder)
    log.info(f"Files already on the drive: {len(files_before)}")
    log.info(f"Running: {shlex.join(command)}")

    osxphotos_exit_code = run_osxphotos_logging_every_line(command)
    log.info(f"osxphotos finished with exit code {osxphotos_exit_code}")

    files_after = fingerprint_files(export_folder)
    changes = compare_drive(files_before, files_after)
    log.info(
        f"Files on the drive now: {len(files_after)} "
        f"({len(changes.new_files)} new, {len(changes.changed_files)} changed, {len(changes.disappeared_files)} gone)"
    )
    for new_file in changes.new_files:
        log.info(f"  new:     {new_file}")
    for changed_file in changes.changed_files:
        log.warning(f"  changed: {changed_file}")
    for disappeared_file in changes.disappeared_files:
        log.error(f"  GONE:    {disappeared_file}")
    log.info(f"Free on this Mac after: {shutil.disk_usage(library_path).free / GIGABYTE:.2f} GB")

    require_no_files_disappeared(changes)
    log.info("Check passed: no file that was on the drive before this run is missing.")
    return osxphotos_exit_code


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="photos-backup", description=__doc__)
    parser.add_argument("--library", type=Path, help="Photos library to read (default: the System Photo Library)")

    date_range_arguments = argparse.ArgumentParser(add_help=False)
    date_range_arguments.add_argument("--from", dest="first_day", type=date.fromisoformat, required=True, help="first day, YYYY-MM-DD")
    date_range_arguments.add_argument("--to", dest="last_day", type=date.fromisoformat, required=True, help="last day (inclusive), YYYY-MM-DD")

    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", parents=[date_range_arguments], help="count items in the range and how much must be downloaded")
    export_parser = commands.add_parser("export", parents=[date_range_arguments], help="export the range to TARGET/Photos Library/YYYY/MM/DD")
    export_parser.add_argument("target", type=Path, help="folder on the external drive, e.g. /Volumes/Backup")
    export_parser.add_argument("--dry-run", action="store_true", help="show what would be exported without downloading or writing")

    progress_parser = commands.add_parser("progress", help="print synced/total item counts per day as JSON")
    progress_parser.add_argument("target", type=Path, help="folder on the external drive, e.g. /Volumes/Backup")

    return parser.parse_args(arguments)


def main(arguments: list[str] | None = None) -> int:
    parsed = parse_arguments(sys.argv[1:] if arguments is None else arguments)
    library_path = parsed.library or system_library_path()
    if parsed.command == "progress":
        return run_progress(library_path, parsed.target)

    try:
        date_range = DateRange(first_day=parsed.first_day, last_day=parsed.last_day)
    except ValueError as invalid_range:
        raise SystemExit(str(invalid_range))

    match parsed.command:
        case "status":
            return run_status(library_path, date_range)
        case "export":
            return run_export(library_path, date_range, parsed.target, parsed.dry_run)
    raise AssertionError(f"unhandled command {parsed.command}")


if __name__ == "__main__":
    sys.exit(main())
