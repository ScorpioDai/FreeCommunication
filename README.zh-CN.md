<div align="center">
  <img src="Resources/AppIconSource.png" width="128" height="128" alt="FreeCommunication App 图标">
  <h1>FreeCommunication</h1>
  <p><strong>面向 Apple 芯片 Mac 的本地英文实时转录与中文翻译工具。</strong></p>
  <p>
    <a href="README.md">English</a> ·
    <strong>简体中文</strong>
  </p>
  <p>
    <img alt="版本 1.5.2" src="https://img.shields.io/badge/版本-1.5.2-1677ff">
    <img alt="macOS 14 或更高版本" src="https://img.shields.io/badge/macOS-14%2B-111111">
    <img alt="需要 Apple 芯片" src="https://img.shields.io/badge/Apple%20芯片-必须-34c759">
    <img alt="PolyForm 非商用许可" src="https://img.shields.io/badge/许可-PolyForm%20非商用-ff3b30">
  </p>
</div>

> [!IMPORTANT]
> FreeCommunication 采用
> [PolyForm Noncommercial License 1.0.0](LICENSE)，属于**源码可见的非商用软件**。
> 个人及其他符合许可的非商用用途可以使用、研究和修改；商用必须事先获得 ScorpioDai
> 的单独书面许可。由于禁止未经授权的商用，本项目不是 OSI 定义下的开源软件。

> [!NOTE]
> App、DMG 和源码仓库均不包含语音识别或翻译模型。首次使用时可由 App 从
> Hugging Face 下载，也可以手动准备模型。

## 项目简介

FreeCommunication 可以把英文语音实时转成英文文本，并在翻译开启时生成简体中文译文。
音频捕捉、语音识别、翻译、记录保存和回放全部在 Mac 本机完成。除下载 Hugging Face
模型外，App 不需要把音频或文本发送到网络服务。

![英文实时转录与中文翻译](docs/images/live-transcription.png)

### 功能概览

- 通话、视频、现场三种实时使用模式。
- 使用 Nemotron 缓存感知流式实现进行真正的增量 ASR。
- 对实时长段设置稳定上限，避免无标点语音无限累积成难以阅读的一整块。
- 录制途中可随时开关翻译，不会中断语音识别。
- 翻译模型完成预热后保持驻留，重新开启翻译无需再次加载。
- 顶部声纹显示真实音频电平，无声音时会恢复平静。
- 支持正常转录窗口和可缩放、置顶的半透明字幕窗口。
- 中文、英文界面可立即热切换，无需重启。
- 支持导入常见音频和视频，选择仅转录或转录加翻译。
- 实时记录保存 TXT 与 16 kHz WAV；导入媒体可额外生成 SRT。
- 记录回放可高亮当前文本，点击文本即可跳转到对应时间。
- 实时和历史记录均可复制原文、译文或原文加译文。
- 可在 App 内重命名、删除记录，或直接在访达中显示。

## 三种实时模式

| 模式 | 捕捉内容 | 适用场景 |
| --- | --- | --- |
| **通话模式** | 系统声音 + 麦克风 | 视频会议、在线通话 |
| **视频模式** | 仅系统声音 | 英语视频、直播、演示 |
| **现场模式** | 仅麦克风 | 面对面沟通、讲座、采访 |

![选择通话、视频或现场模式](docs/images/live-modes.png)

通话模式提供麦克风热开关。**设置 → 录制**中提供实验性的系统回声消除，默认关闭，
因为开启后可能降低麦克风灵敏度。通话时建议佩戴耳机，避免扬声器声音再次进入麦克风。
“我”“电脑音频”等标签表示声音来源，并不是模型识别出的具体说话人；当前版本不支持
说话人分离。

## 字幕模式

字幕模式会把实时转录界面变成 Dock 上方的半透明置顶长条，也能覆盖在全屏内容上。

