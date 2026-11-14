"""The CLI end to end, with a fake Photos library, a fake drive and a fake osxphotos process."""

import json
import os
import signal
import sys
import threading
import time
from pathlib import Path

import pytest

from photos_backup import cli
from photos_backup.safeguards import FilesDisappearedError
from tests.conftest import FakePhotosDB, create_exported_file, photo_taken, write_export_database

FAKE_OSXPHOTOS = Path(__file__).with_name("fake_osxphotos.py")


@pytest.fixture
def fake_osxphotos(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Routes the CLI's osxphotos calls to fake_osxphotos.py; returns a function that sets the scenario."""
    arguments_file = tmp_path / "osxphotos-arguments.json"
    monkeypatch.setattr(cli, "OSXPHOTOS_INVOCATION", [sys.executable, str(FAKE_OSXPHOTOS)])
    monkeypatch.setenv("FAKE_OSXPHOTOS_ARGUMENTS_FILE", str(arguments_file))

    class FakeOsxphotos:
        def use_scenario(self, scenario: str) -> None:
            monkeypatch.setenv("FAKE_OSXPHOTOS_SCENARIO", scenario)

        @property
        def was_run(self) -> bool:
            return arguments_file.exists()

        @property
        def arguments(self) -> list[str]:
            return json.loads(arguments_file.read_text())

    return FakeOsxphotos()


def run_cli(*arguments: str) -> int:
    return cli.main(list(arguments))


def export_one_day(library: Path, target: Path, *extra: str) -> int:
    return run_cli("--library", str(library), "export", "--from", "2026-02-14", "--to", "2026-02-14", str(target), *extra)


def only_log_file(target: Path) -> str:
    [log_file] = (target / "photos-backup-logs").glob("*.log")
    return log_file.read_text()


class TestExport:
    def test_successful_export_logs_every_step(self, fake_library, backup_target, fake_osxphotos):
        FakePhotosDB.photos_in_library = [photo_taken("uuid-1", 2026, 2, 14, original_filesize=2_000_000)]
        fake_osxphotos.use_scenario("export")

        assert export_one_day(fake_library, backup_target) == 0

        log = only_log_file(backup_target)
        assert "Only in iCloud:   1 (0.00 GB to download)" in log
        assert "Files already on the drive: 0" in log
        assert "Running: " in log and "--download-missing" in log
        assert "osxphotos | Exported new file" in log
        assert "osxphotos finished with exit code 0" in log
        assert "(2 new, 0 changed, 0 gone)" in log
        assert "new:     2026/02/14/IMG_0001.HEIC" in log
        assert "Free on this Mac after:" in log
        assert "Check passed" in log

    def test_export_creates_the_folder_layout_on_the_drive(self, fake_library, backup_target, fake_osxphotos):
        fake_osxphotos.use_scenario("export")

        export_one_day(fake_library, backup_target)

        assert (backup_target / "Photos Library" / "2026" / "02" / "14" / "IMG_0001.HEIC").is_file()
        assert (backup_target / "photos-backup-staging").is_dir()
        assert (backup_target / "photos-backup-logs").is_dir()

    def test_osxphotos_receives_the_range_and_drive_paths(self, fake_library, backup_target, fake_osxphotos):
        fake_osxphotos.use_scenario("nothing")

        export_one_day(fake_library, backup_target)

        arguments = fake_osxphotos.arguments
        assert arguments[:2] == ["export", str(backup_target / "Photos Library")]
        assert arguments[arguments.index("--from-date") + 1] == "2026-02-14"
        assert arguments[arguments.index("--to-date") + 1] == "2026-02-15"
        assert arguments[arguments.index("--library") + 1] == str(fake_library)
        assert "--dry-run" not in arguments

    def test_dry_run_is_passed_through_and_named_in_the_log(self, fake_library, backup_target, fake_osxphotos):
        fake_osxphotos.use_scenario("nothing")

        export_one_day(fake_library, backup_target, "--dry-run")

        assert "--dry-run" in fake_osxphotos.arguments
        [log_file] = (backup_target / "photos-backup-logs").glob("*.log")
        assert log_file.name.startswith("dry-run_2026-02-14_to_2026-02-14_")

    def test_rerun_with_nothing_new_reports_no_changes(self, fake_library, backup_target, fake_osxphotos):
        create_exported_file(backup_target / "Photos Library", "2026/02/14/IMG_0001.HEIC")
        fake_osxphotos.use_scenario("nothing")

        export_one_day(fake_library, backup_target)

        log = only_log_file(backup_target)
        assert "Files already on the drive: 1" in log
        assert "(0 new, 0 changed, 0 gone)" in log

    def test_osxphotos_failure_is_logged_and_returned(self, fake_library, backup_target, fake_osxphotos):
        fake_osxphotos.use_scenario("fail")

        assert export_one_day(fake_library, backup_target) == 3

        log = only_log_file(backup_target)
        assert "osxphotos | Error: could not get authorization" in log
        assert "osxphotos finished with exit code 3" in log


class TestNothingGetsLostSilently:
    def test_a_file_disappearing_during_export_stops_with_an_error(self, fake_library, backup_target, fake_osxphotos):
        create_exported_file(backup_target / "Photos Library", "2026/02/14/precious.HEIC")
        fake_osxphotos.use_scenario("delete-existing")

        with pytest.raises(FilesDisappearedError, match="2026/02/14/precious.HEIC"):
            export_one_day(fake_library, backup_target)

        assert "ERROR     GONE:    2026/02/14/precious.HEIC" in only_log_file(backup_target)

    def test_an_overwritten_file_is_logged_as_a_warning(self, fake_library, backup_target, fake_osxphotos):
        create_exported_file(backup_target / "Photos Library", "2026/02/14/edited.HEIC", b"old")
        fake_osxphotos.use_scenario("modify-existing")

        assert export_one_day(fake_library, backup_target) == 0

        assert "WARNING   changed: 2026/02/14/edited.HEIC" in only_log_file(backup_target)

    def test_finder_and_export_database_churn_is_not_reported(self, fake_library, backup_target, fake_osxphotos):
        create_exported_file(backup_target / "Photos Library", ".DS_Store")
        create_exported_file(backup_target / "Photos Library", ".osxphotos_export.db", b"old database")
        fake_osxphotos.use_scenario("export")

        export_one_day(fake_library, backup_target)

        log = only_log_file(backup_target)
        assert "changed:" not in log
        assert ".osxphotos_export.db" not in log.split("Files on the drive now")[1]


class TestRefusesBeforeTouchingAnything:
    def test_target_on_internal_disk_is_refused(self, fake_library, fake_volumes_root, tmp_path, fake_osxphotos):
        fake_osxphotos.use_scenario("export")
        internal_folder = tmp_path / "Desktop" / "Photos"

        with pytest.raises(SystemExit, match="must be on an external drive"):
            export_one_day(fake_library, internal_folder)

        assert not fake_osxphotos.was_run
        assert not internal_folder.exists()

    def test_range_too_big_for_this_mac_is_refused(self, fake_library, backup_target, fake_osxphotos):
        FakePhotosDB.photos_in_library = [photo_taken("huge-video", 2026, 2, 14, original_filesize=10**15)]
        fake_osxphotos.use_scenario("export")

        with pytest.raises(SystemExit, match="Pick a shorter date range"):
            export_one_day(fake_library, backup_target)

        assert not fake_osxphotos.was_run
        assert not (backup_target / "Photos Library" / "2026").exists()

    def test_reversed_date_range_is_refused(self, fake_library, backup_target, fake_osxphotos):
        with pytest.raises(SystemExit, match="before --from"):
            run_cli("--library", str(fake_library), "export", "--from", "2026-02-15", "--to", "2026-02-14", str(backup_target))

        assert not fake_osxphotos.was_run

    def test_malformed_date_is_refused(self, fake_library, backup_target, capsys):
        with pytest.raises(SystemExit):
            run_cli("--library", str(fake_library), "export", "--from", "14.02.2026", "--to", "2026-02-14", str(backup_target))

        assert "invalid fromisoformat value" in capsys.readouterr().err


class TestStatus:
    def test_prints_counts_and_writes_nothing(self, fake_library, tmp_path, capsys):
        FakePhotosDB.photos_in_library = [
            photo_taken("a", 2026, 2, 14, original_filesize=1_500_000_000),
            photo_taken("b", 2026, 2, 14, ismissing=False),
        ]
        files_before = sorted(tmp_path.rglob("*"))

        assert run_cli("--library", str(fake_library), "status", "--from", "2026-02-14", "--to", "2026-02-14") == 0

        output = capsys.readouterr().out
        assert "Photos & videos:  2" in output
        assert "Only in iCloud:   1 (1.50 GB to download)" in output
        assert sorted(tmp_path.rglob("*")) == files_before


class TestProgress:
    def test_prints_per_day_json(self, fake_library, backup_target, capsys):
        FakePhotosDB.photos_in_library = [photo_taken("synced", 2026, 2, 14), photo_taken("missing", 2026, 3, 20)]
        export_folder = backup_target / "Photos Library"
        create_exported_file(export_folder, "2026/02/14/synced.HEIC")
        write_export_database(export_folder, {"2026/02/14/synced.HEIC": "synced"})

        assert run_cli("--library", str(fake_library), "progress", str(backup_target)) == 0

        assert json.loads(capsys.readouterr().out) == {
            "days": [
                {"day": "2026-02-14", "total_items": 1, "synced_items": 1, "hidden_items": 0},
                {"day": "2026-03-20", "total_items": 1, "synced_items": 0, "hidden_items": 0},
            ]
        }

    def test_fresh_drive_shows_everything_missing(self, fake_library, backup_target, capsys):
        FakePhotosDB.photos_in_library = [photo_taken("a", 2026, 2, 14)]

        run_cli("--library", str(fake_library), "progress", str(backup_target))

        assert json.loads(capsys.readouterr().out)["days"] == [{"day": "2026-02-14", "total_items": 1, "synced_items": 0, "hidden_items": 0}]

    def test_disconnected_drive_is_reported(self, fake_library, fake_volumes_root, monkeypatch):
        monkeypatch.setattr(Path, "is_mount", lambda path: False)

        with pytest.raises(SystemExit, match="Drive is not connected"):
            run_cli("--library", str(fake_library), "progress", str(fake_volumes_root / "Gone" / "Photos"))


class TestCancelling:
    def test_sigterm_stops_osxphotos_logs_it_and_still_checks_the_drive(
        self, fake_library, backup_target, fake_osxphotos, tmp_path, monkeypatch
    ):
        pid_file = tmp_path / "osxphotos.pid"
        monkeypatch.setenv("FAKE_OSXPHOTOS_PID_FILE", str(pid_file))
        fake_osxphotos.use_scenario("slow")

        def cancel_once_osxphotos_is_running():
            deadline = time.monotonic() + 20
            while not pid_file.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            os.kill(os.getpid(), signal.SIGTERM)

        threading.Thread(target=cancel_once_osxphotos_is_running, daemon=True).start()
        started = time.monotonic()

        exit_code = export_one_day(fake_library, backup_target)

        assert exit_code == cli.CANCELLED_EXIT_CODE
        assert time.monotonic() - started < 15
        osxphotos_pid = int(pid_file.read_text())
        with pytest.raises(ProcessLookupError):
            os.kill(osxphotos_pid, 0)
        log = only_log_file(backup_target)
        assert "Cancelled: stopping osxphotos" in log
        assert "Check passed" in log
