#!/usr/bin/env python3
"""
Verify that all translations are complete in Localizable.xcstrings files.
"""

import json
from pathlib import Path

def get_target_languages():
    """Return the list of target languages based on fastlane metadata."""
    return [
        "ar-SA", "ca", "cs", "da", "de-DE", "el", "en", "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja",
        "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr",
        "uk", "vi", "zh-Hans", "zh-Hant"
    ]

def verify_file(file_path):
    """Verify translations in a single file."""
    with open(file_path, 'r') as f:
        data = json.load(f)

    target_languages = get_target_languages()
    total_strings = 0
    strings_with_all_translations = 0
    missing = {}

    for key, value in data.get("strings", {}).items():
        # Skip strings that shouldn't be translated
        if value.get("shouldTranslate") == False:
            continue

        total_strings += 1
        localizations = value.get("localizations", {})
        missing_langs = []

        for lang in target_languages:
            if lang not in localizations:
                missing_langs.append(lang)

        if missing_langs:
            missing[key] = missing_langs
        else:
            strings_with_all_translations += 1

    return total_strings, strings_with_all_translations, missing

def check_duplicates(ui_file, main_file):
    """Check for duplicate keys between UI and main files."""
    with open(ui_file, 'r') as f:
        ui_data = json.load(f)
    with open(main_file, 'r') as f:
        main_data = json.load(f)

    ui_keys = set(ui_data["strings"].keys())
    main_keys = set(main_data["strings"].keys())
    duplicates = ui_keys & main_keys

    return duplicates

def main():
    """Main verification function."""
    project_root = Path(__file__).parent.parent.parent
    ui_file = project_root / "Sources/UI/Resources/Localizable.xcstrings"
    main_file = project_root / "Sources/Resources/Localizable.xcstrings"

    print("=== TRANSLATION VERIFICATION REPORT ===\n")

    total_all = 0
    complete_all = 0
    missing_all = 0

    # Check UI file
    if ui_file.exists():
        print(f"Checking: {ui_file.relative_to(project_root)}")
        ui_total, ui_complete, ui_missing = verify_file(ui_file)
        print(f"  Total translatable strings: {ui_total}")
        print(f"  Fully translated strings: {ui_complete}")
        print(f"  Missing translations: {len(ui_missing)}")

        if ui_missing:
            for key, langs in list(ui_missing.items())[:5]:  # Show first 5
                print(f"    '{key}' missing: {', '.join(langs[:5])}...")
            if len(ui_missing) > 5:
                print(f"    ... and {len(ui_missing) - 5} more strings")

        total_all += ui_total
        complete_all += ui_complete
        missing_all += len(ui_missing)
    else:
        print(f"  ⚠️  File not found: {ui_file}")

    # Check main file
    if main_file.exists():
        print(f"\nChecking: {main_file.relative_to(project_root)}")
        main_total, main_complete, main_missing = verify_file(main_file)
        print(f"  Total translatable strings: {main_total}")
        print(f"  Fully translated strings: {main_complete}")
        print(f"  Missing translations: {len(main_missing)}")

        if main_missing:
            for key, langs in list(main_missing.items())[:5]:  # Show first 5
                print(f"    '{key}' missing: {', '.join(langs[:5])}...")
            if len(main_missing) > 5:
                print(f"    ... and {len(main_missing) - 5} more strings")

        total_all += main_total
        complete_all += main_complete
        missing_all += len(main_missing)
    else:
        print(f"  ⚠️  File not found: {main_file}")

    # Summary
    print("\n=== SUMMARY ===")
    print(f"Total translatable strings across both files: {total_all}")
    print(f"Fully translated strings: {complete_all}")
    print(f"Strings with missing translations: {missing_all}")

    if missing_all == 0:
        print("\n✅ SUCCESS: All strings are fully translated for all target languages!")
    else:
        completion_rate = (complete_all / total_all * 100) if total_all > 0 else 0
        print(f"\n⚠️  Translation completion rate: {completion_rate:.1f}%")
        print(f"    {missing_all} strings still need translations.")

    # Check for duplicate keys
    if ui_file.exists() and main_file.exists():
        print("\n=== CHECKING FOR DUPLICATES ===")
        duplicates = check_duplicates(ui_file, main_file)

        if duplicates:
            print(f"Found {len(duplicates)} duplicate keys across both files:")
            for key in sorted(duplicates)[:10]:  # Show first 10
                print(f"  - {key}")
            if len(duplicates) > 10:
                print(f"  ... and {len(duplicates) - 10} more")
        else:
            print("✅ No duplicate keys found between the two files.")

    return 0 if missing_all == 0 else 1

if __name__ == "__main__":
    exit(main())