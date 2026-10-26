# SonioxTrans for iPhone

原生 iOS 日语实时字幕应用。通过麦克风采集音频，使用 Soniox `stt-rt-v5` 同时生成日语原文与简体中文翻译。

## 功能

- 麦克风实时翻译，不采集其他 App 或系统音频
- 美国和日本 Soniox 项目地域
- API Key 保存在本机 Keychain
- 主页面双栏字幕、自动跟随、文本选择与复制
- 最终字幕按日期保存在本机，支持搜索、改名和 Markdown 导出
- 语义断句最大等待 3 秒，减少短暂停顿造成的错误分句

## 构建

1. 用 Xcode 打开 `SonioxTrans.xcodeproj`。
2. 在 Signing & Capabilities 中选择自己的 Team。
3. 连接 iPhone，选择设备后点击 Run。
4. 第一次开始翻译时允许麦克风权限。

应用不会内置 API Key。第一次输入并开始翻译时，Key 会保存到该设备的 Keychain；可在主页面清除。
