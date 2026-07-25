# FreeCommunication Project Notes

FreeCommunication is a local-first macOS application for real-time English
speech recognition and optional Simplified Chinese translation. The macOS UI is
written in SwiftUI with narrow AppKit interop. Python, MLX, MLX Audio, PyTorch,
and Transformers provide local inference.

Current preserved version: **1.5.2**

## Release Shape

- `dist/FreeCommunication.app` embeds the Python/MLX runtime and portable FFmpeg.
- `dist/FreeCommunication-1.5.2.dmg` is the drag-to-Applications installer.
- ASR and NMT model weights are intentionally excluded from both artifacts.
- The Git repository is the authoritative source archive.

## External Models

```text
~/Documents/AI Models/animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit
~/Documents/AI Models/Helsinki-NLP:opus-mt-en-zh
```

The first model provides streaming English ASR on MLX/Metal. The second provides
English-to-Chinese translation through PyTorch on CPU.

Live streaming prefers sentence boundaries and applies stable 36-word or
240-character paragraph caps when punctuation is absent. Ending a live session
also closes the floating subtitle window.

## User Data

```text
~/Documents/FreeCommunication/Recordings
```

Completed live sessions use folder-backed records containing `transcript.txt`
and archived `audio.wav`. Imported translated media can also contain
`subtitles.srt`.

## Preservation

Keep the Git repository, the matching release DMG, and release checksums.
Generated `.build`, `Backend/.venv`, and `dist` contents can be recreated. Model
folders may be retained to avoid re-downloading them but are not source code.

See `README.md`, `README.zh-CN.md`, `ARCHIVING.md`, and
`THIRD_PARTY_NOTICES.md` for full details.