- 拖动背景即可移动窗口。
- 可从边缘自由调整窗口尺寸。
- 鼠标移入后显示麦克风、翻译、透明度、字号和结束控制。
- 进入字幕模式后主窗口会自动隐藏；悬浮菜单中的窗口按钮可在不结束会话的情况下重新显示
  主窗口。
- 向上滚动会暂停自动跟随，重新滚到最底部后恢复。
- 中英文字号比例与正常转录模式保持一致。
- 结束实时会话时，悬浮字幕窗口也会自动关闭。

实时识别会优先把最多三个自然短句合为一段。如果模型持续输出没有标点的长文本，
FreeCommunication 仍会在稳定的 `64` 词或 `420` 字符上限处另起一段，保证最新字幕
始终可以滚动到达；这个过程不会删减转录内容。

![半透明置顶字幕模式](docs/images/subtitle-mode.png)

## 记录保存与回放

实时会话结束后，记录自动保存到：

```text
~/Documents/FreeCommunication/Recordings
```

实时记录通常采用文件夹形式：

```text
YYYY-MM-DD HH.mm.ss/
├── transcript.txt
└── audio.wav
```

记录界面支持播放/暂停、前后跳转 10 秒、拖动时间轴、自动滚动、高亮当前文本，以及
点击某段文字跳转到对应音频位置。同时支持复制、重命名、删除、在访达中显示等操作。
旧版本保存在记录目录顶层的 TXT 文件仍可以读取。

![记录库与音频文字联动回放](docs/images/records-playback.png)

## 导入音视频

打开**音视频**选项卡后，可以选择：

- **转录**：只生成英文内容。
- **转录 + 翻译**：生成中英双语 TXT 与 SRT 字幕。

后端会先使用 FFmpeg 把媒体转换为单声道 16 kHz 音频，再执行离线识别。凡是内置
FFmpeg 支持的常见音视频容器通常都可以导入。输出以源文件名为基础，在记录目录中创建
同名文件夹。

```text
源文件名称/
├── transcript.txt
└── subtitles.srt
```

SRT 会把长段文本拆成更适合观看的短字幕，并细化每条字幕的时间。导入媒体使用快速离线
转录，而不是实时会话采用的流式状态。

![导入英文音频或视频](docs/images/media-import.png)

## 运行要求

### 最低要求

- Apple 芯片 Mac。发行版不支持 Intel Mac。
- macOS 14 或更高版本。
- 建议至少预留约 5 GB 磁盘空间，用于 App、两个完整模型仓库、下载中的临时文件和
  处理文件。
- 通话模式、现场模式需要麦克风权限。
- 通话模式、视频模式需要“屏幕与系统录音”权限。
- 模型和记录位于文稿目录，因此首次使用需要授予文稿文件夹访问权限。

### 推荐环境

- 具有 16 GB 或更多统一内存的 M 系列 Mac。
- 通话模式建议佩戴耳机。
- 首次安装模型时，需要稳定访问 `huggingface.co` 及其重定向模型存储地址。

### 已测试环境

- Apple M1 Pro MacBook Pro。
- 16 GB 统一内存。
- macOS 26。
- ASR 使用 MLX/Metal，NMT 使用 CPU。

macOS 26 是当前主要实际测试系统。App 的最低部署目标为 macOS 14，但中间所有系统版本
和不同 M 系列芯片组合并未获得完全相同强度的人工测试。

## 安装 App

