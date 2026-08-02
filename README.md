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
3. Add compatibility metadata and depiction URL in `repo_metadata.py`.
4. Add a static depiction page under `depictions/`.
5. Run `./update.sh`.
6. Check `Packages`, `Packages.gz`, and `Packages.bz2` into Git.

Compatibility shown on depiction pages must match package dependencies and
Mach-O load commands. Check binaries with:

```sh
dpkg-deb -x package.deb extracted
file extracted/path/to/binary
llvm-objdump --macho --private-headers extracted/path/to/binary
```

`Tag: compatible_min` helps package-manager presentation. Actual installation
constraints belong in package `Depends`, such as `firmware (>= 8.0)`.

## Generate indexes

Requires `dpkg-scanpackages`, Python 3, gzip, and bzip2:

```sh
./update.sh
```
