"""Checks that make sure an export can only add files, and that anything else is caught and logged."""

from dataclasses import dataclass
from pathlib import Path

# osxphotos options that delete or overwrite files on the drive, or change the Photos library.
# The export command is refused if any of them ever appears in it.
FORBIDDEN_OSXPHOTOS_OPTIONS = frozenset({
    "--cleanup",
    "--cleanup-command",
    "--overwrite",
    "--force-update",
    "--add-exported-to-album",
    "--add-skipped-to-album",
    "--add-missing-to-album",
    "--post-command",
    "--post-function",
})

# Files that change on their own and are not photos: Finder's folder settings, and osxphotos' export
# database (plus its SQLite journal files), which osxphotos rewrites on every run.
IGNORED_FILE_NAME_PREFIXES = (".DS_Store", ".osxphotos_export.db")


class UnsafeCommandError(RuntimeError):
    pass


class FilesDisappearedError(RuntimeError):
    pass


@dataclass(frozen=True)
class FileFingerprint:
    size_bytes: int
    modified_at_ns: int


@dataclass(frozen=True)
class DriveChanges:
    new_files: list[Path]
    changed_files: list[Path]
    disappeared_files: list[Path]


def require_only_safe_options(command: list[str]) -> None:
    forbidden_options_used = FORBIDDEN_OSXPHOTOS_OPTIONS.intersection(command)
    if forbidden_options_used:
        raise UnsafeCommandError(f"Refusing to run osxphotos with {sorted(forbidden_options_used)}")


def fingerprint_files(folder: Path) -> dict[Path, FileFingerprint]:
    if not folder.exists():
        return {}
    fingerprints = {}
    for path in folder.rglob("*"):
        if path.is_file() and not path.name.startswith(IGNORED_FILE_NAME_PREFIXES):
            file_stat = path.stat()
            fingerprints[path.relative_to(folder)] = FileFingerprint(file_stat.st_size, file_stat.st_mtime_ns)
    return fingerprints


def compare_drive(before: dict[Path, FileFingerprint], after: dict[Path, FileFingerprint]) -> DriveChanges:
    return DriveChanges(
        new_files=sorted(after.keys() - before.keys()),
        changed_files=sorted(path for path in before.keys() & after.keys() if before[path] != after[path]),
        disappeared_files=sorted(before.keys() - after.keys()),
    )


def require_no_files_disappeared(changes: DriveChanges) -> None:
    if changes.disappeared_files:
        listing = "\n".join(f"  {path}" for path in changes.disappeared_files)
        raise FilesDisappearedError(
            f"{len(changes.disappeared_files)} files that were on the drive before this run are gone:\n{listing}"
        )
