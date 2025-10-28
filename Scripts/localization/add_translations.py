#!/usr/bin/env python3
"""
Add missing translations to Localizable.xcstrings files.
This script should be customized with specific translations when needed.
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

def add_translations_to_file(file_path, translations_dict):
    """
    Add translations to a specific file.

    Args:
        file_path: Path to the .xcstrings file
        translations_dict: Dictionary of format:
            {
                "String Key": {
                    "en": "English text",
                    "ja": "Japanese text",
                    ...
                }
            }
    """
    with open(file_path, 'r') as f:
        data = json.load(f)

    modified = False

    for string_key, translations in translations_dict.items():
        if string_key not in data["strings"]:
            print(f"  ⚠️  String '{string_key}' not found in {file_path}")
            continue

        if "localizations" not in data["strings"][string_key]:
            data["strings"][string_key]["localizations"] = {}

        for lang, value in translations.items():
            # Skip if translation already exists
            if lang in data["strings"][string_key]["localizations"]:
                continue

            data["strings"][string_key]["localizations"][lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value
                }
            }
            modified = True
            print(f"  ✅ Added {lang} translation for '{string_key}'")

    if modified:
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"  💾 Saved changes to {file_path}")
    else:
        print(f"  ℹ️  No changes needed for {file_path}")

    return modified

def main():
    """
    Main function - customize the translations dictionary for your specific needs.
    """
    project_root = Path(__file__).parent.parent.parent
    ui_file = project_root / "Sources/UI/Resources/Localizable.xcstrings"
    main_file = project_root / "Sources/Resources/Localizable.xcstrings"

    # Example translations structure - customize this based on missing translations
    # Run check_missing_translations.py first to see what needs to be translated
    ui_translations = {
        # Add your translations here
        # "String Key": {
        #     "en": "English",
        #     "ja": "日本語",
        #     ...
        # }
    }

    main_translations = {
        # Add your translations here
    }

    print("=== Adding Translations ===\n")

    if ui_translations and ui_file.exists():
        print(f"Processing: {ui_file}")
        add_translations_to_file(ui_file, ui_translations)

    if main_translations and main_file.exists():
        print(f"\nProcessing: {main_file}")
        add_translations_to_file(main_file, main_translations)

    if not ui_translations and not main_translations:
        print("ℹ️  No translations to add. Update this script with the required translations.")
        print("    Run check_missing_translations.py first to see what needs translation.")

if __name__ == "__main__":
    main()