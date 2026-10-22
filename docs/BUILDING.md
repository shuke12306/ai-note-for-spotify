# Build and verification

The development environment uses Windows PowerShell plus WSL 2 / Ubuntu. A Mac was not used for this build. The iOS artifact is built with Theos, Objective-C, UIKit and Logos's `internal` generator.

## Dependencies

Follow the [official Theos Linux/Windows guide](https://theos.dev/docs/installation-linux) to set up a Linux user environment. Obtain any SDK and toolchain under their applicable terms. They are external dependencies and are not included in this repository or source archive.

The configuration used for this release is:

| Component | Version / requirement |
| --- | --- |
| Theos | Commit `304e0799973e8145f32e4ca2de6c747a84b758ce`, including its submodules |
| Cross compiler | L1ghtmann LLVM / Clang 11.1.0, commit `210562a8907c5f1ec4a02c7ac969d26d81d304a0`, [release test-210562a](https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a) |
| iOS SDK | `iPhoneOS16.5.sdk` under `$THEOS/sdks` |
| Build target | arm64, minimum deployment target iOS 14.0 |
| Host-test dependencies | Bash, Python 3.10+, Perl, make, GCC headers and `libgnustep-base-dev` |

`THEOS` defaults to `~/theos`. The compiler is expected at `$THEOS/toolchain/linux/iphone/bin/clang`. The deployment target is a compiler setting, not a claim that every iOS 14+ device supports TrollFools or has been tested.

## Build

In PowerShell, from the project directory:

```powershell
.\build.ps1
```

If Ubuntu has a different WSL distribution name:

```powershell
.\build.ps1 -Distribution 'YourDistributionName'
```

Or, from Linux / WSL in the project directory:

```bash
bash scripts/build.sh
```

The script copies the source to a temporary directory on the Linux filesystem, builds it, checks the Mach-O structure, and places `AINote.dylib` in `dist/`. Temporary build files are removed on exit. No API key or Spotify application binary is required to compile this source.

The build uses only system framework/library dependencies in the resulting dylib. Logos `internal` generates Objective-C runtime method replacements; no additional Substrate or Substitute library is linked by this plugin.

## Run host tests

Inside Linux / WSL, from the project directory:

```bash
bash scripts/test.sh
```

Tests use synthetic input, GNUstep and narrowly scoped host doubles. They do not contact DeepSeek or spend API credit. The Security API double tests storage logic; it does not emulate iOS Keychain isolation or entitlements. UIKit layout is not emulated: the entry tests exercise the same geometry calculation against synthetic rectangles.

`scripts/verify_binary.py` checks arm64 Mach-O type, system dependencies, install name, minimum iOS target, initializer and code-signature data. It does not certify Apple distribution signing or guarantee injection acceptance.

## Release archive

After running tests and building, run `python3 scripts/package_release.py` in WSL. For 1.1.0 it creates `AINote-1.1.0-source.zip`, `AINote-1.1.0.dylib` and `SHA256SUMS.txt` under `release/v1.1.0/`. Only an explicit set of source, test, build and documentation files is included. Toolchains, SDKs, Spotify/other-plugin binaries, local rollbacks and private outreach drafts are excluded.

`AINote` is the build target; `AI Note` is the on-device name; `AI Note for Spotify` is the public project title. The `CGD` source prefix and `ClassicalGuide` storage identifiers intentionally remain unchanged for compatibility with existing preferences, Keychain items, cache and favorites.

This is a repeatable build procedure. Byte-for-byte reproducibility across machines has not been established; linker identifiers or signing metadata may differ. A device should be retested after a toolchain change or a rebuild intended for distribution.
