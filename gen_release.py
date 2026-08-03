#!/usr/bin/env python3
"""Generate a Cydia/APT-compatible Release file with checksum sections."""

import hashlib
import os
import sys
from datetime import datetime, timezone

REPO_URL = "https://ios.slutvibe.site"

HEADER = {
    "Origin": "slutvibe Legacy Repo",
    "Label": "slutvibe Legacy Repo",
    "Suite": "stable",
    "Version": "1.0",
    "Codename": "ios",
    "Architectures": "iphoneos-arm",
    "Components": "main",
    "Description": "Curated packages for jailbroken iOS devices.",
}

INDEX_FILES = ["Packages", "Packages.gz", "Packages.bz2"]


def main() -> int:
    root = os.path.dirname(os.path.abspath(__file__))
    missing = [name for name in INDEX_FILES if not os.path.isfile(os.path.join(root, name))]
    if missing:
        print("Missing index files:", ", ".join(missing), file=sys.stderr)
        return 1

    lines = []
    for key, value in HEADER.items():
        lines.append(f"{key}: {value}")
    lines.append(f"Date: {datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S UTC')}")

    digest_sets = [
        ("MD5Sum", hashlib.md5),
        ("SHA1", hashlib.sha1),
        ("SHA256", hashlib.sha256),
    ]
    for field, digest in digest_sets:
        lines.append(f"{field}:")
        for name in INDEX_FILES:
            path = os.path.join(root, name)
            with open(path, "rb") as fh:
                data = fh.read()
            lines.append(f" {digest(data).hexdigest()} {len(data)} {name}")

    with open(os.path.join(root, "Release"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("Release written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