1. 从 [GitHub Releases](https://github.com/ScorpioDai/FreeCommunication/releases/latest)
   下载 `FreeCommunication-1.5.2.dmg`。
2. 打开 DMG。
3. 把 **FreeCommunication.app** 拖到 **Applications/应用程序**文件夹图标。
4. 推出安装镜像，从“应用程序”或启动台运行 FreeCommunication。
5. 根据计划使用的模式授予文稿、麦克风、屏幕与系统录音权限。

![把 FreeCommunication 拖到应用程序](docs/images/install-dmg.png)

当前社区发行版使用本地临时签名，尚未经过 Apple Developer ID 签名和公证。从网络下载
后首次运行时，macOS 可能显示开发者信任提示。请只在确认 DMG 来自本仓库的情况下，在
“应用程序”中按住 Control 点击 App，选择**打开**并确认。以后具备正式签名条件时会改进
这一体验。

## 安装模型

发布本版本时，两个仓库均为公开且无门槛下载，不需要 Hugging Face 账号或访问 Token。

| 用途 | 模型仓库 | 本地固定目录 | 上游许可 |
| --- | --- | --- | --- |
| 英文流式 ASR | [animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit](https://huggingface.co/animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit) | `~/Documents/AI Models/animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit` | 参见量化模型卡与 NVIDIA 原模型条款 |
| 英译中 NMT | [Helsinki-NLP/opus-mt-en-zh](https://huggingface.co/Helsinki-NLP/opus-mt-en-zh) | `~/Documents/AI Models/Helsinki-NLP:opus-mt-en-zh` | Apache 2.0 |

### 自动下载

1. 启动任意实时模式，或打开**设置 → 模型**。
2. 在缺少模型提示中选择下载。
3. 两个进度条完成前保持 App 运行。
4. 观察侧边栏底部两张模型状态卡从灰色变为黄色、再变为绿色；两个模型均显示“已就绪”
   后点击**检查后端**。

下载中断时会保留 `.part` 文件，重试后可以续传。自动下载会镜像完整仓库，因此 NMT
目录中会同时出现 PyTorch、TensorFlow、Flax、Rust 等权重；FreeCommunication 实际在
CPU 上使用 `pytorch_model.bin`。

如果下载长期为零、反复失败或无法连接，请确认当前网络能访问模型页面和重定向后的存储
地址。App 当前只支持 Hugging Face 官方源，不内置其他镜像。

### 手动下载

App 会检查固定目录，因此手动下载后必须保留上表中的精确文件夹名称。可以使用 Hugging
Face 官方命令行工具：

```bash
python3 -m pip install -U huggingface_hub

hf download animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit \
  --local-dir "$HOME/Documents/AI Models/animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit"

hf download Helsinki-NLP/opus-mt-en-zh \
  --local-dir "$HOME/Documents/AI Models/Helsinki-NLP:opus-mt-en-zh"
```

也可以用其他工具或镜像获取相同仓库，再把完整文件放入对应目录。最后在
**设置 → 模型 → 检查后端**确认必要文件和运行环境。

## 实时使用流程

1. 启动 App。已安装的 ASR 与翻译模型会自动预热，驻留完成后侧边栏状态卡变为绿色。
2. 选择通话、视频或现场模式。
3. 点击**开始**。如果预热尚未完成，App 会等待两个模型均就绪后再开始捕捉音频。
4. 录制途中可随时开关翻译。已经生成的译文会保留，新内容会在纯英文和中英双行布局间
   平滑切换。
5. 通话模式可随时开关麦克风。
6. 可以即时复制当前原文、译文或原文加译文。
7. 需要减少遮挡时进入字幕模式。
8. 点击**结束**。系统会刷新最后一段流式缓存，然后直接写入转录与音频，不会在结束后
   重新识别完整会议。

设置中的“实时分片”范围为 2 至 12 秒，主要影响音频归档和备用分片行为。流式识别器本身
会持续接收 PCM，不需要等到完整分片后才开始识别。

## 设置说明

- **通用**：简体中文与英文界面热切换。
- **模型**：查看模型名称、安装状态、下载进度、固定目录和后端健康状态。
- **录制**：快速打开记录目录、设置实时分片时长、选择是否开启实验性通话回声消除。
- **字幕**：设置正常转录和字幕模式共用的透明度与字号。

所有路径都会根据当前 macOS 账户的真实主目录生成。例如另一台 Mac 会自动显示
`/Users/alex/Documents/...`，代码没有固定写入 `scorpio-dai`。

## 隐私与数据

- 识别和翻译均在本机运行。
- FreeCommunication 不会上传捕捉到的音频和转录文本。
- 复制操作使用 macOS 系统剪贴板。
- 内置网络功能仅用于模型下载。
- 删除文件夹式记录时，其中的转录、音频和字幕会一起删除。重要会议请自行建立独立备份。

ASR 和机器翻译可能出现错误。重要姓名、数字、法律陈述、医疗信息和决策，请回看源音频
进行核对。

## 技术架构

| 层级 | 实现 |
| --- | --- |
| macOS 界面 | SwiftUI，少量 AppKit 窗口与面板互操作 |
| 系统声音捕捉 | ScreenCaptureKit |
| 麦克风与音频归档 | AVFoundation 与内置 FFmpeg |
| 流式 ASR | Python、MLX、MLX Audio、Nemotron ASR，运行于 Metal |
| 翻译 | Transformers/PyTorch OPUS-MT，运行于 CPU |
| 模型下载 | URLSession 获取清单，`/usr/bin/curl` 下载文件 |
| 记录回放 | AVPlayer 与带时间戳文本片段 |

ASR 使用 Apple GPU，NMT 放在 CPU 上，以减少实时识别期间的 GPU 带宽竞争。发行 App
内置 Python/MLX 运行环境和便携 FFmpeg，因此安装后约为 1.1 GB；模型仍然与 App 分离。

## 从源码构建

需要准备：

- 完整 Xcode 或兼容的 Swift 6 工具链。
- Python 3.10 或更高版本。
- 创建后端环境时系统可使用 FFmpeg。
- Apple 芯片 Mac。

```bash
git clone https://github.com/ScorpioDai/FreeCommunication.git
cd FreeCommunication

./script/setup_backend.sh
./script/build_and_run.sh --verify
./script/package_dmg.sh
```

生成文件：

```text
dist/FreeCommunication.app
dist/FreeCommunication-1.5.2.dmg
```

构建时会把 Python 环境和 `Vendor/FFmpeg` 复制到 App 内，但绝不会复制
`~/Documents/AI Models`。

## 测试

```bash
swift test
./script/core_logic_smoke.sh
Backend/.venv/bin/python Backend/test_backend_logic.py
Backend/.venv/bin/python script/stream_translation_smoke.py \
  --input "/path/to/english-audio-or-video"
hdiutil verify dist/FreeCommunication-1.5.2.dmg
```

`swift test` 需要带 XCTest 的 Xcode 工具链。冒烟测试覆盖模型状态、安全下载、真实声纹、
字号比例、实时段落稳定拆分和全文保留、实时翻译策略、长文本翻译拆分、流式状态以及
SRT 字幕切分和时间戳。麦克风和 ScreenCaptureKit 行为仍需人工测试，因为它们受
macOS 权限和当前音频设备影响。

## 当前限制

- 仅支持英文识别和英文到简体中文翻译。
- 不支持具体说话人分离。
- 实验性通话回声消除可能降低麦克风灵敏度。
- 公共 DMG 尚未进行 Developer ID 签名和 Apple 公证。
- 模型效果、偏差和允许用途以各上游模型条款为准。
- 不支持 Intel Mac 和 macOS 14 以前的系统。

## 参与贡献

欢迎提交非商用改进。提交 Issue 或 Pull Request 前请阅读
[CONTRIBUTING.md](CONTRIBUTING.md)。提交代码即表示你同意贡献内容按本项目现有许可
进行分发。

## 许可与第三方条款

FreeCommunication 原创源码采用
[PolyForm Noncommercial License 1.0.0](LICENSE)。该许可允许个人、教育、慈善和其他
符合条款的非商用用途。商用或商用再分发必须事先取得
[ScorpioDai](https://github.com/ScorpioDai) 的单独书面许可。

模型、FFmpeg、Python 软件包、Apple 系统框架、名称和商标不受本项目许可重新授权。
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

Copyright © 2026 ScorpioDai。
