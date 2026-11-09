import os
from pathlib import Path

import pytest

from photos_backup.safeguards import (
    FORBIDDEN_OSXPHOTOS_OPTIONS,
    FilesDisappearedError,
    UnsafeCommandError,
    compare_drive,
    fingerprint_files,
    require_no_files_disappeared,
    require_only_safe_options,
)
from tests.conftest import create_exported_file


class TestForbiddenOptions:
    def test_command_without_forbidden_options_is_allowed(self):
        require_only_safe_options(["osxphotos", "export", "/dest", "--update", "--dry-run"])

    @pytest.mark.parametrize("forbidden_option", sorted(FORBIDDEN_OSXPHOTOS_OPTIONS))
    def test_every_forbidden_option_is_refused(self, forbidden_option: str):
        with pytest.raises(UnsafeCommandError, match=forbidden_option):
            require_only_safe_options(["osxphotos", "export", "/dest", forbidden_option])

    def test_blocklist_covers_deleting_and_overwriting(self):
        assert {"--cleanup", "--overwrite", "--force-update"} <= FORBIDDEN_OSXPHOTOS_OPTIONS


class TestFingerprintFiles:
    def test_missing_folder_has_no_files(self, tmp_path: Path):
        assert fingerprint_files(tmp_path / "not-there") == {}

    def test_records_size_of_nested_files_by_relative_path(self, tmp_path: Path):
        create_exported_file(tmp_path, "2026/02/14/IMG_0001.HEIC", b"12345")

        fingerprints = fingerprint_files(tmp_path)

        assert list(fingerprints) == [Path("2026/02/14/IMG_0001.HEIC")]
        assert fingerprints[Path("2026/02/14/IMG_0001.HEIC")].size_bytes == 5

    @pytest.mark.parametrize(
        "ignored_name", [".DS_Store", ".osxphotos_export.db", ".osxphotos_export.db-wal", ".osxphotos_export.db-shm"]
    )
    def test_ignores_files_finder_and_osxphotos_rewrite_themselves(self, tmp_path: Path, ignored_name: str):
        create_exported_file(tmp_path, f"2026/{ignored_name}")

        assert fingerprint_files(tmp_path) == {}


class TestCompareDrive:
    def test_detects_new_changed_and_disappeared_files(self, tmp_path: Path):
        create_exported_file(tmp_path, "keep.jpg", b"same")
        changed = create_exported_file(tmp_path, "edit.jpg", b"before")
        disappearing = create_exported_file(tmp_path, "remove.jpg", b"bye")
        before = fingerprint_files(tmp_path)

        disappearing.unlink()
        changed.write_bytes(b"after, and longer")
        create_exported_file(tmp_path, "new.jpg")
        changes = compare_drive(before, fingerprint_files(tmp_path))

        assert changes.new_files == [Path("new.jpg")]
        assert changes.changed_files == [Path("edit.jpg")]
        assert changes.disappeared_files == [Path("remove.jpg")]

    def test_touching_a_file_counts_as_changed(self, tmp_path: Path):
        touched = create_exported_file(tmp_path, "touched.jpg")
        before = fingerprint_files(tmp_path)
        os.utime(touched, ns=(0, 1_000_000_000))

        assert compare_drive(before, fingerprint_files(tmp_path)).changed_files == [Path("touched.jpg")]

    def test_unchanged_drive_has_no_changes(self, tmp_path: Path):
        create_exported_file(tmp_path, "a.jpg")
        snapshot = fingerprint_files(tmp_path)

        changes = compare_drive(snapshot, fingerprint_files(tmp_path))

        assert (changes.new_files, changes.changed_files, changes.disappeared_files) == ([], [], [])


class TestRequireNoFilesDisappeared:
    def test_passes_when_files_were_only_added(self, tmp_path: Path):
        before = fingerprint_files(tmp_path)
        create_exported_file(tmp_path, "new.jpg")

        require_no_files_disappeared(compare_drive(before, fingerprint_files(tmp_path)))

    def test_fails_and_names_every_disappeared_file(self, tmp_path: Path):
        first =create_exported_file(tmp_path, "2026/02/14/a.jpg")
        second = create_exported_file(tmp_path, "2026/02/14/b.jpg")
        before = fingerprint_files(tmp_path)
        first.unlink()
        second.unlink()

        with pytest.raises(FilesDisappearedError) as error:
            require_no_files_disappeared(compare_drive(before, fingerprint_files(tmp_path)))

        assert "2 files" in str(error.value)
        assert "2026/02/14/a.jpg" in str(error.value)
        assert "2026/02/14/b.jpg" in str(error.value)
