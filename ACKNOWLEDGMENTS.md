# Acknowledgments and external components

The repository contains the plugin's Objective-C/Logos implementation, build scripts, synthetic host tests, documentation, and maintainer-supplied screenshots and a screen recording demonstrating the plugin. It does not bundle Spotify, Eevee, TrollFools, Theos or an iOS SDK. Third-party UI, album artwork and incidental audio visible or audible in the demonstration media remain the property of their respective owners.

## Build tools

- [Theos](https://github.com/theos/theos) and [Logos](https://github.com/theos/logos) provide the build and hook-generation tools. Their license text explicitly distinguishes projects created with these tools from the tools' own GPL license. The tools and their source are not bundled here. See the [Theos license](https://github.com/theos/theos/blob/master/LICENSE.md) and [Logos license](https://github.com/theos/logos/blob/master/LICENSE.md).
- [L1ghtmann's LLVM toolchain](https://github.com/L1ghtmann/llvm-project) is an external compiler toolchain. Its licenses apply to that toolchain.
- [GNUstep](https://www.gnustep.org/) supports Linux host tests; it is not linked into the iOS plugin.
- UIKit, Foundation, QuartzCore, Security and other Apple system libraries are external platform dependencies. SDK redistribution is outside this repository.

## Interface research and installation

- [EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated), specifically its [Now Playing service hooks](https://github.com/SideloadLabs/EeveeSpotifyReincarnated/blob/Master/Sources/EeveeSpotify/Lyrics/NowPlayingScrollViewControllerInstanceHook.x.swift), supplied class/method names to investigate. The reference project is GPL-3.0 licensed. This repository uses separate Objective-C/Logos hooks with runtime signature checks; it does not include the reference project's Swift files, implementation library, premium-feature patches or global state. Credit for interface clues does not relicense upstream code.
- [Spicetify](https://github.com/spicetify/cli) type definitions document artist metadata keys such as `artist_name:1`, used as interface clues for reading a complete artist list. No Spicetify runtime is required or bundled.
- [TrollFools](https://github.com/Lessica/TrollFools) is the separately installed injection tool used in the tested environment. This repository does not distribute or modify it.
- [DeepSeek](https://api-docs.deepseek.com/) provides the API called with the user's own key. No DeepSeek SDK or model weights are distributed.

Only the project-owned source and documentation are covered by this repository's [MIT License](LICENSE). External projects retain their own licenses. New contributions that copy or adapt third-party implementation code must retain applicable notices and use compatible licensing.

## Independence

This is an independent community project, not an official Spotify feature, app or developer-platform integration. It is not affiliated with or endorsed by Spotify or DeepSeek. Spotify and other product names are used to identify compatibility or external services. Screenshots supplied by the maintainer may show third-party artwork and UI; those materials are not relicensed as plugin source code.
