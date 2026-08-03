#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
rm -f Packages Packages.bz2 Packages.gz

dpkg-scanpackages -m debs /dev/null > Packages
python3 repo_metadata.py Packages
python3 gen_index.py
bzip2 -c9 Packages > Packages.bz2
gzip -cn9 Packages > Packages.gz
python3 gen_release.py

printf 'Repository updated: %s packages\n' "$(grep -c '^Package:' Packages)"
