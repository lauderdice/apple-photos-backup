"""Read-only inspection of the Photos library for one date range."""

import shutil
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import osxphotos
from osxphotos import PhotoInfo
from osxphotos.utils import get_system_library_path


@dataclass(frozen=True)
class DateRange:
    first_day: date
    last_day: date

    def __post_init__(self) -> None:
        if self.last_day < self.first_day:
            raise ValueError(f"--to ({self.last_day}) is before --from ({self.first_day})")


@dataclass(frozen=True)
class RangeStatus:
    library_path: Path
    item_count: int
    items_only_in_icloud: int
    bytes_to_download: int
    library_volume_free_bytes: int
    hidden_item_count: int


@dataclass(frozen=True)
class BackupSelection:
    """Which photos a backup covers: exactly what `osxphotos export --not-hidden` writes, plus the hidden ones it skips."""

    photos: list[PhotoInfo]
    # Photos never hands hidden items to other apps (the Hidden album is locked), so they can't be backed up
    # until they're unhidden. They're reported separately rather than as missing.
    hidden_photos: list[PhotoInfo]


def system_library_path() -> Path:
    path = get_system_library_path()
    if path is None:
        raise RuntimeError("No System Photo Library is set; open Photos and choose one first.")
    return Path(path)


def including_every_burst_frame(photos: list[PhotoInfo]) -> list[PhotoInfo]:
    """Adds the burst frames Photos hides behind each burst's key photo.

    PhotosDB.photos() lists a burst as the one frame Photos shows, but osxphotos export writes every frame of
    it, so anything that counts or sizes an export has to include them.
    """
    photos_by_uuid: dict[str, PhotoInfo] = {}
    for photo in photos:
        photos_by_uuid.setdefault(photo.uuid, photo)
        if photo.burst:
            for burst_frame in photo.burst_photos:
                photos_by_uuid.setdefault(burst_frame.uuid, burst_frame)
    return list(photos_by_uuid.values())


def is_written_by_osxphotos_export(photo: PhotoInfo) -> bool:
    """osxphotos export skips "Shared with You" items that were never saved to the library and have no local file."""
    return not photo.syndicated or photo.saved_to_library or photo.path is not None


def select_for_backup(photos: list[PhotoInfo]) -> BackupSelection:
    exportable = [photo for photo in including_every_burst_frame(photos) if is_written_by_osxphotos_export(photo)]
    return BackupSelection(
        photos=[photo for photo in exportable if not photo.hidden],
        hidden_photos=[photo for photo in exportable if photo.hidden],
    )


def read_range_status(library_path: Path, date_range: DateRange, before_day: date) -> RangeStatus:
    if not library_path.is_dir():
        raise FileNotFoundError(f"Photos library not found: {library_path}")

    photos_db = osxphotos.PhotosDB(dbfile=str(library_path))
    selection = select_for_backup(
        photos_db.photos(
            from_date=datetime.combine(date_range.first_day, datetime.min.time()),
            to_date=datetime.combine(before_day, datetime.min.time()),
        )
    )
    photos_only_in_icloud = [photo for photo in selection.photos if photo.ismissing]

    return RangeStatus(
        library_path=library_path,
        item_count=len(selection.photos),
        items_only_in_icloud=len(photos_only_in_icloud),
        bytes_to_download=sum(photo.original_filesize for photo in photos_only_in_icloud),
        library_volume_free_bytes=shutil.disk_usage(library_path).free,
        hidden_item_count=len(selection.hidden_photos),
    )
