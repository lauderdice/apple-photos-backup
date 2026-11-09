"""Guards against osxphotos upgrades silently changing what photos-backup relies on."""

import re
import sqlite3
import subprocess
from datetime import date
from functools import cache
from pathlib import Path

import pytest
from osxphotos.export_db import ExportDB

from photos_backup import cli
from photos_backup.library import DateRange
from photos_backup.safeguards import FORBIDDEN_OSXPHOTOS_OPTIONS


@cache
def osxphotos_export_help() -> str:
    completed = subprocess.run(
        [*cli.OSXPHOTOS_INVOCATION, "export", "--help"],
        capture_output=True,
        text=True,
        check=True,
        env={"OSXPHOTOS_NO_VERSION_CHECK": "1", "PATH": "/usr/bin:/bin"},
    )
    return completed.stdout


def options_used_by_photos_backup() -> list[str]:
    command = cli.build_export_command(
        Path("/Library.photoslibrary"), DateRange(date(2026, 2, 14), date(2026, 2, 14)), Path("/Volumes/D/P"), dry_run=True
    )
    return sorted({argument for argument in command if argument.startswith("--")})


def is_documented_option(option: str) -> bool:
    return re.search(rf"^\s+(-\w, )?{re.escape(option)}\b", osxphotos_export_help(), re.MULTILINE) is not None


@pytest.mark.parametrize("option", options_used_by_photos_backup())
def test_every_option_we_pass_exists(option: str):
    assert is_documented_option(option), f"osxphotos export no longer has {option}"


@pytest.mark.parametrize("option", sorted(FORBIDDEN_OSXPHOTOS_OPTIONS))
def test_every_blocklisted_option_still_exists(option: str):
    """A blocklist entry osxphotos renamed would silently stop protecting us."""
    assert is_documented_option(option), f"{option} was renamed or removed; update FORBIDDEN_OSXPHOTOS_OPTIONS"


def test_folder_template_fields_exist():
    template_help = subprocess.run(
        [*cli.OSXPHOTOS_INVOCATION, "help", "export"],
        capture_output=True,
        text=True,
        env={"OSXPHOTOS_NO_VERSION_CHECK": "1", "PATH": "/usr/bin:/bin"},
    ).stdout
    for field in ["{created.year}", "{created.mm}", "{created.dd}"]:
        assert field in template_help


def test_export_database_stores_uuid_and_relative_file_path(tmp_path: Path):
    export_db = ExportDB(tmp_path / ".osxphotos_export.db", tmp_path)
    export_db.create_file_record(tmp_path / "2026" / "02" / "14" / "IMG_0001.HEIC", "the-uuid")
    export_db.close()

    connection = sqlite3.connect(tmp_path / ".osxphotos_export.db")
    rows = connection.execute("SELECT uuid, filepath FROM export_data").fetchall()
    connection.close()

    assert rows == [("the-uuid", "2026/02/14/IMG_0001.HEIC")]
