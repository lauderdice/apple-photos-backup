from datetime import date
from pathlib import Path

import pytest

from photos_backup.library import DateRange, read_range_status
from tests.conftest import FakePhotosDB, photo_taken


class TestDateRange:
    def test_single_day_is_valid(self):
        single_day = DateRange(first_day=date(2026, 2, 14), last_day=date(2026, 2, 14))
        assert single_day.first_day == single_day.last_day

    def test_last_day_before_first_day_is_rejected(self):
        with pytest.raises(ValueError, match="before --from"):
            DateRange(first_day=date(2026, 2, 15), last_day=date(2026, 2, 14))


class TestReadRangeStatus:
    def test_counts_items_and_bytes_still_only_in_icloud(self, fake_library: Path):
        FakePhotosDB.photos_in_library = [
            photo_taken("only-in-icloud", 2026, 2, 14, original_filesize=3_000),
            photo_taken("already-downloaded", 2026, 2, 14, ismissing=False, original_filesize=5_000),
            photo_taken("next-day", 2026, 2, 15),
        ]

        status = read_range_status(
            fake_library, DateRange(date(2026, 2, 14), date(2026, 2, 14)), before_day=date(2026, 2, 15)
        )

        assert status.item_count == 2
        assert status.items_only_in_icloud == 1
        assert status.bytes_to_download == 3_000
        assert status.library_path == fake_library
        assert status.library_volume_free_bytes > 0

    def test_empty_range_has_nothing_to_download(self, fake_library: Path):
        FakePhotosDB.photos_in_library = [photo_taken("elsewhere", 2020, 1, 1)]

        status = read_range_status(
            fake_library, DateRange(date(2026, 2, 14), date(2026, 2, 14)), before_day=date(2026, 2, 15)
        )

        assert (status.item_count, status.items_only_in_icloud, status.bytes_to_download) == (0, 0, 0)

    def test_missing_library_fails_fast(self, tmp_path: Path):
        with pytest.raises(FileNotFoundError, match="Photos library not found"):
            read_range_status(
                tmp_path / "nope.photoslibrary",
                DateRange(date(2026, 2, 14), date(2026, 2, 14)),
                before_day=date(2026, 2, 15),
            )
