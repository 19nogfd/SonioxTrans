# SonioxTrans 日文同声传译

SonioxTrans 是一个面向 macOS 的日语实时字幕工具，通过 Soniox `stt-rt-v5` 同时生成日语原文和简体中文翻译。

> **平台说明：当前正式版仅支持 Apple Silicon Mac 和 macOS 14 及以上版本，不支持 Windows、Intel Mac、iPhone 或 iPad。**

## 功能

- 麦克风日语实时识别与中文翻译
- macOS 支持通过 BlackHole 捕获系统播放音频
- 悬浮字幕和双栏翻译窗口
- 保留上下文、文本选择与复制
- 按日期保存历史记录，支持搜索、改名和导出
- 支持 Soniox 美国与日本节点
- API Key 由使用者输入，不包含在源码和安装包中

## 下载 macOS 正式版

请在仓库的 **Releases** 页面下载 `SonioxTrans.dmg`。当前版本为 `v1.0.0`，支持 Apple Silicon 和 macOS 14 及以上版本。

安装时将 `SonioxTrans.app` 拖入“应用程序”。当前个人发布包没有 Apple Developer ID 公证；如果 macOS 阻止首次启动，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。

系统音频翻译需要先安装 [BlackHole 2ch](https://existential.audio/blackhole/)，并在“音频 MIDI 设置”中创建包含“MacBook 扬声器”和“BlackHole 2ch”的多输出设备。SonioxTrans 会从 BlackHole 输入读取系统声音。

## macOS 从源码构建

要求：

- Apple Silicon Mac
- macOS 14 或更高版本
- Xcode Command Line Tools
- Python 3.11 或更高版本

```bash
git clone https://github.com/19nogfd/SonioxTrans-.git
cd SonioxTrans-
python3 -m venv .venv
.venv/bin/pip install -r requirements-build.txt
./build_backend.sh
./MacUI/build.sh
./package_dmg.sh
```

生成的应用位于 `build/SonioxTrans.app`。DMG 默认生成到 `~/Downloads/SonioxTrans.dmg`。

## API Key 与隐私

每位使用者需要使用自己的 Soniox API Key。macOS 版使用系统安全存储，iOS 版使用 Keychain 保存 Key。请勿把真实 API Key 提交到 GitHub、截图或日志中。

语音数据会发送到所选地区的 Soniox 服务进行实时识别和翻译，使用前请阅读 Soniox 的服务条款和隐私政策。

## 版本

- `v1.0.0`：首个 Soniox macOS 正式版。
