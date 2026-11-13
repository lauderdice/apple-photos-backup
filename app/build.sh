#!/bin/zsh
# Builds a self-contained "Photos Backup Tracker.app" from the current source into OUTPUT_FOLDER.
#
#   app/build.sh OUTPUT_FOLDER
#
# The app carries its own Python runtime with the photos-backup CLI and its locked dependencies in
# Contents/Resources/python, so the people who download it need nothing else installed.
#
# SIGNING_IDENTITY    codesign identity (default "-", ad hoc). With a real identity, macOS keeps the app's
#                     permissions across updates.
# SWIFT_SCRATCH_PATH  where build output and caches go (default ~/Library/Caches/photos-backup-tracker/swift-build)
set -euo pipefail

output_folder="${1:?usage: app/build.sh OUTPUT_FOLDER}"
app_folder="${0:A:h}"
project_folder="${app_folder:h}"
scratch_path="${SWIFT_SCRATCH_PATH:-$HOME/Library/Caches/photos-backup-tracker/swift-build}"
signing_identity="${SIGNING_IDENTITY:--}"
bundle="$output_folder/Photos Backup Tracker.app"
python_version="$(cat "$project_folder/.python-version")"

echo "== Building the Swift app"
swift build --configuration release --package-path "$app_folder" --scratch-path "$scratch_path"
bin_path="$(swift build --configuration release --package-path "$app_folder" --scratch-path "$scratch_path" --show-bin-path)"

# The embedded Python runtime: uv's standalone (relocatable) CPython plus the CLI and its locked dependencies.
# Rebuilt only when the Python version, the lock file or the CLI's source changes.
runtime_fingerprint="$(cat "$project_folder/.python-version" "$project_folder/uv.lock" "$project_folder/pyproject.toml" \
    "$project_folder"/src/photos_backup/*.py | shasum -a 256 | cut -c1-16)"
runtime="$scratch_path/python-runtime-$runtime_fingerprint"
if [[ ! -d "$runtime" ]]; then
    echo "== Building the embedded Python runtime"
    uv python install --quiet "$python_version"
    standalone_python="$(cd / && uv python find --no-project --managed-python "$python_version")"
    standalone_root="${standalone_python:A:h:h}"
    staging_runtime="$runtime.partial"
    rm -rf "$staging_runtime"
    cp -R "$standalone_root" "$staging_runtime"
    rm -f "$staging_runtime/lib/python$python_version/EXTERNALLY-MANAGED"
    rm -rf "$staging_runtime/lib/python$python_version/"{test,idlelib,turtledemo}

    locked_requirements="$(mktemp)"
    uv export --project "$project_folder" --frozen --no-dev --no-emit-project --no-hashes --quiet > "$locked_requirements"
    uv pip install --quiet --python "$staging_runtime/bin/python3" -r "$locked_requirements"
    uv pip install --quiet --python "$staging_runtime/bin/python3" --no-deps "$project_folder"
    rm "$locked_requirements"

    # Precompile, so the app never writes bytecode into its own (signed) bundle. Third-party packages print
    # harmless syntax warnings while compiling, hence the silenced output.
    "$staging_runtime/bin/python3" -I -m compileall -q "$staging_runtime/lib" >/dev/null 2>&1 || true
    mv "$staging_runtime" "$runtime"
fi

# The icon is drawn by app/icon/render-icon.swift; redraw it only when that script changes.
icon="$scratch_path/AppIcon.icns"
if [[ ! -f "$icon" || "$app_folder/icon/render-icon.swift" -nt "$icon" ]]; then
    echo "== Drawing the app icon"
    iconset="$scratch_path/AppIcon.iconset"
    rm -rf "$iconset" && mkdir -p "$iconset"
    swift "$app_folder/icon/render-icon.swift" "$iconset/icon_512x512@2x.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil --convert icns --output "$icon" "$iconset"
fi

echo "== Assembling the app bundle"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_path/PhotosBackupTracker" "$bundle/Contents/MacOS/PhotosBackupTracker"
cp "$app_folder/Info.plist" "$bundle/Contents/Info.plist"
cp "$icon" "$bundle/Contents/Resources/AppIcon.icns"
cp -R "$runtime" "$bundle/Contents/Resources/python"

echo "== Signing"
# Every binary inside the embedded runtime first, then the bundle itself.
find "$bundle/Contents/Resources/python" -type f \( -perm -u+x -o -name "*.so" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' candidate; do
        if file -b "$candidate" | grep -q "Mach-O"; then
            codesign --force --sign "$signing_identity" "$candidate" 2>/dev/null
        fi
    done
codesign --force --sign "$signing_identity" "$bundle"

echo "Built $bundle"
