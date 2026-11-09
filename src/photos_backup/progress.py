"""Per-day comparison between the Photos library and what is already exported to the drive."""

import shutil
import sqlite3
import tempfile
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path

import osxphotos

from photos_backup.library import including_every_burst_frame

EXPORT_DATABASE_NAME = ".osxphotos_export.db"
SQLITE_SIDECAR_SUFFIXES = ("-wal", "-shm")


@dataclass(frozen=True)
class DayProgress:
    day: date
    total_items: int
    synced_items: int

    def as_json(self) -> dict:
        return asdict(self) | {"day": self.day.isoformat()}


def read_synced_uuids(export_folder: Path) -> set[str]:
    """UUIDs recorded in osxphotos' export database whose exported file still exists on the drive.

    The database is read from a temporary copy so a running export is never disturbed.
    """
    export_database = export_folder / EXPORT_DATABASE_NAME
    if not export_database.exists():
        return set()

    with tempfile.TemporaryDirectory(prefix="photos-backup-progress-") as temporary_folder:
        database_copy = Path(temporary_folder) / EXPORT_DATABASE_NAME
        shutil.copy2(export_database, database_copy)
        for suffix in SQLITE_SIDECAR_SUFFIXES:
            sidecar = export_database.with_name(export_database.name + suffix)
            if sidecar.exists():
                shutil.copy2(sidecar, database_copy.with_name(database_copy.name + suffix))

        connection = sqlite3.connect(database_copy)
        try:
            exported_rows = connection.execute("SELECT uuid, filepath FROM export_data").fetchall()
        finally:
            connection.close()

    return {uuid for uuid, relative_path in exported_rows if (export_folder / relative_path).is_file()}


def compute_day_progress(library_path: Path, export_folder: Path) -> list[DayProgress]:
    photos_db = osxphotos.PhotosDB(dbfile=str(library_path))
    synced_uuids = read_synced_uuids(export_folder)

    total_by_day: Counter[date] = Counter()
    synced_by_day: Counter[date] = Counter()
    for photo in including_every_burst_frame(photos_db.photos()):
        photo_day = photo.date.date()
        total_by_day[photo_day] += 1
        if photo.uuid in synced_uuids:
            synced_by_day[photo_day] += 1

    return [
        DayProgress(day=day, total_items=total_by_day[day], synced_items=synced_by_day[day])
        for day in sorted(total_by_day)
    ]
