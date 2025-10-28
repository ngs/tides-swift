#!/usr/bin/env python3
"""
Main script to complete all translations for Localizable.xcstrings files.
This orchestrates the other scripts to check, fix, and verify translations.
"""

import subprocess
import sys
from pathlib import Path

def run_script(script_name, description):
    """Run a Python script and return its exit code."""
    script_path = Path(__file__).parent / script_name
    print(f"\n{'='*60}")
    print(f"🔧 {description}")
    print(f"{'='*60}")

    result = subprocess.run([sys.executable, str(script_path)], capture_output=False)
    return result.returncode

def main():
    """Main orchestration function."""
    print("🌍 STARTING LOCALIZATION COMPLETION PROCESS")

    # Step 1: Check for missing translations
    if run_script("check_missing_translations.py", "Step 1: Checking for missing translations") != 0:
        print("\n⚠️  Missing translations detected. Please update add_translations.py with the required translations.")
        print("    Then run this script again.")
        # Note: In actual use, you would need to update add_translations.py with specific translations
        # based on what's missing, then run it.

    # Step 2: Fix Norwegian locale codes
    run_script("fix_norwegian_locale.py", "Step 2: Fixing Norwegian language codes (nb → no)")

    # Step 3: Verify all translations are complete
    exit_code = run_script("verify_translations.py", "Step 3: Verifying all translations")

    print(f"\n{'='*60}")
    if exit_code == 0:
        print("✅ LOCALIZATION COMPLETION SUCCESSFUL!")
        print("   All strings have translations for all target languages.")
    else:
        print("⚠️  LOCALIZATION INCOMPLETE")
        print("   Some strings still need translations.")
        print("   Update add_translations.py with the missing translations and run again.")
    print(f"{'='*60}\n")

    return exit_code

if __name__ == "__main__":
    sys.exit(main())