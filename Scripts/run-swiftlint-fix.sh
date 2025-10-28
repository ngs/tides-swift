#!/bin/bash

# Script to run SwiftLint with --fix on the entire project
# This can be run manually or integrated into your workflow

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running SwiftLint with auto-fix on the entire project..."

if which swiftlint >/dev/null; then
    cd "$PROJECT_ROOT"

    # Run SwiftLint with --fix
    swiftlint --fix --config .swiftlint.yml Sources Tests

    echo "SwiftLint auto-fix complete!"

    # Show any remaining issues
    echo "Checking for remaining issues..."
    swiftlint --config .swiftlint.yml Sources Tests
else
    echo "Error: SwiftLint is not installed"
    echo "Install it with: brew install swiftlint"
    exit 1
fi