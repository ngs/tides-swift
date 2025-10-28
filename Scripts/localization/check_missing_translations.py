#!/usr/bin/env python3
"""
Check for missing translations in Localizable.xcstrings files.
"""

import json
import sys
from pathlib import Path

def get_target_languages():
    """Return the list of target languages based on fastlane metadata."""
    return [
        "ar-SA", "ca", "cs", "da", "de-DE", "el", "en", "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja",
        "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr",
        "uk", "vi", "zh-Hans", "zh-Hant"
    ]

def check_missing_translations(file_path):
    """Check which strings are missing translations in a given file."""
    with open(file_path, 'r') as f:
        data = json.load(f)

    target_languages = get_target_languages()
    missing = {}

    for key, value in data.get("strings", {}).items():
        # Skip strings that shouldn't be translated
        if value.get("shouldTranslate") == False:
            continue

        localizations = value.get("localizations", {})
        missing_langs = []

        for lang in target_languages:
            if lang not in localizations:
                # Check for Norwegian special case (nb vs no)
                if lang == "no" and "nb" in localizations:
                    continue
                missing_langs.append(lang)

        if missing_langs:
            missing[key] = missing_langs

    return missing

def main():
    # Define file paths
    project_root = Path(__file__).parent.parent.parent
    ui_file = project_root / "Sources/UI/Resources/Localizable.xcstrings"
    main_file = project_root / "Sources/Resources/Localizable.xcstrings"

    print("=== Checking for Missing Translations ===\n")

    # Check UI file
    if ui_file.exists():
        print(f"Checking: {ui_file}")
        ui_missing = check_missing_translations(ui_file)
        if ui_missing:
            for key, langs in ui_missing.items():
                print(f"\n'{key}' is missing translations for:")
                print(f"  {', '.join(langs)}")
        else:
            print("  ✅ All strings have complete translations")
    else:
        print(f"  ⚠️  File not found: {ui_file}")

    # Check main file
    if main_file.exists():
        print(f"\n\nChecking: {main_file}")
        main_missing = check_missing_translations(main_file)
        if main_missing:
            for key, langs in main_missing.items():
                print(f"\n'{key}' is missing translations for:")
                print(f"  {', '.join(langs)}")
        else:
            print("  ✅ All strings have complete translations")
    else:
        print(f"  ⚠️  File not found: {main_file}")

    # Summary
    total_missing = len(ui_missing if ui_file.exists() else {}) + len(main_missing if main_file.exists() else {})

    print("\n\n=== Summary ===")
    if total_missing == 0:
        print("✅ All strings have complete translations!")
        return 0
    else:
        print(f"⚠️  {total_missing} strings need translations")
        return 1

if __name__ == "__main__":
    sys.exit(main())