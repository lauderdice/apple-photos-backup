#!/bin/zsh
# Runs the Swift test suite against the current source. Swift Testing ships with the Xcode command-line
# tools but outside the default search paths, so point the compiler, linker and test runner at it.
#
# SWIFT_SCRATCH_PATH  where the Swift compiler writes its build output (default ~/Library/Caches/photos-backup-tracker/swift-build)
set -euo pipefail

app_folder="${0:A:h}"
scratch_path="${SWIFT_SCRATCH_PATH:-$HOME/Library/Caches/photos-backup-tracker/swift-build}"
developer_folder="$(xcode-select -p)/Library/Developer"

# Only the command-line tools need the extra paths; full Xcode finds Swift Testing on its own.
testing_flags=()
if [[ -d "$developer_folder/Frameworks/Testing.framework" ]]; then
    testing_flags=(
        -Xswiftc -F -Xswiftc "$developer_folder/Frameworks"
        -Xlinker -rpath -Xlinker "$developer_folder/Frameworks"
        -Xlinker -rpath -Xlinker "$developer_folder/usr/lib"
    )
fi

swift test --package-path "$app_folder" --scratch-path "$scratch_path" "${testing_flags[@]}" "$@"
