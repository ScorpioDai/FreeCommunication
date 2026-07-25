# Contributing

Thank you for improving FreeCommunication.

## Before You Start

- Use an Apple Silicon Mac and macOS 14 or newer.
- Install a Swift 6/Xcode toolchain, Python 3.10 or newer, and FFmpeg.
- Read `README.md`, `LICENSE`, and `THIRD_PARTY_NOTICES.md`.
- Do not commit model weights, `Backend/.venv`, build products, recordings,
  credentials, personal audio, or other people's private transcripts.
- Keep contributions within noncommercial purposes allowed by the project
  license unless you have separate written permission.

## Setup

```bash
./script/setup_backend.sh
swift build
```

Models remain external. Follow the README model instructions if live or
imported-media testing is required.

## Pull Requests

- Keep each change focused and explain its user-facing behavior.
- Follow the existing SwiftUI, AppKit, and Python structure.
- Add or update focused tests for changed shared logic.
- Preserve local-only processing and explicit macOS permission handling.
- Document any new network behavior, saved file, model, or third-party
  dependency.
- Confirm that no user-specific absolute path is hard-coded.

## Verification

Run the checks relevant to your change:

```bash
swift test
./script/core_logic_smoke.sh
Backend/.venv/bin/python Backend/test_backend_logic.py
Backend/.venv/bin/python script/stream_translation_smoke.py \
  --input "/path/to/english-audio-or-video"
./script/build_and_run.sh --verify
./script/package_dmg.sh
hdiutil verify dist/FreeCommunication-1.5.2.dmg
```

Microphone, system-audio, subtitle-window, and macOS permission workflows
require manual testing on a real Mac.

## Contribution Terms

By submitting a contribution, you represent that you have the right to provide
it and agree that it may be distributed under the current FreeCommunication
license. Do not submit code or assets whose licenses are incompatible with this
repository or the intended binary distribution.
