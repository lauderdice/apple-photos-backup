#!/bin/zsh
# Builds "Photos Backup Tracker.app" from the current source into OUTPUT_FOLDER.
#
#   app/build.sh OUTPUT_FOLDER
#
# SIGNING_IDENTITY  codesign identity (default "-", ad hoc). With a real identity, macOS keeps the app's
#                   Photos and drive permissions across rebuilds; with ad hoc signing it asks again after
#                   every rebuild.
# SWIFT_SCRATCH_PATH  where the Swift compiler writes its build output (default ~/Library/Caches/photos-backup-tracker/swift-build)
set -euo pipefail

output_folder="${1:?usage: app/build.sh OUTPUT_FOLDER}"
app_folder="${0:A:h}"
scratch_path="${SWIFT_SCRATCH_PATH:-$HOME/Library/Caches/photos-backup-tracker/swift-build}"
signing_identity="${SIGNING_IDENTITY:--}"
bundle="$output_folder/Photos Backup Tracker.app"

swift build --configuration release --package-path "$app_folder" --scratch-path "$scratch_path"
bin_path="$(swift build --configuration release --package-path "$app_folder" --scratch-path "$scratch_path" --show-bin-path)"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$bin_path/PhotosBackupTracker" "$bundle/Contents/MacOS/PhotosBackupTracker"
cp "$app_folder/Info.plist" "$bundle/Contents/Info.plist"
codesign --force --sign "$signing_identity" "$bundle"

echo "Built $bundle"
