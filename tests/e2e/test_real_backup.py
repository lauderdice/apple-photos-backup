"""End-to-end tests against your real Photos library and backup drive.

Opt in with:   PHOTOS_BACKUP_E2E_TARGET="/Volumes/<drive>/<folder>" uv run pytest -m e2e

Read-only tests run anywhere. Tests marked needs_photos_access call osxphotos with PhotoKit, which macOS only
grants to Terminal.app, so they skip themselves elsewhere. Those two may export: a dry run of a day that isn't
backed up yet, and a re-export of a day that already is (which must change nothing).
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from photos_backup.safeguards import fingerprint_files

TARGET_VARIABLE = "PHOTOS_BACKUP_E2E_TARGET"
configured_target = os.environ.get(TARGET_VARIABLE)

pytestmark = [
    pytest.mark.e2e,
    pytest.mark.skipif(not configured_target, reason=f"set {TARGET_VARIABLE} to your backup folder to run these"),
]

requires_terminal_app = pytest.mark.skipif(
    os.environ.get("TERM_PROGRAM") != "Apple_Terminal",
    reason="macOS grants Photos access to Terminal.app only; run this test from Terminal.app",
)


@pytest.fixture(scope="module")
def backup_target() -> Path:
    target = Path(configured_target)
    if not target.is_dir():
        pytest.skip(f"backup folder not found (is the drive connected?): {target}")
    return target


@pytest.fixture(scope="module")
def days(backup_target: Path) -> list[dict]:
    completed = photos_backup("progress", str(backup_target))
    assert completed.returncode == 0, completed.stderr
    return json.loads(completed.stdout)["days"]


def photos_backup(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "photos_backup.cli", *arguments], capture_output=True, text=True, timeout=1800
    )


def export_database_digest(export_folder: Path) -> str:
    database = export_folder / ".osxphotos_export.db"
    return hashlib.sha256(database.read_bytes()).hexdigest() if database.exists() else ""


def newest_log(backup_target: Path) -> str:
    return max((backup_target / "photos-backup-logs").glob("*.log"), key=lambda path: path.stat().st_mtime).read_text()


def test_progress_is_consistent_and_writes_nothing(backup_target: Path):
    export_folder = backup_target / "Photos Library"
    photos_before = fingerprint_files(export_folder)
    database_before = export_database_digest(export_folder)

    completed = photos_backup("progress", str(backup_target))

    assert completed.returncode == 0, completed.stderr
    days = json.loads(completed.stdout)["days"]
    assert days, "the Photos library looks empty"
    assert [day["day"] for day in days] == sorted({day["day"] for day in days})
    assert all(0 <= day["synced_items"] <= day["total_items"] for day in days)
    assert fingerprint_files(export_folder) == photos_before
    assert export_database_digest(export_folder) == database_before


def test_status_reads_a_real_day(days: list[dict]):
    first_day = days[0]["day"]

    completed = photos_backup("status", "--from", first_day, "--to", first_day)

    assert completed.returncode == 0, completed.stderr
    assert "Photos & videos:" in completed.stdout


@requires_terminal_app
@pytest.mark.needs_photos_access
def test_dry_run_of_a_day_not_yet_backed_up_writes_no_photos(backup_target: Path, days: list[dict]):
    small_unsynced_days = [day["day"] for day in days if day["synced_items"] == 0 and 1 <= day["total_items"] <= 5]
    if not small_unsynced_days:
        pytest.skip("every small day is already backed up")
    export_folder = backup_target / "Photos Library"
    photos_before = fingerprint_files(export_folder)

    completed = photos_backup(
        "export", "--from", small_unsynced_days[0], "--to", small_unsynced_days[0], str(backup_target), "--dry-run"
    )

    assert completed.returncode == 0, completed.stdout
    assert fingerprint_files(export_folder) == photos_before
    assert "Exporting" in newest_log(backup_target)


@requires_terminal_app
@pytest.mark.needs_photos_access
def test_exporting_a_backed_up_day_again_changes_nothing(backup_target: Path, days: list[dict]):
    backed_up_days = [day["day"] for day in days if day["synced_items"] == day["total_items"] > 0]
    if not backed_up_days:
        pytest.skip("no day is fully backed up yet")
    export_folder = backup_target / "Photos Library"
    photos_before = fingerprint_files(export_folder)

    completed = photos_backup("export", "--from", backed_up_days[0], "--to", backed_up_days[0], str(backup_target))

    assert completed.returncode == 0, completed.stdout
    assert "(0 new, 0 changed, 0 gone)" in newest_log(backup_target)
    assert fingerprint_files(export_folder) == photos_before
