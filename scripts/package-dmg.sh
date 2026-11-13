#!/bin/zsh
# Builds the app and packages it as a drag-to-install disk image for distribution.
#
#   scripts/package-dmg.sh [OUTPUT_FOLDER]     (default ~/Library/Caches/photos-backup-tracker/dist)
#
# SIGNING_IDENTITY   codesign identity for the app (default "-", ad hoc; see app/build.sh)
set -euo pipefail

project_folder="${0:A:h:h}"
output_folder="${1:-$HOME/Library/Caches/photos-backup-tracker/dist}"
version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$project_folder/app/Info.plist")"
architecture="$(uname -m)"
dmg="$output_folder/Photos-Backup-Tracker-$version-$architecture.dmg"
disk_image_contents="$(mktemp -d)"
trap 'rm -rf "$disk_image_contents"' EXIT

"$project_folder/app/build.sh" "$disk_image_contents"
ln -s /Applications "$disk_image_contents/Applications"

echo "== Creating $dmg"
mkdir -p "$output_folder"
rm -f "$dmg"
hdiutil create -quiet -volname "Photos Backup Tracker" -srcfolder "$disk_image_contents" -fs HFS+ -format UDZO -ov "$dmg"

echo "Created $dmg ($(du -h "$dmg" | cut -f1))"
