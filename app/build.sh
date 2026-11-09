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

# The icon is drawn by app/icon/render-icon.swift; redraw it only when that script changes.
icon="$scratch_path/AppIcon.icns"
if [[ ! -f "$icon" || "$app_folder/icon/render-icon.swift" -nt "$icon" ]]; then
    iconset="$scratch_path/AppIcon.iconset"
    rm -rf "$iconset" && mkdir -p "$iconset"
    swift "$app_folder/icon/render-icon.swift" "$iconset/icon_512x512@2x.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil --convert icns --output "$icon" "$iconset"
fi

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$bin_path/PhotosBackupTracker" "$bundle/Contents/MacOS/PhotosBackupTracker"
cp "$app_folder/Info.plist" "$bundle/Contents/Info.plist"
mkdir -p "$bundle/Contents/Resources"
cp "$icon" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign "$signing_identity" "$bundle"

echo "Built $bundle"
