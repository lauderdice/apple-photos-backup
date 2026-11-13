#!/bin/zsh
# Builds Photos Backup Tracker from the current source and installs it into /Applications.
# The app is self-contained (it embeds its own Python runtime), so nothing else gets installed.
#
# INSTALL_FOLDER     where the app goes (default /Applications)
# SIGNING_IDENTITY   codesign identity for the app (default "-", ad hoc; see app/build.sh)
set -euo pipefail

project_folder="${0:A:h:h}"
install_folder="${INSTALL_FOLDER:-/Applications}"
staging_folder="$(mktemp -d)"
trap 'rm -rf "$staging_folder"' EXIT

command -v uv >/dev/null || { echo "uv is required: https://docs.astral.sh/uv/" >&2; exit 1; }
command -v swift >/dev/null || { echo "Swift is required: run xcode-select --install" >&2; exit 1; }

"$project_folder/app/build.sh" "$staging_folder"

echo "== Installing the app into $install_folder"
rm -rf "$install_folder/Photos Backup Tracker.app"
cp -R "$staging_folder/Photos Backup Tracker.app" "$install_folder/"
# Earlier development builds kept a separate copy of the CLI here; the app no longer uses it.
rm -rf "$HOME/Library/Application Support/Photos Backup Tracker/cli"

echo "Installed \"$install_folder/Photos Backup Tracker.app\"."
