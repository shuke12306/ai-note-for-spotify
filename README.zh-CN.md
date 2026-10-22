# AI Note for Spotify

**在 iPhone 的 Spotify 里，一边听古典乐，一边看 AI 导赏。**

看不懂冗长的曲名？点击播放页的「导赏」，就能翻译标题、了解作品背景和演奏者，不用切换应用。

[**下载插件**](https://github.com/shuke12306/ai-note-for-spotify/releases/latest) · [**实机演示视频 · MP4，65 秒**](https://github.com/shuke12306/ai-note-for-spotify/raw/refs/heads/main/media/demo.mp4) · [English](README.md)

## 实际效果

<table>
  <tr>
    <td align="center"><b>从播放页打开</b></td>
    <td align="center"><b>边听边看导赏</b></td>
  </tr>
  <tr>
    <td><img src="media/now-playing.png" width="300" alt="Spotify 播放页：封面下方是书本图标和导赏入口"></td>
    <td><img src="media/guide.png" width="300" alt="AI Note 导赏：展示勃拉姆斯交响曲的曲名、作品背景与演奏者介绍"></td>
  </tr>
</table>

## 能做什么

- **读懂音乐**：曲名翻译、标题拆解、作品背景、欣赏提示，以及演奏者或乐团介绍。
- **按喜好阅读**：模块可排序、开关、修改提示词，也能单独重新生成。
- **选择语言**：插件界面支持简体中文和英文；AI 导赏支持 10 种常用语言及自选语言。
- **留住喜欢的导赏**：本地缓存、收藏后离线阅读，以及复制分享。

<details>
<summary><b>更多截图：功能菜单与设置</b></summary>

<p>
  <img src="media/guide-actions.png" width="220" alt="导赏功能菜单：收藏、复制与重新生成">
  <img src="media/interface-settings.png" width="220" alt="界面语言、卡片亮度与模块排序设置">
  <img src="media/guide-settings.png" width="220" alt="导赏语言、模块提示词与 API Key 设置">
</p>

</details>

## 开始使用

需要 **iOS 版 Spotify、可正常使用的 TrollFools**，以及**你自己的 DeepSeek API Key**。目前实测版本为 Spotify **9.1.60（916001969）**，其他版本尚未验证。

1. 在 [Releases](https://github.com/shuke12306/ai-note-for-spotify/releases/latest) 下载 `AINote-1.1.0.dylib`，通过 TrollFools 注入。
2. 播放歌曲，进入完整播放页，点击「导赏」。
3. 在「设置」中填写 DeepSeek Key、选择导赏语言。API 用量由你的 DeepSeek 账户计费。

导赏由 AI 根据曲目信息生成，可能存在错误。请求从手机直接发送到 DeepSeek，密钥保存在本机钥匙串。本项目独立开发，与 Spotify 官方无关联。

[源码构建](docs/BUILDING.md) · [隐私说明](docs/PRIVACY.md) · [兼容性与测试](docs/TESTING.md) · [反馈问题](https://github.com/shuke12306/ai-note-for-spotify/issues) · [MIT 许可证](LICENSE) · [致谢](ACKNOWLEDGMENTS.md)
