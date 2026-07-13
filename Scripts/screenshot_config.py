#!/usr/bin/env python3
"""Builds the config.json that the screenshot UI test reads.

Called by Scripts/screenshots.sh once per locale; prints the document on stdout.

The interesting part is the seed: the locations the app comes up with are
assembled here from the fixtures, with their names translated into the locale
being shot, and handed to the app as base64 (it travels through a JSON
document, and a nested JSON string is a quoting hazard). The harmonic
parameters are the tides-api responses verbatim, so the app computes the same
tide curve it would for a real saved location — offline, with no API call.
"""

import base64
import json
import os
import pathlib
import sys

FALLBACK_LOCALE = "en-US"


def main() -> int:
    fixtures = pathlib.Path(os.environ["FIXTURES"])
    locale = os.environ["LOCALE_KEY"]

    spec = json.loads((fixtures / "locations.json").read_text())
    locations = []
    for entry in spec["locations"]:
        names = entry["names"]
        if locale not in names and FALLBACK_LOCALE not in names:
            print(
                f"error: no name for {entry['parameters']} in {locale} or {FALLBACK_LOCALE}",
                file=sys.stderr,
            )
            return 1
        parameters = json.loads((fixtures / entry["parameters"]).read_text())
        locations.append(
            {
                "name": names.get(locale, names[FALLBACK_LOCALE]),
                "latitude": entry["latitude"],
                "longitude": entry["longitude"],
                "parameters": parameters,
            }
        )

    seed = base64.b64encode(
        json.dumps({"locations": locations}, ensure_ascii=False).encode()
    ).decode()

    # The app opens on the first location, which is also the one whose chart
    # the shots are of.
    first = locations[0]
    json.dump(
        {
            "language": os.environ["LANGUAGE"],
            "region": os.environ["REGION"],
            "seed": seed,
            "fixedDate": os.environ["FIXED_DATE"],
            "selectedLatitude": first["latitude"],
            "selectedLongitude": first["longitude"],
            "externalCapture": os.environ.get("EXTERNAL") == "true",
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
