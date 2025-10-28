#!/usr/bin/env python3
"""
Fix Norwegian language codes in Localizable.xcstrings files.
Renames 'nb' (Norwegian Bokmål) to 'no' (Norwegian) to match fastlane metadata.
"""

import json
from pathlib import Path

def fix_norwegian_in_file(file_path):
    """Fix Norwegian language code in a single file."""
    with open(file_path, 'r') as f:
        data = json.load(f)

    modified = False

    for key, value in data.get("strings", {}).items():
        localizations = value.get("localizations", {})

        # If "nb" exists but "no" doesn't, rename "nb" to "no"
        if "nb" in localizations and "no" not in localizations:
            localizations["no"] = localizations.pop("nb")
            modified = True
            print(f"  ✅ Renamed 'nb' to 'no' for string: {key}")

    if modified:
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"  💾 File updated: {file_path}")
    else:
        print(f"  ℹ️  No changes needed for: {file_path}")

    return modified

def main():
    """Main function to fix Norwegian locale in all Localizable.xcstrings files."""
    project_root = Path(__file__).parent.parent.parent
    ui_file = project_root / "Sources/UI/Resources/Localizable.xcstrings"
    main_file = project_root / "Sources/Resources/Localizable.xcstrings"

    print("=== Fixing Norwegian Language Codes ===")
    print("Converting 'nb' (Norwegian Bokmål) to 'no' (Norwegian)\n")

    # Fix UI file
    if ui_file.exists():
        print(f"Processing: {ui_file}")
        fix_norwegian_in_file(ui_file)
    else:
        print(f"  ⚠️  File not found: {ui_file}")

    # Fix main file
    if main_file.exists():
        print(f"\nProcessing: {main_file}")
        fix_norwegian_in_file(main_file)
    else:
        print(f"  ⚠️  File not found: {main_file}")

    print("\n✅ Done!")

if __name__ == "__main__":
    main()