# Localization Scripts

This directory contains Python scripts for managing translations in the Localizable.xcstrings files.

## Scripts Overview

### 1. `check_missing_translations.py`
Checks both Localizable.xcstrings files for missing translations.
```bash
python3 scripts/localization/check_missing_translations.py
```

### 2. `add_translations.py`
Adds missing translations to the files. You need to customize this script with the actual translations.
```bash
# First edit the script to add your translations
python3 scripts/localization/add_translations.py
```

### 3. `fix_norwegian_locale.py`
Converts Norwegian language codes from 'nb' to 'no' to match fastlane metadata.
```bash
python3 scripts/localization/fix_norwegian_locale.py
```

### 4. `verify_translations.py`
Comprehensive verification of all translations, including duplicate detection.
```bash
python3 scripts/localization/verify_translations.py
```

### 5. `complete_translations.py`
Main orchestration script that runs all the above in sequence.
```bash
python3 scripts/localization/complete_translations.py
```

## Target Languages

The scripts work with the following languages (based on fastlane/metadata):
- Arabic (ar-SA)
- Catalan (ca)
- Czech (cs)
- Danish (da)
- German (de-DE)
- Greek (el)
- English variants (en, en-AU, en-CA, en-GB, en-US)
- Spanish variants (es-ES, es-MX)
- Finnish (fi)
- French variants (fr-CA, fr-FR)
- Hebrew (he)
- Hindi (hi)
- Croatian (hr)
- Hungarian (hu)
- Indonesian (id)
- Italian (it)
- Japanese (ja)
- Korean (ko)
- Malay (ms)
- Dutch (nl-NL)
- Norwegian (no)
- Polish (pl)
- Portuguese variants (pt-BR, pt-PT)
- Romanian (ro)
- Russian (ru)
- Slovak (sk)
- Swedish (sv)
- Thai (th)
- Turkish (tr)
- Ukrainian (uk)
- Vietnamese (vi)
- Chinese Simplified (zh-Hans)
- Chinese Traditional (zh-Hant)

## Files Processed

- `/Sources/UI/Resources/Localizable.xcstrings` - UI-related strings
- `/Sources/Resources/Localizable.xcstrings` - General application strings

## Usage for Adding New Translations

1. Run `check_missing_translations.py` to identify missing translations
2. Edit `add_translations.py` with the required translations
3. Run `add_translations.py` to apply the translations
4. Run `verify_translations.py` to confirm everything is complete

Or simply run `complete_translations.py` which orchestrates all steps.