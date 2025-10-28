#!/bin/bash

# SwiftLint Script
# This script runs SwiftLint with different modes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    echo -e "${RED}SwiftLint is not installed.${NC}"
    echo "Install it with: brew install swiftlint"
    exit 1
fi

# Default mode is check
MODE=${1:-check}

case "$MODE" in
    check)
        echo -e "${YELLOW}Running SwiftLint check...${NC}"
        swiftlint lint --quiet
        ;;
    fix)
        echo -e "${YELLOW}Running SwiftLint auto-fix...${NC}"
        swiftlint lint --fix --quiet
        echo -e "${GREEN}Auto-fix complete!${NC}"
        ;;
    strict)
        echo -e "${YELLOW}Running SwiftLint in strict mode...${NC}"
        swiftlint lint --strict
        ;;
    *)
        echo "Usage: $0 [check|fix|strict]"
        echo "  check  - Run SwiftLint and report issues (default)"
        echo "  fix    - Auto-fix correctable issues"
        echo "  strict - Run in strict mode (warnings as errors)"
        exit 1
        ;;
esac

echo -e "${GREEN}SwiftLint complete!${NC}"