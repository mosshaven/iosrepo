# slutvibe Legacy Repo

Flat APT repository for jailbroken iOS devices, published at
`https://ios.slutvibe.site/`.

## Packages

- AppSync Unified 116.0: iOS 5.0-18.2, ARMv7/ARM64
- ldid 2.1.5-procursus7: iOS 14.0+, ARM64

Current `ldid` package does not run on 32-bit devices. Its Mach-O binary has an
`LC_BUILD_VERSION` minimum of iOS 14.0 and an ARM64-only slice.

## Add or update a package

1. Put its `.deb` in `debs/`.
2. Add an icon under `icons/`.
3. Add compatibility metadata and depiction URL in `repo_metadata.py` or
   `packages_meta.json`.
4. Add a static depiction page under `depictions/`.
5. Run `./update.sh`.
6. Check `Packages`, `Packages.gz`, `Packages.bz2`, `Release`, and `index.html`
   into Git.

`packages_meta.json` is the sidecar for automated flows (the Telegram bot). Each
entry may hold `Name`, `Depiction`, `Icon` (written into the APT index) and
`Tags` (used only on the web page). `repo_metadata.py` merges its built-in
overrides with this file; JSON wins per field.

Compatibility shown on depiction pages must match package dependencies and
Mach-O load commands. Check binaries with:

```sh
dpkg-deb -x package.deb extracted
file extracted/path/to/binary
llvm-objdump --macho --private-headers extracted/path/to/binary
```

Installation constraints belong in package `Depends`, such as
`firmware (>= 8.0)`. Avoid nonstandard compatibility tags: old Cydia versions
may filter packages carrying tags intended for newer package managers.

## Generate indexes

Requires `dpkg-scanpackages`, Python 3, gzip, and bzip2:

```sh
./update.sh
```

`update.sh` regenerates `Packages`, `Packages.gz`, `Packages.bz2`, `Release`
(with checksum sections — required by Cydia/APT on old iOS), and `index.html`.

## Telegram bot

See `bot/README.md`. Bot receives `.deb`/`.ipa`, converts/validates, updates the
repo, and pushes to Git.
