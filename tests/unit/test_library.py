from datetime import date
from pathlib import Path

import pytest

from photos_backup.library import DateRange, including_every_burst_frame, read_range_status
from tests.conftest import FakePhotosDB, burst_taken, photo_taken


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


class TestIncludingEveryBurstFrame:
    def test_photos_that_are_not_bursts_pass_through(self):
        photos = [photo_taken("a", 2026, 2, 14), photo_taken("b", 2026, 2, 14)]

        assert [photo.uuid for photo in including_every_burst_frame(photos)] == ["a", "b"]

    def test_adds_the_frames_photos_hides_behind_a_burst(self):
        burst = burst_taken("burst", hidden_frame_count=3, year=2016, month=12, day=24)

        uuids = [photo.uuid for photo in including_every_burst_frame([burst])]

        assert uuids == ["burst", "burst-frame-0", "burst-frame-1", "burst-frame-2"]

    def test_frames_listed_twice_are_counted_once(self):
        burst = burst_taken("burst", hidden_frame_count=2, year=2016, month=12, day=24)
        second_key_photo_of_same_burst = photo_taken("burst-frame-0", 2016, 12, 24, burst=True, burst_photos=burst.burst_photos)

        photos = including_every_burst_frame([burst, second_key_photo_of_same_burst])

        assert sorted(photo.uuid for photo in photos) == ["burst", "burst-frame-0", "burst-frame-1"]


class TestReadRangeStatusWithBursts:
    def test_hidden_burst_frames_are_counted_and_sized(self, fake_library: Path):
        """Regression: a 322-frame burst made a month export 630 items while only 309 were counted."""
        FakePhotosDB.photos_in_library = [
            photo_taken("single", 2016, 12, 24, original_filesize=1_000),
            burst_taken("burst", hidden_frame_count=4, year=2016, month=12, day=24, original_filesize=2_000),
        ]

        status = read_range_status(
            fake_library, DateRange(date(2016, 12, 1), date(2016, 12, 31)), before_day=date(2017, 1, 1)
        )

        assert status.item_count == 6
        assert status.items_only_in_icloud == 6
        assert status.bytes_to_download == 1_000 + 5 * 2_000
