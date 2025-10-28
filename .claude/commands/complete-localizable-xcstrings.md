# Complete Localization for Localizable.xcstrings Files

## Task
Complete the localization for all untranslated strings in the project's Localizable.xcstrings files. The project contains multiple localization files that need to be updated with translations for all supported languages.

## Files to Process
1. `/Sources/UI/Resources/Localizable.xcstrings`
2. `/Sources/Resources/Localizable.xcstrings`

## Target Languages
The project supports the following languages (based on fastlane/metadata locales):
- English (en) - Source language
- Arabic (ar-SA)
- Catalan (ca)
- Czech (cs)
- Danish (da)
- German (de-DE)
- Greek (el)
- English - Australia (en-AU)
- English - Canada (en-CA)
- English - United Kingdom (en-GB)
- English - United States (en-US)
- Spanish - Spain (es-ES)
- Spanish - Mexico (es-MX)
- Finnish (fi)
- French - Canada (fr-CA)
- French - France (fr-FR)
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
- Portuguese - Brazil (pt-BR)
- Portuguese - Portugal (pt-PT)
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

## Instructions

1. **Analyze each Localizable.xcstrings file**:
   - Read the entire content of each file
   - Identify strings that are missing translations for any of the target languages
   - Note strings where only some languages have translations

2. **Add missing translations**:
   - For each string that lacks translations in any target language, add the appropriate translation
   - Ensure translations are contextually appropriate for a stopwatch/timer application
   - Maintain consistency with existing translations in tone and terminology

3. **Translation Guidelines**:
   - Keep translations concise and appropriate for UI elements
   - Consider button labels, menu items, and short messages
   - Use formal/polite forms where culturally appropriate
   - For technical terms (like "Lap", "Split", etc.), use commonly accepted translations in each language
   - Preserve any format specifiers (like %@, %lld) in the exact same position and format

4. **JSON Structure**:
   - Maintain the exact JSON structure of the xcstrings format
   - Each translation should include `"state" : "translated"`
   - Preserve any existing translations and only add missing ones

5. **Context for Translation**:
   This is a stopwatch/timer application with the following features:
   - Start, Stop, Resume, Reset controls
   - Lap time tracking
   - Export functionality (CSV format)
   - Preferences for appearance and behavior
   - Sound and haptic feedback options
   - Color customization

6. **Common Terms Reference**:
   - "Start" - Begin timing
   - "Stop" - Pause timing
   - "Resume" - Continue timing after pause
   - "Reset" - Clear all timing data
   - "Lap" - Record split time
   - "Export" - Save data to file
   - "Preferences" - Application settings

7. **Quality Checks**:
   - Verify all strings have translations for all target languages
   - Ensure no duplicate keys exist
   - Validate JSON syntax is correct
   - Check that format specifiers are preserved correctly
   - Confirm cultural appropriateness of translations

## Example Entry Structure
```json
"String Key": {
  "localizations": {
    "en": {
      "stringUnit": {
        "state": "translated",
        "value": "English Text"
      }
    },
    "ar-SA": {
      "stringUnit": {
        "state": "translated",
        "value": "نص عربي"
      }
    },
    "ja": {
      "stringUnit": {
        "state": "translated",
        "value": "日本語テキスト"
      }
    },
    "ko": {
      "stringUnit": {
        "state": "translated",
        "value": "한국어 텍스트"
      }
    },
    "zh-Hans": {
      "stringUnit": {
        "state": "translated",
        "value": "简体中文文本"
      }
    },
    "zh-Hant": {
      "stringUnit": {
        "state": "translated",
        "value": "繁體中文文本"
      }
    }
    // ... other languages
  }
}
```

## Execution Steps

**IMPORTANT: Use the existing Python scripts in `/scripts/localization/` instead of creating temporary files.**

1. **Check for missing translations**:
   ```bash
   python3 scripts/localization/check_missing_translations.py
   ```

2. **If translations are missing**:
   - Create a temporary Python script based on `scripts/localization/add_translations.py`
   - Populate it with the specific translations needed
   - Run the script to add translations

3. **Fix Norwegian locale codes** (if needed):
   ```bash
   python3 scripts/localization/fix_norwegian_locale.py
   ```

4. **Verify all translations are complete**:
   ```bash
   python3 scripts/localization/verify_translations.py
   ```

Alternatively, use the main orchestration script:
```bash
python3 scripts/localization/complete_translations.py
```

**Available Scripts**:
- `check_missing_translations.py` - Identifies missing translations
- `add_translations.py` - Template for adding specific translations
- `fix_norwegian_locale.py` - Converts 'nb' to 'no' locale codes
- `verify_translations.py` - Comprehensive verification
- `complete_translations.py` - Main orchestration script

See `/scripts/localization/README.md` for detailed documentation

## Notes
- Some strings like ":", ".", or empty strings ("") may not need translations as they are punctuation marks
- Focus on meaningful text strings that appear in the user interface
- If a string already has a translation for a language, do not modify it unless it's clearly incorrect
- The `"state": "translated"` field is important for the build system to recognize completed translations
- For locale codes, use the exact format from fastlane/metadata (e.g., "ar-SA" not "ar", "de-DE" not "de")
- English variants (en-AU, en-CA, en-GB, en-US) can share the same translation as "en" unless specific regional differences are needed
- Regional variants like fr-CA vs fr-FR, es-ES vs es-MX, pt-BR vs pt-PT should have appropriate regional variations where applicable