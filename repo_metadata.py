#!/usr/bin/env python3
"""Add repository-specific Cydia metadata to generated package indexes.

Built-in overrides are merged with per-package entries from packages_meta.json
(the sidecar written by the Telegram bot). JSON entries win on a per-field
basis.
"""

from pathlib import Path
import json
import sys


REPO_URL = "https://ios.slutvibe.site"
BUILTIN_OVERRIDES = {
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

ROOT = Path(__file__).resolve().parent
META_PATH = ROOT / "packages_meta.json"

# Only these fields belong in the APT index. `Tags` is consumed by gen_index.py
# for the web page only; old Cydia may filter stanzas carrying unknown fields.
INDEX_FIELDS = {"Name", "Depiction", "Icon"}


def load_overrides() -> dict:
    merged = {pkg: dict(fields) for pkg, fields in BUILTIN_OVERRIDES.items()}
    if META_PATH.is_file():
        try:
            meta = json.loads(META_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            return merged
        for pkg, fields in meta.items():
            merged.setdefault(pkg, {}).update(
                {k: v for k, v in fields.items() if k in INDEX_FIELDS}
            )
    return merged


def patch_stanza(stanza: str, overrides: dict) -> str:
    lines = stanza.splitlines()
    fields = dict(line.split(": ", 1) for line in lines if ": " in line)
    ovr = overrides.get(fields.get("Package", ""), {})
    if not ovr:
        return stanza

    replaced = set()
    output = []
    for line in lines:
        key = line.split(":", 1)[0]
        if key in ovr:
            output.append(f"{key}: {ovr[key]}")
            replaced.add(key)
        else:
            output.append(line)
    output.extend(f"{key}: {value}" for key, value in ovr.items() if key not in replaced)
    return "\n".join(output)


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "Packages")
    overrides = load_overrides()
    stanzas = [stanza for stanza in path.read_text().strip().split("\n\n") if stanza]
    path.write_text("\n\n".join(map(lambda s: patch_stanza(s, overrides), stanzas)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
