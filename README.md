# AI Note for Spotify

[简体中文](README.zh-CN.md) · [Download v1.1.0](https://github.com/shuke12306/ai-note-for-spotify/releases/tag/v1.1.0) · [Report an issue](https://github.com/shuke12306/ai-note-for-spotify/issues)

Understand the work you are listening to without leaving Spotify's Now Playing page. AI Note explains long classical titles, catalogue numbers, movements, performers and musical context using your own DeepSeek API key.

**Version 1.1.0 · MIT license.** AI Note is the new name for ClassicalGuide. Version 1.1.0 adds English and Simplified Chinese interface settings, independently of the AI guide language. Host checks and arm64 compilation passed. Device feedback from the maintainer's Spotify 9.1.60 environment is recorded separately from automated checks. See [verification scope](docs/TESTING.md).

This is an independent iOS plugin injected through TrollFools. It is not an official Spotify feature or Spotify Web API integration. It does not include Spotify, other plugins or premium-feature modifications.

## Features

- A discreet book icon and guide entry on the full Now Playing page, with placement for static artwork and video/Canvas layouts.
- Five AI modules: translated title, title breakdown, work background, listening tips, and performer/ensemble introduction. Original track information remains available for comparison.
- English and Simplified Chinese interface settings, applied immediately and saved across restarts. The initial interface remains Simplified Chinese.
- Ten preset AI output languages and a custom language option, independent of interface language. Switching the interface does not regenerate content or invalidate cached results. Prompt text and generated content keep their original language.
- Reorder or hide modules; edit each module's prompt; regenerate one module and restore its previous result while the panel remains open.
- Generate only enabled modules that lack a matching cache. Changing one module's prompt invalidates that module, while other matching results remain usable.
- Persistent local cache, saved favorites for offline reading, and copy actions.
- A background drawn from the playback page's color, adjustable card brightness, and readable navigation controls.

Generated text is based on title, artist and album metadata. It is not independently fact-checked, does not analyze the audio, and may contain errors. Prompts ask the model to omit unsupported claims; this does not guarantee factual accuracy.

## Compatibility

| Item | Status |
| --- | --- |
| Spotify | Manually tested on **9.1.60, build 916001969** |
| Injection | TrollFools in the maintainer's existing working environment |
| Existing Eevee installation | User-reported coexistence in that environment; not a dependency |
| Architecture | arm64; minimum compiler deployment target iOS 14.0 |
| Other app/device versions | Not verified; the deployment target is not an installation compatibility guarantee |
| AI service | Your own DeepSeek account/key; configurable model, default `deepseek-flash` |

The exact phone model and iOS/TrollFools/Eevee versions were not captured in the release test record. See [verification scope](docs/TESTING.md). Runtime checks disable unsupported entry points instead of calling guessed private methods. A Spotify update can require a new adapter.

## Use

You need a device on which TrollFools already works with Spotify. This project does not provide a Spotify IPA or instructions for changing your device's installation eligibility.

1. Fully close Spotify. Inject one copy of the AI Note dylib using TrollFools. When updating from ClassicalGuide, remove its injected copy before adding AI Note; do not load both names together. Loading both copies can produce overlapping Chinese/English guide entries. Existing storage identifiers are retained for settings, keys, prompts, cache and favorites.
2. Open Spotify, play a track, and open the full Now Playing page. Tap the book/guide entry.
3. In Settings, enter your own DeepSeek API key, select a model and guide language, and adjust modules as desired.
4. Opening or returning to the guide automatically requests missing enabled content when a key is configured. Usage is charged to your own DeepSeek account.
5. Use a module's small refresh icon to regenerate it. The guide's More menu includes favorites, copy and other actions.

The panel stays bound to the track captured when it was opened. Reopen it or explicitly read the current track after switching songs. The plugin does not generate a guide merely because playback advances.

To remove it, fully close Spotify and remove this plugin with TrollFools. Removing the dylib does not automatically erase stored preferences, Keychain items or favorites.

## Privacy and local storage

Requests go directly from the phone to DeepSeek over HTTPS. The request includes track title, artist names, album, selected language/model and prompts. It does not include audio, cover/video data, Spotify account credentials or the local track ID. There is no developer-hosted relay or analytics SDK.

The API key is stored in the device's Keychain. Cache data survives an ordinary app restart but can be purged by the OS: the module cache is limited to 100 track/model/language groups and 4 MiB. Favorites are stored separately, up to 200 entries and 16 MiB; clearing the cache does not remove them. Uninstalling Spotify can remove local data.

The plugin shares Spotify's process and storage context with the host and other injected code. Read the [privacy details](docs/PRIVACY.md) before configuring a key or publishing diagnostics.

## Build and verify

The existing build workflow uses Windows plus WSL 2 / Ubuntu, Theos, an iOS cross compiler and an externally obtained SDK. No Mac was used for the current build.

```powershell
.\build.ps1
```

In Linux/WSL, from the source directory:

```bash
bash scripts/test.sh
bash scripts/build.sh
```

See [build dependencies and versions](docs/BUILDING.md). Version 1.1.0 passed 546 host assertions plus arm64 compilation and Mach-O checks. Host tests do not replace iPhone testing or verify model-generated historical claims.

## Contributing and reporting issues

Report the plugin version, Spotify version/build, iOS version, cover mode and reproduction steps. Include a reviewed diagnostic report if useful; never attach an API key, IPA or full account/network dump. The issue template includes these fields.

Keep private-interface changes guarded by runtime signature checks. Preserve original hook calls and local-data compatibility. Include applicable notices when incorporating third-party implementation code.

## License and credits

Project-owned code and documentation are distributed under the [MIT License](LICENSE). External dependencies retain their own terms; see [acknowledgments](ACKNOWLEDGMENTS.md).

Screenshots will be supplied by the maintainer from actual device use. None are generated or included in the initial source archive.
