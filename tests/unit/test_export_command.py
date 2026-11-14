from datetime import date
from pathlib import Path

import pytest

from photos_backup import cli
from photos_backup.library import DateRange, RangeStatus
from photos_backup.safeguards import require_only_safe_options

GIGABYTE = 1_000_000_000
TARGET = Path("/Volumes/Drive/Photos")


def option_value(command: list[str], option: str) -> str:
    return command[command.index(option) + 1]


def export_command(first_day: date, last_day: date, dry_run: bool = False) -> list[str]:
    return cli.build_export_command(Path("/Library.photoslibrary"), DateRange(first_day, last_day), TARGET, dry_run)


class TestBuildExportCommand:
    def test_exports_into_photos_library_folder_with_one_folder_per_day(self):
        command = export_command(date(2026, 2, 14), date(2026, 2, 14))

        assert command[: len(cli.OSXPHOTOS_INVOCATION) + 2] == [*cli.OSXPHOTOS_INVOCATION, "export", str(TARGET / "Photos Library")]
        assert option_value(command, "--directory") == "{created.year}/{created.mm}/{created.dd}"
        assert option_value(command, "--library") == "/Library.photoslibrary"

    def test_last_day_is_inclusive(self):
        command = export_command(date(2026, 2, 1), date(2026, 2, 28))

        assert option_value(command, "--from-date") == "2026-02-01"
        assert option_value(command, "--to-date") == "2026-03-01"

    def test_range_ending_on_new_years_eve_stops_on_january_first(self):
        command = export_command(date(2025, 12, 31), date(2025, 12, 31))

        assert option_value(command, "--to-date") == "2026-01-01"

    def test_downloads_from_icloud_through_photokit_incrementally(self):
        command = export_command(date(2026, 2, 14), date(2026, 2, 14))

        for option in ["--download-missing", "--use-photokit", "--not-hidden", "--update", "--touch-file", "--verbose", "--no-progress"]:
            assert option in command

    def test_stages_downloads_and_reports_on_the_backup_drive(self):
        command = export_command(date(2026, 2, 14), date(2026, 2, 15))

        assert option_value(command, "--tmpdir") == str(TARGET / "photos-backup-staging")
        assert option_value(command, "--report") == str(TARGET / "photos-backup-logs" / "export_2026-02-14_to_2026-02-15.csv")
        assert "--append" in command

    def test_dry_run_flag_only_when_asked(self):
        assert "--dry-run" not in export_command(date(2026, 2, 14), date(2026, 2, 14))
        assert "--dry-run" in export_command(date(2026, 2, 14), date(2026, 2, 14), dry_run=True)

    @pytest.mark.parametrize("dry_run", [True, False])
    def test_generated_command_passes_the_safety_check(self, dry_run: bool):
        require_only_safe_options(export_command(date(2026, 2, 14), date(2026, 2, 14), dry_run))


class TestRequireExternalTarget:
    def test_folder_on_connected_drive_is_accepted(self, backup_target: Path):
        assert cli.require_external_target(backup_target) == backup_target

    def test_folder_outside_volumes_is_refused(self, fake_volumes_root: Path, tmp_path: Path):
        with pytest.raises(SystemExit, match="must be on an external drive"):
            cli.require_external_target(tmp_path / "Desktop")

    def test_volumes_root_itself_is_refused(self, fake_volumes_root: Path):
        with pytest.raises(SystemExit, match="must be on an external drive"):
            cli.require_external_target(fake_volumes_root)

    def test_disconnected_drive_is_refused(self, fake_volumes_root: Path, monkeypatch: pytest.MonkeyPatch):
        monkeypatch.setattr(Path, "is_mount", lambda path: False)

        with pytest.raises(SystemExit, match="Drive is not connected"):
            cli.require_external_target(fake_volumes_root / "Unplugged" / "Photos")

    def test_relative_escape_out_of_volumes_is_refused(self, backup_target: Path, fake_volumes_root: Path):
        with pytest.raises(SystemExit, match="must be on an external drive"):
            cli.require_external_target(fake_volumes_root / ".." / "elsewhere")


class TestRequireRoomToDownload:
    @staticmethod
    def status(bytes_to_download: int, free_bytes: int) -> RangeStatus:
        return RangeStatus(
            library_path=Path("/Library.photoslibrary"),
            item_count=1,
            items_only_in_icloud=1,
            bytes_to_download=bytes_to_download,
            library_volume_free_bytes=free_bytes,
            hidden_item_count=0,
        )

    def test_enough_room_passes(self):
        cli.require_room_to_download(self.status(bytes_to_download=10 * GIGABYTE, free_bytes=100 * GIGABYTE))

    def test_exactly_twenty_gigabytes_left_passes(self):
        cli.require_room_to_download(self.status(bytes_to_download=80 * GIGABYTE, free_bytes=100 * GIGABYTE))

    def test_leaving_under_twenty_gigabytes_is_refused(self):
        with pytest.raises(SystemExit, match="Pick a shorter date range"):
            cli.require_room_to_download(self.status(bytes_to_download=81 * GIGABYTE, free_bytes=100 * GIGABYTE))
