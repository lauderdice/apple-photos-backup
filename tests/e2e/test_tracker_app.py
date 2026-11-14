"""Builds Photos Backup Tracker.app from the current source and launches it against a fake CLI.

Opt in with: uv run pytest -m e2e

Checks that the packaged app starts, honours its configuration and asks the CLI for progress of the backup
folder. It never touches an installed copy of the app. The window appears on screen for a few seconds.
Clicking through the UI isn't automated (that needs XCUITest, i.e. full Xcode); the Swift tests cover what
the buttons do.
"""

import os
import stat
import subprocess
import time
from pathlib import Path

import pytest

pytestmark = pytest.mark.e2e

PROJECT_FOLDER = Path(__file__).parents[2]
SECONDS_TO_WAIT_FOR_APP = 20


@pytest.fixture(scope="module")
def app_executable(tmp_path_factory: pytest.TempPathFactory) -> Path:
    build_folder = tmp_path_factory.mktemp("app-build")
    subprocess.run([str(PROJECT_FOLDER / "app" / "build.sh"), str(build_folder)], check=True, capture_output=True)
    return build_folder / "Photos Backup Tracker.app" / "Contents" / "MacOS" / "PhotosBackupTracker"


def write_fake_cli(folder: Path, calls_file: Path) -> Path:
    fake_cli = folder / "fake-photos-backup"
    fake_cli.write_text(
        "#!/bin/sh\n"
        f'printf "%s\\n" "$*" >> "{calls_file}"\n'
        'if [ "$1" = progress ]; then\n'
        '  echo \'{"days": [{"day": "2026-02-14", "total_items": 2, "synced_items": 2, "hidden_items": 0}]}\'\n'
        "fi\n"
    )
    fake_cli.chmod(fake_cli.stat().st_mode | stat.S_IXUSR)
    return fake_cli


def wait_for_calls(calls_file: Path) -> list[str]:
    deadline = time.monotonic() + SECONDS_TO_WAIT_FOR_APP
    while time.monotonic() < deadline:
        if calls_file.exists() and calls_file.read_text().strip():
            return calls_file.read_text().splitlines()
        time.sleep(0.2)
    return []


def test_app_launches_and_asks_the_cli_for_progress_of_the_configured_folder(app_executable: Path, tmp_path: Path):
    calls_file = tmp_path / "cli-calls.txt"
    fake_cli = write_fake_cli(tmp_path, calls_file)
    fake_target = "/Volumes/E2E Test Drive/Photos"
    app = subprocess.Popen(
        [str(app_executable)],
        env=os.environ | {"PHOTOS_BACKUP_TRACKER_CLI": str(fake_cli), "PHOTOS_BACKUP_TRACKER_TARGET": fake_target},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        calls = wait_for_calls(calls_file)
        assert app.poll() is None, f"app quit early: {app.stderr.read().decode()}"
    finally:
        app.terminate()
        app.wait(timeout=10)

    assert calls == [f"progress {fake_target}"]


def test_embedded_python_runs_the_cli_with_nothing_else_installed(app_executable: Path):
    embedded_python = app_executable.parents[1] / "Resources" / "python" / "bin" / "python3"

    completed = subprocess.run(
        [str(embedded_python), "-I", "-m", "photos_backup.cli", "--help"],
        env={"HOME": str(Path.home()), "PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
        capture_output=True,
        text=True,
        cwd="/",
    )

    assert completed.returncode == 0, completed.stderr
    assert "usage: photos-backup" in completed.stdout


def test_embedded_python_has_osxphotos_and_no_paths_to_the_build_machine(app_executable: Path):
    embedded_python = app_executable.parents[1] / "Resources" / "python" / "bin" / "python3"

    completed = subprocess.run(
        [str(embedded_python), "-I", "-c", "import sys, osxphotos, photos_backup; print(sys.prefix); print(photos_backup.__file__)"],
        env={"HOME": str(Path.home()), "PATH": "/usr/bin:/bin"},
        capture_output=True,
        text=True,
    )

    assert completed.returncode == 0, completed.stderr
    bundle_resources = str(app_executable.parents[1] / "Resources")
    assert all(line.startswith(bundle_resources) for line in completed.stdout.splitlines())
