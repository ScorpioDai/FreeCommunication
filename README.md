# FreeCommunication

FreeCommunication is a local-first macOS app for real-time English
transcription and English-to-Chinese translation.

Current version: **1.5.1**

## Features

- Call mode captures system audio and the microphone.
- Video mode captures system audio only.
- Field mode captures the microphone only.
- Translation can be turned on or off during any live session without
  restarting ASR. The translation model remains loaded for instant resumption.
- Live waveforms reflect the captured PCM level and settle when audio is silent.
- The interface defaults to Simplified Chinese and can switch between Chinese
  and English immediately without restarting the app.
- A resizable floating subtitle window supports opacity and font-size controls.
- Imported audio and video can be transcribed, or transcribed and translated.
- Recordings include searchable text, audio playback, and SRT subtitles where
  available.

## Models

Models are not bundled in the app or source repository. On first launch,
FreeCommunication can download both public repositories from Hugging Face
without an account or access token.

- [animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit](https://huggingface.co/animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit)
- [Helsinki-NLP/opus-mt-en-zh](https://huggingface.co/Helsinki-NLP/opus-mt-en-zh)

The fixed local directories are:

```text
~/Documents/AI Models/animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit
~/Documents/AI Models/Helsinki-NLP:opus-mt-en-zh
```

Manual downloads must use these folder names. The app downloads complete model
repositories. In the NMT repository, inference currently uses the PyTorch
weights (`pytorch_model.bin`); the TensorFlow, Flax, and Rust weights are kept
only because the downloader mirrors the complete repository.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Microphone permission for Call and Field modes
- Screen & System Audio Recording permission for Call and Video modes

## Build

Install the backend environment once:

```bash
./script/setup_backend.sh
```

Build and launch the release app:

```bash
./script/build_and_run.sh
```

Create the drag-to-Applications disk image:

```bash
./script/package_dmg.sh
```

The app is staged at `dist/FreeCommunication.app`. The build embeds the local
Python/MLX runtime and the vendored FFmpeg binary, but never copies model files.
Model downloading uses native macOS networking and `/usr/bin/curl`, so
`huggingface_hub` is not a runtime dependency.

## Records

Live and imported-media records are stored under:

```text
~/Documents/FreeCommunication/Recordings
```

Folder-backed records contain `transcript.txt`, `audio.wav`, and
`subtitles.srt` when subtitle output is available. Older top-level text records
remain readable.

See `ARCHIVING.md` for release preservation and distribution notes.
