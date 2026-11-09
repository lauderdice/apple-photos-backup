#!/bin/zsh
# Installs Photos Backup Tracker for the current user:
#   1. the photos-backup CLI, with its locked dependencies, into ~/Library/Application Support/Photos Backup Tracker/cli
#   2. the app, built from the current source, into /Applications
#
# INSTALL_FOLDER     where the app goes (default /Applications)
# SIGNING_IDENTITY   codesign identity for the app (default "-", ad hoc; see app/build.sh)
set -euo pipefail

project_folder="${0:A:h:h}"
install_folder="${INSTALL_FOLDER:-/Applications}"
cli_environment="$HOME/Library/Application Support/Photos Backup Tracker/cli"
staging_folder="$(mktemp -d)"
trap 'rm -rf "$staging_folder"' EXIT

command -v uv >/dev/null || { echo "uv is required: https://docs.astral.sh/uv/" >&2; exit 1; }
command -v swift >/dev/null || { echo "Swift is required: run xcode-select --install" >&2; exit 1; }

echo "== Installing the photos-backup CLI into $cli_environment"
uv venv --quiet --allow-existing --python "$(cat "$project_folder/.python-version")" "$cli_environment"
uv export --project "$project_folder" --frozen --no-dev --no-emit-project --no-hashes --quiet > "$staging_folder/requirements.txt"
uv pip install --quiet --python "$cli_environment/bin/python" -r "$staging_folder/requirements.txt"
uv pip install --quiet --python "$cli_environment/bin/python" --no-deps --reinstall-package photos-backup "$project_folder"

echo "== Building the app"
"$project_folder/app/build.sh" "$staging_folder"

echo "== Installing the app into $install_folder"
rm -rf "$install_folder/Photos Backup Tracker.app"
cp -R "$staging_folder/Photos Backup Tracker.app" "$install_folder/"

cat <<EOF

Installed "$install_folder/Photos Backup Tracker.app".

Open it from Applications (or Spotlight). The first time, macOS asks whether it may access your Photos
library and your external drive; allow both. It remembers your answers until the app is reinstalled.
EOF
