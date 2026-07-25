# Third-Party Notices

FreeCommunication's PolyForm Noncommercial license applies only to original
project code and assets for which ScorpioDai holds the necessary rights. The
following external works retain their own terms. Nothing in this repository
relicenses a model, library, system framework, name, logo, or trademark.

## External Models

Models are not stored in the Git repository, source archives, App bundle, or
DMG. FreeCommunication can download them from their publishers into the user's
Documents folder. Users are responsible for reviewing and accepting the
applicable model terms before downloading or using them.

### Nemotron Speech Streaming EN 0.6B · MLX 8-bit

- Derivative repository:
  <https://huggingface.co/animaslabs/nemotron-speech-streaming-en-0.6b-mlx-8bit>
- Base model:
  <https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b>
- Base-model terms:
  <https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/>

The derivative model card states that the weights were converted to MLX and
8-bit quantized from NVIDIA's base model, and directs users to the original
model card. At the time of review, the derivative repository metadata used
`License: other` and contained no separate LICENSE file. This project does not
claim ownership of or grant rights to those weights. Review both repositories
and obtain any clarification you require from their publishers.

Attribution for the base model:

> Licensed by NVIDIA Corporation under the NVIDIA Open Model License.

NVIDIA, Nemotron, and related marks are the property of their respective
owners. FreeCommunication is not affiliated with or endorsed by NVIDIA or
animaslabs.

### Helsinki-NLP OPUS-MT English → Chinese

- Repository: <https://huggingface.co/Helsinki-NLP/opus-mt-en-zh>
- Declared license: Apache License 2.0
- License text: <https://www.apache.org/licenses/LICENSE-2.0>

OPUS-MT, Helsinki-NLP, and related names belong to their respective owners.
FreeCommunication is not affiliated with or endorsed by the University of
Helsinki or the model maintainers.

## FFmpeg

The distributed App contains a dynamically linked, reduced FFmpeg 8.1.2 build
under the GNU Lesser General Public License version 2.1 or later.

- Source archive: <https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz>
- Build recipe: `script/build_portable_ffmpeg.sh`
- Build information: `Vendor/FFmpeg/SOURCE.txt`
- Included license text: `Vendor/FFmpeg/Licenses/FFmpeg-LGPL-2.1.txt`

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.
This project is not affiliated with or endorsed by the FFmpeg project.

## Python Runtime And Packages

The packaged App embeds a Python runtime and the packages pinned in
`Backend/requirements-lock.txt`, including MLX, MLX Audio, parakeet-mlx,
Transformers, PyTorch, SentencePiece, SafeTensors, NumPy, and their transitive
dependencies. Each package remains subject to its own license and notices.
Installed package distributions retain their metadata and license files in the
embedded environment. Package versions can be reproduced with:

```bash
./script/setup_backend.sh
```

Review package metadata and upstream repositories before redistributing a
modified binary.

## Apple Frameworks

FreeCommunication uses public macOS frameworks including SwiftUI, AppKit,
AVFoundation, ScreenCaptureKit, CoreMedia, and Accelerate. These frameworks are
provided by macOS and remain subject to Apple's terms.

Last reviewed: July 25, 2026.
