# Verification scope

Recorded on 2026-10-22. Keep host checks, user-reported device results and unverified environments separate.

## Version 1.1.0 interface-language update

Version 1.1.0 passed 546 host assertions (the 506 existing checks plus 40 new interface-language checks), arm64 compilation with warnings treated as errors, and Mach-O verification. The new checks cover default/corrupt preferences, persistence in a fresh process, Chinese/English status messages, late errors, unchanged request bodies and cache identities, preserved cached/generated content, and separate AI output-language settings. The UI string catalog was also checked for missing direct keys, duplicate keys and format-placeholder mismatches.

The new binary SHA-256 is `5f2419388a28d55c94b6a674c8af66647fa7b9aef149d507979fc043a3fd2878`. On 2026-10-22, the maintainer tested the English interface and reported overlapping Guide/导赏 entries. They confirmed that both ClassicalGuide and AINote were injected; after removing the legacy ClassicalGuide copy, they reported that the overlap was resolved. This is specific device feedback, not an itemized pass of every language-switch scenario. UIKit layout and visual behavior cannot be exercised by the GNUstep host tests. The user-tested 1.0.0 binary is retained locally for rollback.

For further regression coverage on the phone, switch Settings → Interface language between 简体中文 and English. Check the playback entry, guide headings, settings subpages and errors, then restart Spotify. Also check switching while a guide is generating: the response should retain the chosen guide language and original track, with no duplicate request from switching the interface. Unsaved key/model drafts should survive the switch, and the Save label should remain readable. Prompt bodies remain unchanged to preserve custom instructions and cached results.

## Host checks

The AI Note 1.0.0 source passed all 506 existing host assertions on 2026-10-22. The same suite previously passed for the 0.5.1 functional baseline:

| Area | Assertions |
| --- | ---: |
| Track-reader signatures, metadata and snapshots | 67 |
| Key settings / storage logic with a Security API double | 66 |
| Request construction, parser, errors and legacy cache | 221 |
| Module requests, persistent cache, undo, favorites and title fixtures | 70 |
| Output-language and module preferences | 44 |
| Playback-page class matching | 8 |
| Static/video entry geometry and scrolling boundaries | 19 |
| Logos hook gating and original-call preservation | 11 |

AI Note 1.0.0 arm64 compilation and Mach-O checks passed. These checks do not execute UIKit on an iPhone or exercise an actual DeepSeek response.

The source ZIP was extracted into a fresh temporary directory and successfully rebuilt with the documented external toolchain. In this environment the rebuilt dylib matched the release binary byte for byte (SHA-256 `328680902bb5ed909b9c54ec718ac793a070fb0332947ca375229398d13f1ebc`). This does not establish reproducibility across different machines or toolchains.

## Device feedback

The maintainer tested a personal iPhone environment running Spotify **9.1.60 (916001969)** with TrollFools and an existing Eevee installation. During iterative development they reported that track reading, AI guide generation, settings, module regeneration and the interface worked normally. They also reported normal operation after the 0.5.0 optimization batch and the 0.5.1 dynamic-cover entry fix.

These are manual reports from one environment, not a device-farm certification or a public compatibility matrix. The exact iPhone model, iOS version and TrollFools/Eevee version were not captured in the release test record. Do not infer them from the compiler's minimum deployment target.

Version 1.0.0 adopts the name AI Note for Spotify and the MIT license. It changes display strings, the dylib build target and packaging, while retaining the functional behavior and local storage identifiers of 0.5.1. On 2026-10-22, the maintainer reported that testing this renamed build worked normally in the existing iPhone environment. This confirms a user-reported device test of the release binary identified above; it is not a new compatibility claim for other environments. The user-tested 0.5.1 binary is retained locally as a rollback.

## Device regression checklist

The 1.0.0 feedback was an overall confirmation, not an itemized execution log for every check below. Keep this checklist for future regression testing.

- Open Spotify, play a track and open the guide. Check the displayed release name/version.
- Switch static artwork → video/Canvas → static artwork. Check entry visibility and taps.
- Close/reopen the page, scroll, pause/resume, lock/unlock and switch background/foreground. Check for duplicate or leftover entries and playback interruption.
- Enable a previously disabled module; verify that existing modules remain and only missing content is generated. Change one module prompt and repeat.
- Regenerate a module, restore the previous result, and confirm unrelated modules remain intact.
- Save a favorite, restart Spotify and read it. Clear the temporary cache and verify the favorite remains.
- Check existing injected-plugin behavior; remove this plugin and verify normal Spotify startup.

## Content-quality review

The automated fixtures protect title markers such as BWV, K./KV, Op., key and Roman-numbered movements. They cannot verify biographies, composition history or the musical truth of generated listening advice.

For a human content review, compare multiple movements and different recordings of the same work. Include BWV 988, K. 467, Op. 9, BWV 208 in an arrangement, Op. 67, BWV 1043 and RV 93. Verify performers against the actual recording's credits and assess the suggestions while listening. No paid model evaluation or authoritative fact-checking corpus was run as part of the host tests.

## Report a problem

Include plugin version, Spotify version/build, iOS version, the reproduction steps, static/video cover mode, expected behavior and actual behavior. If needed, use Settings → Diagnostics and copy the report after reviewing it. Never attach an API key, IPA or full network trace.
