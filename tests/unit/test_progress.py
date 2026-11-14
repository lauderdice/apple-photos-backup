from datetime import date
from pathlib import Path

from photos_backup.progress import DayProgress, compute_day_progress, read_synced_uuids
from tests.conftest import FakePhotosDB, burst_taken, create_exported_file, photo_taken, write_export_database


class TestReadSyncedUuids:
    def test_no_export_database_means_nothing_synced(self, tmp_path: Path):
        assert read_synced_uuids(tmp_path) == set()

    def test_uuid_counts_as_synced_only_when_its_file_exists(self, tmp_path: Path):
        create_exported_file(tmp_path, "2026/02/14/IMG_0001.HEIC")
        write_export_database(
            tmp_path,
            {"2026/02/14/IMG_0001.HEIC": "present-uuid", "2026/02/14/IMG_0002.HEIC": "file-deleted-uuid"},
        )

        assert read_synced_uuids(tmp_path) == {"present-uuid"}

    def test_live_photo_counts_once_when_either_file_exists(self, tmp_path: Path):
        create_exported_file(tmp_path, "2026/02/14/IMG_0001.HEIC")
        write_export_database(
            tmp_path, {"2026/02/14/IMG_0001.HEIC": "live-uuid", "2026/02/14/IMG_0001.mov": "live-uuid"}
        )

        assert read_synced_uuids(tmp_path) == {"live-uuid"}

    def test_reading_never_modifies_the_export_database(self, tmp_path: Path):
        create_exported_file(tmp_path, "a.jpg")
        database = write_export_database(tmp_path, {"a.jpg": "uuid-a"})
        bytes_before = database.read_bytes()
        modified_before = database.stat().st_mtime_ns

        read_synced_uuids(tmp_path)

        assert database.read_bytes() == bytes_before
        assert database.stat().st_mtime_ns == modified_before
        assert sorted(path.name for path in tmp_path.iterdir()) == [".osxphotos_export.db", "a.jpg"]


class TestComputeDayProgress:
    def test_counts_total_and_synced_items_per_day_in_date_order(self, fake_library: Path, tmp_path: Path):
        export_folder = tmp_path / "Photos Library"
        FakePhotosDB.photos_in_library = [
            photo_taken("feb-14-synced", 2026, 2, 14),
            photo_taken("feb-14-missing", 2026, 2, 14),
            photo_taken("jan-1-missing", 2026, 1, 1),
        ]
        create_exported_file(export_folder, "2026/02/14/synced.HEIC")
        write_export_database(export_folder, {"2026/02/14/synced.HEIC": "feb-14-synced"})

        progress = compute_day_progress(fake_library, export_folder)

        assert progress == [
            DayProgress(day=date(2026, 1, 1), total_items=1, synced_items=0, hidden_items=0),
            DayProgress(day=date(2026, 2, 14), total_items=2, synced_items=1, hidden_items=0),
        ]

    def test_every_burst_frame_counts_toward_its_day(self, fake_library: Path, tmp_path: Path):
        """Regression: the app showed a burst as one item although the export writes every frame."""
        export_folder = tmp_path / "Photos Library"
        FakePhotosDB.photos_in_library = [burst_taken("burst", hidden_frame_count=3, year=2016, month=12, day=24)]
        create_exported_file(export_folder, "2016/12/24/frame.JPG")
        write_export_database(export_folder, {"2016/12/24/frame.JPG": "burst-frame-1"})

        assert compute_day_progress(fake_library, export_folder) == [
            DayProgress(day=date(2016, 12, 24), total_items=4, synced_items=1, hidden_items=0)
        ]

    def test_hidden_items_are_counted_apart_and_shared_with_you_items_are_left_out(self, fake_library: Path, tmp_path: Path):
        """Regression: a fully synced 2017 kept showing hidden photos and Messages photos as missing."""
        export_folder = tmp_path / "Photos Library"
        FakePhotosDB.photos_in_library = [
            photo_taken("synced", 2017, 4, 15),
            photo_taken("hidden", 2017, 4, 15, hidden=True),
            photo_taken("hidden-before-it-was-backed-up", 2017, 4, 15, hidden=True),
            photo_taken("from-messages", 2017, 4, 15, syndicated=True),
        ]
        create_exported_file(export_folder, "2017/04/15/a.JPG")
        create_exported_file(export_folder, "2017/04/15/b.JPG")
        write_export_database(export_folder, {"2017/04/15/a.JPG": "synced", "2017/04/15/b.JPG": "hidden-before-it-was-backed-up"})

        assert compute_day_progress(fake_library, export_folder) == [
            DayProgress(day=date(2017, 4, 15), total_items=2, synced_items=2, hidden_items=1)
        ]

    def test_a_day_with_only_hidden_items_is_still_listed(self, fake_library: Path, tmp_path: Path):
        FakePhotosDB.photos_in_library = [photo_taken("hidden", 2017, 1, 7, hidden=True)]

        assert compute_day_progress(fake_library, tmp_path / "Photos Library") == [
            DayProgress(day=date(2017, 1, 7), total_items=0, synced_items=0, hidden_items=1)
        ]

    def test_empty_library_has_no_days(self, fake_library: Path, tmp_path: Path):
        assert compute_day_progress(fake_library, tmp_path / "Photos Library") == []

    def test_exported_items_no_longer_in_library_are_ignored(self, fake_library: Path, tmp_path: Path):
        export_folder = tmp_path / "Photos Library"
        FakePhotosDB.photos_in_library = [photo_taken("still-here", 2026, 2, 14)]
        create_exported_file(export_folder, "old.jpg")
        write_export_database(export_folder, {"old.jpg": "deleted-from-photos"})

        assert compute_day_progress(fake_library, export_folder) == [
            DayProgress(day=date(2026, 2, 14), total_items=1, synced_items=0, hidden_items=0)
        ]


def test_day_progress_serialises_to_json_friendly_dict():
    assert DayProgress(day=date(2026, 2, 14), total_items=2, synced_items=1, hidden_items=0).as_json() == {
        "day": "2026-02-14",
        "total_items": 2,
        "synced_items": 1,
        "hidden_items": 0,
    }
