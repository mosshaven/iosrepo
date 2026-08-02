#!/usr/bin/env python3
"""Add repository-specific Cydia metadata to generated package indexes."""

from pathlib import Path
import sys


REPO_URL = "https://ios.slutvibe.site"
OVERRIDES = {
    "ai.akemi.appsyncunified": {
        "Depiction": f"{REPO_URL}/depictions/appsync.html",
        "Icon": f"{REPO_URL}/icons/ai.akemi.appsyncunified.png",
    },
    "ldid": {
        "Name": "ldid",
        "Depiction": f"{REPO_URL}/depictions/ldid.html",
        "Icon": f"{REPO_URL}/CydiaIcon.png",
    },
}


def patch_stanza(stanza: str) -> str:
    lines = stanza.splitlines()
    fields = dict(line.split(": ", 1) for line in lines if ": " in line)
    overrides = OVERRIDES.get(fields.get("Package", ""), {})
    if not overrides:
        return stanza

    replaced = set()
    output = []
    for line in lines:
        key = line.split(":", 1)[0]
        if key in overrides:
            output.append(f"{key}: {overrides[key]}")
            replaced.add(key)
        else:
            output.append(line)
    output.extend(f"{key}: {value}" for key, value in overrides.items() if key not in replaced)
    return "\n".join(output)


path = Path(sys.argv[1] if len(sys.argv) > 1 else "Packages")
stanzas = [stanza for stanza in path.read_text().strip().split("\n\n") if stanza]
path.write_text("\n\n".join(map(patch_stanza, stanzas)) + "\n")
