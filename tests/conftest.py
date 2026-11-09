"""Shared fixtures: a fake Photos library, a fake external drive and real osxphotos export databases."""

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import osxphotos
import pytest
from osxphotos.export_db import ExportDB

from photos_backup import cli


@dataclass
class FakePhoto:
    """The subset of osxphotos.PhotoInfo that photos_backup reads."""

    uuid: str
    date: datetime
    ismissing: bool = True
    original_filesize: int = 1_000_000


class FakePhotosDB:
    """Stands in for osxphotos.PhotosDB; filters by date the way PhotosDB.photos() does."""

    photos_in_library: list[FakePhoto] = []

    def __init__(self, dbfile: str | None = None):
        self.dbfile = dbfile

    def photos(self, from_date: datetime | None = None, to_date: datetime | None = None, **_unused) -> list[FakePhoto]:
        def in_range(photo: FakePhoto) -> bool:
            local_date = photo.date.replace(tzinfo=None)
            return (from_date is None or local_date >= from_date) and (to_date is None or local_date < to_date)

        return [photo for photo in self.photos_in_library if in_range(photo)]


def photo_taken(uuid: str, year: int, month: int, day: int, hour: int = 12, **fields) -> FakePhoto:
    return FakePhoto(uuid=uuid, date=datetime(year, month, day, hour, tzinfo=timezone.utc), **fields)


@pytest.fixture
def fake_library(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A Photos library folder whose contents come from FakePhotosDB.photos_in_library."""
    library_path = tmp_path / "Fake Library.photoslibrary"
    library_path.mkdir()
    FakePhotosDB.photos_in_library = []
    monkeypatch.setattr(osxphotos, "PhotosDB", FakePhotosDB)
    return library_path


@pytest.fixture
def fake_volumes_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A stand-in for /Volumes; every folder directly inside it counts as a mounted drive."""
    volumes_root = (tmp_path / "Volumes").resolve()
    volumes_root.mkdir()
    monkeypatch.setattr(cli, "EXTERNAL_VOLUMES_ROOT", volumes_root)

    real_is_mount = Path.is_mount
    monkeypatch.setattr(Path, "is_mount", lambda path: path.parent == volumes_root or real_is_mount(path))
    return volumes_root


@pytest.fixture
def backup_target(fake_volumes_root: Path) -> Path:
    """The backup folder on a connected fake drive, like /Volumes/Backup Drive/Photos."""
    target = fake_volumes_root / "Backup Drive" / "Photos"
    target.mkdir(parents=True)
    return target


def write_export_database(export_folder: Path, exported_files: dict[str, str]) -> Path:
    """Creates a genuine osxphotos export database recording {relative file path: uuid}."""
    export_folder.mkdir(parents=True, exist_ok=True)
    database_path = export_folder / ".osxphotos_export.db"
    export_db = ExportDB(database_path, export_folder)
    for relative_path, uuid in exported_files.items():
        export_db.create_file_record(export_folder / relative_path, uuid)
    export_db.close()
    return database_path


def create_exported_file(export_folder: Path, relative_path: str, content: bytes = b"photo") -> Path:
    file_path = export_folder / relative_path
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_bytes(content)
    return file_path
