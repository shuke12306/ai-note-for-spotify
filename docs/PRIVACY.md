# Privacy and data handling

This document describes the current source implementation. The plugin runs inside the Spotify application process and uses the host application's local storage and Keychain access. It is not a separate sandboxed app.

## When requests happen

Opening the guide checks the cache. Missing enabled modules are requested from DeepSeek. Returning from settings can also request modules whose language, model or prompt changed. Manual regeneration requests the selected module, or all enabled modules when explicitly chosen. Saving settings alone does not send a request. Reading a saved favorite does not send a request.

The plugin does not automatically generate guides merely because a song starts playing. A request already submitted may finish after the guide closes so its result can be cached. Failed requests are not automatically retried.

## What leaves the device

Requests go directly to `https://api.deepseek.com/chat/completions` using HTTPS. They contain the track title, available artist names and album title, selected output language, model, module writing instructions, and the common JSON/formatting instructions. The user's DeepSeek API key is sent in the Authorization header. DeepSeek can also receive normal connection metadata, such as the originating IP address.

The plugin does not attach audio, artwork, Canvas video, Spotify credentials, account details, playback history, diagnostic reports or the local Spotify track ID to this request. It does not operate a developer-hosted relay or include an analytics SDK. User-entered prompts are transmitted, so do not put private information in them.

API service terms, billing and provider-side processing are governed by the provider. Local cache deletion does not delete data held by the provider. See [DeepSeek's platform](https://platform.deepseek.com/) for the account and current service terms.

## What stays on the device

| Data | Storage and behavior |
| --- | --- |
| API key | iOS Keychain, non-synchronizing, accessible when unlocked on this device; never intentionally written into source, diagnostics or a plaintext settings file. |
| Model, language, layout, appearance and custom prompts | The host application's user defaults. |
| Generated module cache | JSON in the host application's Caches directory, up to 100 track/model/language groups and 4 MiB. Each module also has its own prompt identity. The OS may purge caches. Restarting the app alone does not clear them. |
| Favorites | Separate JSON in Application Support, up to 200 entries and 16 MiB. Includes track information and guide content; no API key or custom prompts. Clearing the cache does not remove favorites. |
| Previous module result | One level in the currently open guide panel; not a permanent revision history. |
| Diagnostic information | Prepared locally on request. Copying is explicit; reports can include track ID, track metadata, app version, class names and hook status. |

Settings and favorites are local data, not an encrypted private vault. The host app and other injected code share the process. Favorites are not a cross-device sync or backup service; uninstalling the host app or removing its data can remove them.

## Delete or share deliberately

Use settings to delete the saved API key or clear the temporary cache. Remove individual favorites from the favorites list. Removing the injected dylib stops the plugin but does not itself erase all previously stored settings, Keychain items or favorites.

Copy actions put text on the system clipboard. Before posting diagnostics or screenshots, review them for information you do not want public. Do not include API keys, authorization headers or full account screenshots in GitHub issues.

## 中文摘要

插件在 Spotify 进程内运行。只有打开导赏、从设置返回后需要补齐内容，或主动重生成时，才向 DeepSeek 发送曲名、艺术家、专辑、语言和提示词；不发送音频、封面、动态视频或 Spotify 账号凭据。API Key 直接用于 DeepSeek 请求，保存在本机 Keychain。

缓存可跨 Spotify 重启保留，但属于系统可清理的临时数据；收藏独立保存，清缓存不会删除收藏。卸载 Spotify 可能导致本地内容丢失。移除插件本身不会自动删除此前保存的全部数据。
