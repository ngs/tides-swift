#!/bin/bash

# Build phase script to run SwiftLint with --fix during builds
# To use this script in Xcode:
# 1. Select your target in Xcode
# 2. Go to Build Phases
# 3. Add a new "Run Script Phase"
# 4. Place it before "Compile Sources"
# 5. Set the script path to: ${SRCROOT}/Scripts/swiftlint-fix-build-phase.sh

# Check if SwiftLint is installed
if which swiftlint >/dev/null; then
    echo "Running SwiftLint with auto-fix..."

    # Run SwiftLint with --fix on all source directories
    swiftlint --fix --config "${SRCROOT}/.swiftlint.yml" \
        "${SRCROOT}/Sources" \
        "${SRCROOT}/Tests" 2>/dev/null

    # Run SwiftLint again to report any remaining issues
    swiftlint --config "${SRCROOT}/.swiftlint.yml" \
        "${SRCROOT}/Sources" \
        "${SRCROOT}/Tests"
else
    echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi