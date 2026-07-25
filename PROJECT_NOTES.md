# FreeCommunication

FreeCommunication 是一款为 Apple Silicon Mac 开发的本地英语实时转录与中文翻译应用。项目使用 SwiftUI 构建 macOS 图形界面，后端通过 Python、MLX 和 PyTorch 在本机运行模型，音频和文字不会上传到云端。

当前保存版本：**1.3.2**

## 主要功能

- 通话模式：同时捕捉系统音频和麦克风。
- 视频模式：捕捉电脑播放的英语音频。
- 现场模式：通过麦克风进行现场转录与翻译。
- 支持正常窗口和半透明字幕窗口。
- 支持导入常见音频、视频文件，生成转录、翻译和 SRT 字幕。
- 记录可保存原始音频、英文原文和中文译文，并支持回放与文本定位。
- 默认记录目录：`~/Documents/FreeCommunication/Recordings`。

应用内置以下模型：

- ASR：Nemotron Speech Streaming EN 0.6B，MLX 8-bit。
- NMT：Helsinki-NLP OPUS-MT EN-ZH，使用 PyTorch 权重在 CPU 上翻译。

## 保存的文件

### `FreeCommunication-1.3.2.app.zip`

完整可运行版本，包含 macOS App、Python/MLX 运行环境、ASR 模型、翻译模型和 FFmpeg。解压后可将 `FreeCommunication.app` 放入“应用程序”文件夹。

该版本为本地签名而非 Apple 公证版本。在其他 Mac 上首次打开时，可能需要按住 Control 点击 App 并选择“打开”，同时授予麦克风以及屏幕与系统音频录制权限。

### `FreeCommunication-1.3.2-source.zip`

项目源码归档，包含 Swift/Python 源码、界面资源、构建脚本、锁定的 Python 依赖和便携 FFmpeg。它不单独包含完整 Python 环境和模型权重；当前模型保存在上面的 App ZIP 内。

以后需要修改功能或更换模型时，应同时保留源码 ZIP 和 App ZIP。当前模型可以从解压后的以下目录取出：

```text
FreeCommunication.app/Contents/Resources/Models/ASR
FreeCommunication.app/Contents/Resources/Models/NMT
```

## 备注

这是经过多轮实际使用和调试后保存的稳定版本。后续更新前建议保留本目录中的两个带版本号 ZIP，新的发行版本也继续采用同样的“可运行包 + 源码包”方式归档。
