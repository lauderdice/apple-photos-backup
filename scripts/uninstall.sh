#!/bin/zsh
# Removes the app and its CLI copy. Leaves your backup drive, its logs and your Photos library untouched.
#
# INSTALL_FOLDER  where the app was installed (default /Applications)
set -euo pipefail

install_folder="${INSTALL_FOLDER:-/Applications}"

rm -rf "$install_folder/Photos Backup Tracker.app"
rm -rf "$HOME/Library/Application Support/Photos Backup Tracker"
defaults delete io.github.photos-backup-tracker 2>/dev/null || true

echo "Removed Photos Backup Tracker. Your backup drive and Photos library were not touched."
echo "To also forget its macOS permissions: tccutil reset All io.github.photos-backup-tracker"
