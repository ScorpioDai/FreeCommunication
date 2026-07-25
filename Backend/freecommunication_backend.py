#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
import time
import wave
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


ASR_MODEL = None
ASR_MODEL_PATH: Optional[Path] = None
NMT_MODEL = None
NMT_TOKENIZER = None
NMT_MODEL_PATH: Optional[Path] = None
NMT_TRANSLATION_CACHE: Dict[tuple[str, str], str] = {}
STREAM_SESSIONS: Dict[str, Dict[str, "StreamingASRSession"]] = {}


@dataclass
class Segment:
    channel: str
    speaker: str
    start: float
    end: Optional[float]
    source_text: str
    translated_text: str = ""

    def to_json(self) -> Dict[str, Any]:
        return {
            "channel": self.channel,
            "speaker": self.speaker,
            "start": self.start,
            "end": self.end,
            "source_text": self.source_text,
            "translated_text": self.translated_text,
        }


def emit(payload: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ok(request_id: Optional[str], **payload: Any) -> Dict[str, Any]:
    result = {"id": request_id, "ok": True}
    result.update(payload)
    return result


def fail(request_id: Optional[str], error: str) -> Dict[str, Any]:
    return {"id": request_id, "ok": False, "error": error}


def truthy(value: str | bool | None, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return value.lower() in {"1", "true", "yes", "y", "on"}


def require_path(path: str, label: str) -> Path:
    if not path:
        raise RuntimeError(f"{label} path is empty")
    resolved = Path(path).expanduser()
    if not resolved.exists():
        raise RuntimeError(f"{label} path does not exist: {resolved}")
    return resolved


def check_model_files(model_dir: Path, filenames: Iterable[str]) -> List[str]:
    missing = []
    for name in filenames:
        if not (model_dir / name).exists():
            missing.append(name)
    return missing


def resolve_ffmpeg() -> Optional[str]:
    bundled = os.environ.get("FREECOMMUNICATION_FFMPEG")
    if bundled:
        path = Path(bundled).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    found = shutil.which("ffmpeg")
    if found:
        return found
    for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]:
        path = Path(candidate)
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return None


def wav_duration(path: Path) -> float:
    try:
        with wave.open(str(path), "rb") as handle:
            frame_count = handle.getnframes()
            frame_rate = handle.getframerate()
            if frame_rate <= 0:
                return 0.0
            return frame_count / frame_rate
    except (wave.Error, OSError, EOFError):
        return 0.0


def handle_check(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    warnings: List[str] = []
    asr_dir = require_path(payload.get("asr_model", ""), "ASR model")
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")

    missing_asr = check_model_files(
        asr_dir,
        ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"],
    )
    if missing_asr:
        raise RuntimeError("ASR model is missing: " + ", ".join(missing_asr))

    missing_nmt = check_model_files(
        nmt_dir,
        ["config.json", "pytorch_model.bin", "source.spm", "target.spm", "vocab.json"],
    )
    if missing_nmt:
        raise RuntimeError("NMT model is missing: " + ", ".join(missing_nmt))

    if resolve_ffmpeg() is None:
        warnings.append("ffmpeg was not found. Install it with Homebrew before processing media files.")

    for module in ["mlx", "parakeet_mlx", "mlx_audio", "transformers", "sentencepiece", "torch", "safetensors"]:
        if importlib.util.find_spec(module) is None:
            warnings.append(f"Python dependency missing: {module}")

    message = "ASR/NMT model directories look valid."
    if warnings:
        message += " Install backend dependencies before live inference."
    return ok(request_id, message=message, warnings=warnings)


def patch_tokenizer_paths(config: Dict[str, Any], model_dir: Path) -> Dict[str, Any]:
    tokenizer = dict(config.get("tokenizer", {}))
    tokenizer["model_path"] = str(model_dir / "tokenizer.model")
    tokenizer["vocab_path"] = str(model_dir / "vocab.txt")
    tokenizer["spe_tokenizer_vocab"] = str(model_dir / "tokenizer.vocab")
    config = dict(config)
    config["tokenizer"] = tokenizer
    encoder = dict(config.get("encoder", {}))
    context = encoder.get("att_context_size")
    if (
        isinstance(context, list)
        and context
        and isinstance(context[0], list)
        and len(context[0]) >= 2
    ):
        encoder["att_context_size"] = context[0]
    config["encoder"] = encoder
    return config


def load_asr_model(model_dir: Path):
    global ASR_MODEL, ASR_MODEL_PATH
    if ASR_MODEL is not None and ASR_MODEL_PATH == model_dir:
        return ASR_MODEL

    with (model_dir / "config.json").open("r", encoding="utf-8") as handle:
        raw_config = json.load(handle)

    encoder = raw_config.get("encoder", {})
    if encoder.get("subsampling") == "dw_striding" and encoder.get("causal_downsampling") is True:
        ASR_MODEL = load_nemotron_causal_quantized(model_dir, raw_config)
        ASR_MODEL_PATH = model_dir
        return ASR_MODEL

    # Prefer the public parakeet-mlx API when it accepts a local model path.
    first_error: Optional[BaseException] = None
    try:
        import parakeet_mlx

        if hasattr(parakeet_mlx, "from_pretrained"):
            ASR_MODEL = parakeet_mlx.from_pretrained(str(model_dir))
            ASR_MODEL_PATH = model_dir
            return ASR_MODEL
    except BaseException as exc:  # noqa: BLE001
        first_error = exc

    try:
        import mlx.nn as nn
        from parakeet_mlx.utils import from_config

        config = patch_tokenizer_paths(raw_config, model_dir)

        model = from_config(config)
        quantization = config.get("quantization")
        if quantization:
            nn.quantize(
                model,
                bits=quantization.get("bits", 8),
                group_size=quantization.get("group_size", 64),
            )
        model.load_weights(str(model_dir / "model.safetensors"))
        ASR_MODEL = model
        ASR_MODEL_PATH = model_dir
        return model
    except BaseException as exc:  # noqa: BLE001
        if first_error is not None:
            raise RuntimeError(f"ASR load failed: {first_error}; fallback failed: {exc}") from exc
        raise


def load_nemotron_causal_quantized(model_dir: Path, config: Dict[str, Any]):
    import mlx.core as mx
    import mlx.nn as nn
    from mlx_audio.stt.models.nemotron_asr import Model, ModelConfig
    from mlx_audio.utils import apply_quantization, load_weights

    config = dict(config)
    config["model_type"] = "nemotron_asr"
    config["vocabulary"] = config.get("vocabulary") or config.get("joint", {}).get("vocabulary", [])
    config["prompt"] = {
        "num_prompts": 0,
        "prompt_hidden": config.get("encoder", {}).get("d_model", 1024) * 2,
        "prompt_dictionary": {},
    }
    config["default_language"] = "en"
    context = config.get("encoder", {}).get("att_context_size")
    if (
        isinstance(context, list)
        and context
        and isinstance(context[0], list)
        and len(context[0]) >= 2
    ):
        config["default_att_context_size"] = context[0]
    else:
        config["default_att_context_size"] = [70, 13]

    model = Model(ModelConfig.from_dict(config))
    model.apply_prompt = lambda encoded, language=None: encoded

    quantization = config.get("quantization", {})
    bits = quantization.get("bits", 8)
    group_size = quantization.get("group_size", 64)
    d_model = config.get("encoder", {}).get("d_model", 1024)
    for layer in model.encoder.layers:
        layer.conv.pointwise_conv1 = nn.QuantizedLinear(
            d_model,
            d_model * 2,
            bias=False,
            group_size=group_size,
            bits=bits,
        )
        layer.conv.pointwise_conv2 = nn.QuantizedLinear(
            d_model,
            d_model,
            bias=False,
            group_size=group_size,
            bits=bits,
        )

    weights = load_weights(model_dir)
    apply_quantization(model, config, weights)
    model.load_weights(list(weights.items()), strict=False)
    mx.eval(model.parameters())
    model.eval()
    model.freecommunication_att_context_size = config["default_att_context_size"]
    return model


def load_nmt_model(model_dir: Path):
    global NMT_MODEL, NMT_TOKENIZER, NMT_MODEL_PATH
    if NMT_MODEL is not None and NMT_TOKENIZER is not None and NMT_MODEL_PATH == model_dir:
        return NMT_TOKENIZER, NMT_MODEL

    os.environ["CUDA_VISIBLE_DEVICES"] = ""
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    import torch
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    torch.set_num_threads(max(1, min(6, os.cpu_count() or 2)))
    tokenizer = AutoTokenizer.from_pretrained(str(model_dir), local_files_only=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(str(model_dir), local_files_only=True)
    model.to("cpu")
    model.eval()

    NMT_TOKENIZER = tokenizer
    NMT_MODEL = model
    NMT_MODEL_PATH = model_dir
    return tokenizer, model


def run_ffmpeg_to_wav(input_path: Path, wav_path: Path) -> None:
    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required but was not found.")
    command = [
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(input_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        str(wav_path),
    ]
    subprocess.run(command, check=True)


def run_ffmpeg_concat_to_wav(input_paths: List[Path], wav_path: Path, list_path: Path) -> None:
    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required but was not found.")
    if not input_paths:
        raise RuntimeError("No input chunks were provided.")
    lines = []
    for path in input_paths:
        if not path.exists():
            raise RuntimeError(f"Input chunk does not exist: {path}")
        escaped = str(path).replace("'", "'\\''")
        lines.append(f"file '{escaped}'")
    list_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    command = [
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(list_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        str(wav_path),
    ]
    subprocess.run(command, check=True)


def split_wav(wav_path: Path, output_dir: Path, segment_seconds: float = 30.0) -> List[Path]:
    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required but was not found.")
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = output_dir / "chunk-%05d.wav"
    command = [
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(wav_path),
        "-f",
        "segment",
        "-segment_time",
        f"{segment_seconds:.3f}",
        "-reset_timestamps",
        "1",
        "-acodec",
        "pcm_s16le",
        str(pattern),
    ]
    subprocess.run(command, check=True)
    return sorted(output_dir.glob("chunk-*.wav"))


def split_wav_windows(
    wav_path: Path,
    output_dir: Path,
    duration: float,
    step_seconds: float = 45.0,
    overlap_seconds: float = 10.0,
) -> List[tuple[Path, float, float, float]]:
    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required but was not found.")
    output_dir.mkdir(parents=True, exist_ok=True)
    windows: List[tuple[Path, float, float, float]] = []
    cursor = 0.0
    index = 0
    while cursor < duration:
        keep_start = cursor
        keep_end = min(duration, cursor + step_seconds)
        chunk_start = max(0.0, keep_start - overlap_seconds)
        chunk_end = min(duration, keep_end + overlap_seconds)
        chunk_duration = max(0.0, chunk_end - chunk_start)
        if chunk_duration < 0.35:
            break
        chunk_path = output_dir / f"chunk-{index:05d}.wav"
        command = [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            f"{chunk_start:.3f}",
            "-t",
            f"{chunk_duration:.3f}",
            "-i",
            str(wav_path),
            "-ac",
            "1",
            "-ar",
            "16000",
            "-acodec",
            "pcm_s16le",
            str(chunk_path),
        ]
        subprocess.run(command, check=True)
        windows.append((chunk_path, chunk_start, keep_start, keep_end))
        if keep_end >= duration:
            break
        cursor += step_seconds
        index += 1
    return windows


def sentence_split(text: str) -> List[str]:
    compact = re.sub(r"\s+", " ", text).strip()
    if not compact:
        return []
    parts = re.split(r"(?<=[.!?])\s+", compact)
    return [part.strip() for part in parts if part.strip()]


def word_count(text: str) -> int:
    return len(re.findall(r"\S+", text))


def has_terminal_punctuation(text: str) -> bool:
    return text.strip().endswith((".", "!", "?", "。", "！", "？", "..."))


def join_source_text(left: str, right: str) -> str:
    left = re.sub(r"\s+", " ", left).strip()
    right = re.sub(r"\s+", " ", right).strip()
    if not left:
        return right
    if not right:
        return left
    return f"{left} {right}"


def coalesce_segments(
    segments: List[Segment],
    max_words: int = 46,
    max_duration: float = 18.0,
    max_gap: float = 0.85,
) -> List[Segment]:
    if not segments:
        return []

    merged: List[Segment] = []
    for segment in sorted(segments, key=lambda item: (item.start, item.end or item.start)):
        text = re.sub(r"\s+", " ", segment.source_text).strip()
        if not text:
            continue
        segment.source_text = text
        if not merged:
            merged.append(segment)
            continue

        previous = merged[-1]
        previous_end = previous.end if previous.end is not None else previous.start
        next_end = segment.end if segment.end is not None else segment.start
        gap = segment.start - previous_end
        combined_words = word_count(previous.source_text) + word_count(segment.source_text)
        combined_duration = max(next_end, previous_end) - previous.start
        short_previous = word_count(previous.source_text) <= 5
        short_next = word_count(segment.source_text) <= 5
        should_merge = (
            previous.channel == segment.channel
            and previous.speaker == segment.speaker
            and gap <= max_gap
            and combined_words <= max_words
            and combined_duration <= max_duration
            and (
                gap <= 0.2
                or not has_terminal_punctuation(previous.source_text)
                or short_previous
                or short_next
            )
        )

        if should_merge:
            previous.end = max(previous_end, next_end)
            previous.source_text = join_source_text(previous.source_text, segment.source_text)
        else:
            merged.append(segment)
    return merged


def split_stream_segments(
    segments: List[Segment],
    max_words: int = 36,
    max_chars: int = 240,
    natural_break_min_words: int = 12,
) -> List[Segment]:
    split: List[Segment] = []
    terminal_pattern = re.compile(r"[.!?。！？](?:[\"')\]}]+)?$")

    for segment in segments:
        compact = re.sub(r"\s+", " ", segment.source_text).strip()
        words = compact.split()
        if not words:
            continue
        if len(words) <= max_words and len(compact) <= max_chars:
            segment.source_text = compact
            split.append(segment)
            continue

        boundaries: List[tuple[int, int]] = []
        cursor = 0
        while cursor < len(words):
            hard_end = min(cursor + max_words, len(words))
            char_count = 0
            char_end = cursor
            for index in range(cursor, hard_end):
                addition = len(words[index]) + (1 if index > cursor else 0)
                if index > cursor and char_count + addition > max_chars:
                    break
                char_count += addition
                char_end = index + 1
            hard_end = max(cursor + 1, char_end)

            if hard_end < len(words):
                search_start = min(cursor + natural_break_min_words, hard_end)
                natural_ends = [
                    index + 1
                    for index in range(search_start - 1, hard_end)
                    if terminal_pattern.search(words[index])
                ]
                if natural_ends:
                    hard_end = natural_ends[-1]

            boundaries.append((cursor, hard_end))
            cursor = hard_end

        original_end = segment.end
        duration = max(0.0, (original_end or segment.start) - segment.start)
        total_words = len(words)
        for start_index, end_index in boundaries:
            start_fraction = start_index / total_words
            end_fraction = end_index / total_words
            chunk_start = segment.start + duration * start_fraction
            chunk_end = segment.start + duration * end_fraction if original_end is not None else None
            split.append(
                Segment(
                    channel=segment.channel,
                    speaker=segment.speaker,
                    start=chunk_start,
                    end=chunk_end,
                    source_text=" ".join(words[start_index:end_index]),
                )
            )

    return split


class StreamingASRSession:
    def __init__(self, model: Any, channel: str, offset: float):
        self.model = model
        self.channel = channel
        self.offset = offset
        self.audio_parts: List[Any] = []
        self.total_samples = 0
        self.consumed = 0
        self.emitted = 0
        self.attn_cache: List[Any] = [None] * len(model.encoder.layers)
        self.conv_cache: List[Any] = [None] * len(model.encoder.layers)
        self.mel_cache = None
        self.last_token = model.blank_id
        self.decoder_hidden = None
        self.hypothesis: List[Any] = []
        self.global_time = 0
        self.translation_cache: Dict[str, str] = {}
        self.last_partial_translation_at = 0.0
        self.last_partial_translation_word_count = 0
        self.last_partial_translation_text = ""

    def append_pcm_f32(self, pcm_bytes: bytes, final: bool) -> List[Segment]:
        import mlx.core as mx
        import numpy as np
        from mlx_audio.stt.models.nemotron_asr.audio import log_mel_spectrogram

        if pcm_bytes:
            samples = np.frombuffer(pcm_bytes, dtype="<f4").astype(np.float32, copy=False)
            if samples.size:
                self.audio_parts.append(samples.copy())
                self.total_samples += int(samples.size)

        n_fft = int(getattr(self.model.preprocessor_config, "n_fft", 512))
        if self.total_samples < n_fft and not final:
            return []

        if not self.audio_parts:
            return self.current_segments()

        audio_np = np.concatenate(self.audio_parts)
        if audio_np.size < n_fft:
            return self.current_segments()

        audio_data = mx.array(audio_np, dtype=mx.float32)
        mel = log_mel_spectrogram(audio_data, self.model.preprocessor_config)
        self.consume_mel(mel, final=final)
        return self.current_segments()

    def consume_mel(self, mel: Any, final: bool) -> None:
        import mlx.core as mx
        import mlx.nn as nn
        from mlx_audio.stt.models.nemotron_asr.streaming import (
            _PRE_ENCODE_MEL_CACHE,
            _stream_block,
        )

        enc = self.model.encoder
        acs = getattr(self.model, "freecommunication_att_context_size", None) or self.model.default_att_context_size
        left_cache = int(acs[0])
        right = int(acs[1])
        chunk_frames = max(4, right + 1)
        sf = enc.args.subsampling_factor
        chunk_mel = chunk_frames * sf
        conv_left = enc.args.conv_kernel_size - 1
        if mel.ndim == 2:
            mel = mx.expand_dims(mel, 0)

        total = mel.shape[1]
        stable_total = total if final else max(0, total - 2)
        while self.consumed < stable_total:
            remaining = stable_total - self.consumed
            if not final and remaining < chunk_mel:
                break

            take = min(chunk_mel, total - self.consumed)
            m = mel[:, self.consumed : self.consumed + take]
            cache_len = 0 if self.mel_cache is None else self.mel_cache.shape[1]
            win = m if self.mel_cache is None else mx.concatenate([self.mel_cache, m], axis=1)
            win_len = win.shape[1]
            sub = enc.pre_encode(win, mx.array([win_len], dtype=mx.int32))[0]

            end = self.consumed + m.shape[1]
            is_final = final and end >= total
            base = (self.consumed - cache_len) // sf
            lo = self.emitted - base
            hi = sub.shape[1] if is_final else (end // sf - base)
            self.consumed = end
            self.mel_cache = win[:, -_PRE_ENCODE_MEL_CACHE:]

            if hi <= lo:
                self.emitted = base + max(lo, hi)
                continue
            self.emitted = base + hi
            h = sub[:, lo:hi]
            for index, block in enumerate(enc.layers):
                h, self.attn_cache[index], self.conv_cache[index] = _stream_block(
                    block,
                    h,
                    enc.pos_enc,
                    self.attn_cache[index],
                    self.conv_cache[index],
                    left_cache,
                    conv_left,
                )
            prompted = self.model.apply_prompt(h, self.model.default_language)
            mx.eval(prompted)
            self.decode_prompted(prompted)

    def decode_prompted(self, prompted: Any) -> None:
        import mlx.core as mx
        from mlx_audio.stt.models.nemotron_asr import tokenizer as tok
        from mlx_audio.stt.models.nemo.alignment import AlignedToken

        frame_sec = (
            self.model.encoder_config.subsampling_factor
            * self.model.preprocessor_config.hop_length
            / self.model.preprocessor_config.sample_rate
        )
        chunk_len = prompted.shape[1]
        time_index = 0
        new_symbols = 0
        while time_index < chunk_len:
            feature = prompted[:, time_index : time_index + 1]
            current_token = (
                mx.array([[self.last_token]], dtype=mx.int32)
                if self.last_token != self.model.blank_id
                else None
            )
            decoder_output, (h, c) = self.model.decoder(current_token, self.decoder_hidden)
            decoder_output = decoder_output.astype(feature.dtype)
            proposed_hidden = (h.astype(feature.dtype), c.astype(feature.dtype))
            joint_output = self.model.joint(feature, decoder_output)
            pred_token = int(mx.argmax(joint_output))
            if pred_token != self.model.blank_id:
                self.last_token = pred_token
                self.decoder_hidden = proposed_hidden
                if not tok.is_special_token(self.last_token, self.model.vocabulary):
                    self.hypothesis.append(
                        AlignedToken(
                            self.last_token,
                            start=(self.global_time + time_index) * frame_sec,
                            duration=frame_sec,
                            text=tok.decode([self.last_token], self.model.vocabulary),
                        )
                    )
                new_symbols += 1
                if self.model.max_symbols is not None and new_symbols >= self.model.max_symbols:
                    time_index += 1
                    new_symbols = 0
            else:
                time_index += 1
                new_symbols = 0
        self.global_time += chunk_len

    def current_segments(self) -> List[Segment]:
        from mlx_audio.stt.models.nemo.alignment import sentences_to_result, tokens_to_sentences

        result = sentences_to_result(tokens_to_sentences(self.hypothesis))
        return split_stream_segments(
            result_segments(result, channel=self.channel, offset=self.offset)
        )

    def translate_stable_segments(self, segments: List[Segment], model_dir: Path, final: bool) -> None:
        now = time.monotonic()
        allow_partial_translation = final or now - self.last_partial_translation_at >= 2.4
        candidates: List[Segment] = []
        for index, segment in enumerate(segments):
            text = segment.source_text.strip()
            if not text:
                continue
            is_last = index == len(segments) - 1
            current_word_count = word_count(text)
            if is_last and self.last_partial_translation_text:
                stable_prefix = self.last_partial_translation_text[: min(80, len(self.last_partial_translation_text))]
                if current_word_count + 3 < self.last_partial_translation_word_count or not text.startswith(stable_prefix):
                    self.last_partial_translation_word_count = 0
                    self.last_partial_translation_text = ""
            partial_ready = (
                is_last
                and current_word_count >= 7
                and allow_partial_translation
                and current_word_count >= self.last_partial_translation_word_count + 10
            )
            stable = final or not is_last or has_terminal_punctuation(text) or partial_ready
            if stable:
                candidates.append(segment)
                if partial_ready and not final:
                    self.last_partial_translation_at = now
                    self.last_partial_translation_word_count = current_word_count
                    self.last_partial_translation_text = text

        missing = [segment.source_text for segment in candidates if segment.source_text not in self.translation_cache]
        if missing:
            for source, translation in zip(missing, translate_texts(missing, model_dir)):
                self.translation_cache[source] = translation

        for segment in segments:
            segment.translated_text = self.translation_cache.get(segment.source_text, "")


def result_segments(result: Any, channel: str, offset: float) -> List[Segment]:
    speaker = "音频"
    if channel == "microphone":
        speaker = "我"
    elif channel == "system":
        speaker = "电脑音频"

    sentences = getattr(result, "sentences", None)
    if sentences:
        segments = []
        for sentence in sentences:
            text = getattr(sentence, "text", "")
            if not text:
                continue
            start = float(getattr(sentence, "start", 0.0) or 0.0) + offset
            end_value = getattr(sentence, "end", None)
            end = float(end_value) + offset if end_value is not None else None
            segments.append(Segment(channel=channel, speaker=speaker, start=start, end=end, source_text=text.strip()))
        if segments:
            return segments

    text = result.get("text", "") if isinstance(result, dict) else getattr(result, "text", "")
    if isinstance(text, str):
        text = text.strip()
    else:
        text = ""
    if not text:
        return []
    texts = sentence_split(text)
    if not texts:
        return []
    segments: List[Segment] = []
    cursor = offset
    for text in texts:
        duration = max(1.5, min(8.0, len(text.split()) * 0.45))
        segments.append(Segment(channel=channel, speaker=speaker, start=cursor, end=cursor + duration, source_text=text))
        cursor += duration
    return segments


def transcribe_wav(wav_path: Path, model_dir: Path, channel: str, offset: float) -> List[Segment]:
    duration = wav_duration(wav_path)
    if 0 < duration < 0.35:
        return []
    model = load_asr_model(model_dir)
    if hasattr(model, "transcribe"):
        try:
            result = model.transcribe(str(wav_path), chunk_duration=120.0, overlap_duration=15.0)
        except TypeError:
            result = model.transcribe(str(wav_path))
    elif hasattr(model, "generate"):
        result = model.generate(
            str(wav_path),
            language=None,
            att_context_size=getattr(model, "freecommunication_att_context_size", [70, 13]),
        )
    else:
        raise RuntimeError("Loaded ASR model does not expose transcribe() or generate().")
    return result_segments(result, channel=channel, offset=offset)


def transcribe_wav_chunked(
    wav_path: Path,
    model_dir: Path,
    channel: str,
    offset: float,
    tmp_dir: Path,
) -> List[Segment]:
    duration = wav_duration(wav_path)
    if duration <= 45.0:
        return transcribe_wav(wav_path, model_dir, channel=channel, offset=offset)

    segments: List[Segment] = []
    windows = split_wav_windows(wav_path, tmp_dir / "chunks", duration=duration, step_seconds=30.0, overlap_seconds=10.0)
    for chunk_path, chunk_start, _, _ in windows:
        chunk_duration = wav_duration(chunk_path)
        if chunk_duration < 0.35:
            continue
        segments.extend(transcribe_wav(chunk_path, model_dir, channel=channel, offset=offset + chunk_start))
    return dedupe_overlapping_segments(segments)


def dedupe_overlapping_segments(segments: List[Segment]) -> List[Segment]:
    deduped: List[Segment] = []
    for segment in sorted(segments, key=lambda item: (item.start, item.end or item.start)):
        text = re.sub(r"\s+", " ", segment.source_text).strip()
        if not text:
            continue
        segment.source_text = text
        duplicate_index = -1
        for index in range(max(0, len(deduped) - 8), len(deduped)):
            existing = deduped[index]
            if abs(existing.start - segment.start) > 14.0:
                continue
            if segment_similarity(existing.source_text, segment.source_text) >= 0.64:
                duplicate_index = index
                break
        if duplicate_index >= 0:
            if word_count(segment.source_text) > word_count(deduped[duplicate_index].source_text):
                deduped[duplicate_index] = segment
        else:
            deduped.append(segment)
    return sorted(deduped, key=lambda item: item.start)


def segment_similarity(left: str, right: str) -> float:
    left_words = set(re.findall(r"[A-Za-z0-9']+", left.lower()))
    right_words = set(re.findall(r"[A-Za-z0-9']+", right.lower()))
    denominator = min(len(left_words), len(right_words))
    if denominator == 0:
        return 0.0
    return len(left_words.intersection(right_words)) / denominator


def translate_texts(texts: List[str], model_dir: Path) -> List[str]:
    if not texts:
        return []
    chunk_lists = [split_text_for_translation(text) for text in texts]
    missing_chunks: List[str] = []
    seen_missing = set()
    model_key = str(model_dir)
    for chunks in chunk_lists:
        for chunk in chunks:
            cache_key = (model_key, chunk)
            if cache_key not in NMT_TRANSLATION_CACHE and chunk not in seen_missing:
                missing_chunks.append(chunk)
                seen_missing.add(chunk)

    if missing_chunks:
        translated_chunks = translate_text_chunks(missing_chunks, model_dir)
        for source, translation in zip(missing_chunks, translated_chunks):
            NMT_TRANSLATION_CACHE[(model_key, source)] = translation

    results: List[str] = []
    for chunks in chunk_lists:
        translations = [NMT_TRANSLATION_CACHE.get((model_key, chunk), "") for chunk in chunks]
        results.append(join_translation_chunks(translations))
    return results


def translate_text_chunks(texts: List[str], model_dir: Path) -> List[str]:
    if not texts:
        return []
    tokenizer, model = load_nmt_model(model_dir)
    import torch

    translated: List[str] = []
    batch_size = 8
    for start in range(0, len(texts), batch_size):
        batch = texts[start : start + batch_size]
        prepared = [f">>cmn_Hans<< {text}" for text in batch]
        encoded = tokenizer(prepared, return_tensors="pt", padding=True, truncation=True, max_length=256)
        encoded = {key: value.to("cpu") for key, value in encoded.items()}
        with torch.no_grad():
            generated = model.generate(**encoded, num_beams=4, max_length=256)
        translated.extend(tokenizer.batch_decode(generated, skip_special_tokens=True))
    return translated


def split_text_for_translation(text: str, max_words: int = 34, max_chars: int = 210) -> List[str]:
    compact = re.sub(r"\s+", " ", text).strip()
    if not compact:
        return []
    chunks: List[str] = []
    for sentence in sentence_split(compact):
        words = sentence.split()
        current: List[str] = []
        current_chars = 0
        for word in words:
            projected_chars = current_chars + len(word) + (1 if current else 0)
            should_flush = current and (len(current) >= max_words or projected_chars > max_chars)
            if should_flush:
                chunks.append(" ".join(current).strip())
                current = []
                current_chars = 0
            current.append(word)
            current_chars += len(word) + (1 if current_chars else 0)
        if current:
            chunks.append(" ".join(current).strip())
    return [chunk for chunk in chunks if chunk]


def join_translation_chunks(chunks: List[str]) -> str:
    cleaned = [re.sub(r"\s+", " ", chunk).strip() for chunk in chunks if chunk and chunk.strip()]
    if not cleaned:
        return ""
    joined = cleaned[0]
    punctuation = "，。！？；,.!?;"
    for chunk in cleaned[1:]:
        if joined[-1] in punctuation or chunk[0] in punctuation:
            joined += chunk
        else:
            joined += "。" + chunk
    joined = re.sub(r"\s+([，。！？；,.!?;])", r"\1", joined)
    return joined


def safe_base_name(name: str) -> str:
    name = re.sub(r"[/:\\\n\r\t]+", " ", name).strip()
    return name or datetime.now().strftime("%Y-%m-%d %H.%M.%S")


def unique_path(directory: Path, base_name: str, suffix: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    base = safe_base_name(base_name)
    candidate = directory / f"{base}{suffix}"
    index = 2
    while candidate.exists():
        candidate = directory / f"{base} {index}{suffix}"
        index += 1
    return candidate


def unique_directory(directory: Path, base_name: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    base = safe_base_name(base_name)
    candidate = directory / base
    index = 2
    while candidate.exists():
        candidate = directory / f"{base} {index}"
        index += 1
    candidate.mkdir(parents=True, exist_ok=False)
    return candidate


def write_txt(
    path: Path,
    title: str,
    source_media: Optional[Path],
    segments: List[Segment],
    include_translation: bool,
) -> None:
    lines: List[str] = [
        f"# {title}",
        f"时间: {datetime.now().isoformat(timespec='seconds')}",
    ]
    if source_media:
        lines.append(f"源文件: {source_media}")
    if include_translation:
        lines.extend(["", "## 转录+翻译"])
        for segment in segments:
            lines.append(f"[{short_clock(segment.start)}] {segment.speaker}")
            if segment.source_text:
                lines.append(segment.source_text)
            if segment.translated_text:
                lines.append(segment.translated_text)
            lines.append("")
    else:
        lines.extend(["", "## 转录"])
        for segment in segments:
            lines.append(f"[{short_clock(segment.start)}] {segment.speaker}: {segment.source_text}")
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def write_srt(path: Path, segments: List[Segment], include_translation: bool) -> None:
    blocks: List[str] = []
    previous_end = 0.0
    subtitle_segments = expand_segments_for_srt(segments, include_translation=include_translation)
    for index, segment in enumerate(subtitle_segments, start=1):
        start_seconds = max(segment.start, previous_end + (0.001 if previous_end > 0 else 0.0))
        end_seconds = segment.end if segment.end is not None else start_seconds + 4.0
        end_seconds = max(end_seconds, start_seconds + 0.35)
        previous_end = end_seconds
        start = srt_clock(start_seconds)
        end = srt_clock(end_seconds)
        text = segment.source_text
        if include_translation and segment.translated_text:
            text = f"{segment.source_text}\n{segment.translated_text}"
        blocks.append(f"{index}\n{start} --> {end}\n{text}")
    path.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")


def expand_segments_for_srt(segments: List[Segment], include_translation: bool) -> List[Segment]:
    expanded: List[Segment] = []
    for segment in segments:
        source_chunks = split_source_for_srt(segment.source_text)
        if not source_chunks:
            continue
        translation_chunks = split_translation_for_srt(segment.translated_text, len(source_chunks)) if include_translation else []
        start = segment.start
        fallback_duration = max(1.6, min(5.0, word_count(segment.source_text) * 0.34))
        end = segment.end if segment.end is not None else start + fallback_duration
        duration = max(0.8 * len(source_chunks), end - start)
        end = start + duration
        cursor = start
        weights = [subtitle_timing_weight(source) for source in source_chunks]
        total_weight = max(1, sum(weights))
        consumed_weight = 0
        for index, source in enumerate(source_chunks):
            consumed_weight += weights[index]
            chunk_end = start + (duration * consumed_weight / total_weight)
            if index == len(source_chunks) - 1:
                chunk_end = end
            else:
                remaining_minimum = (len(source_chunks) - index - 1) * 0.35
                chunk_end = min(chunk_end, end - remaining_minimum)
            chunk_end = max(chunk_end, cursor + 0.35)
            translated = translation_chunks[index] if index < len(translation_chunks) else ""
            expanded.append(
                Segment(
                    channel=segment.channel,
                    speaker=segment.speaker,
                    start=cursor,
                    end=chunk_end,
                    source_text=source,
                    translated_text=translated,
                )
            )
            cursor = chunk_end + 0.001
    return expanded


def subtitle_timing_weight(text: str) -> int:
    # Words, numbers, and individual CJK characters are closer to spoken duration than raw character count.
    units = re.findall(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*|[\u3400-\u9fff]", text)
    return max(1, len(units))


def split_source_for_srt(text: str, max_words: int = 11, max_chars: int = 78) -> List[str]:
    chunks: List[str] = []
    for sentence in sentence_split(text):
        words = sentence.split()
        current: List[str] = []
        current_chars = 0
        for word in words:
            projected = current_chars + len(word) + (1 if current else 0)
            if current and (len(current) >= max_words or projected > max_chars):
                chunks.append(" ".join(current).strip())
                current = []
                current_chars = 0
            current.append(word)
            current_chars += len(word) + (1 if current_chars else 0)
        if current:
            chunks.append(" ".join(current).strip())
    return [chunk for chunk in chunks if chunk]


def split_translation_for_srt(text: str, target_count: int) -> List[str]:
    compact = re.sub(r"\s+", " ", text).strip()
    if target_count <= 0:
        return []
    if not compact:
        return [""] * target_count
    if target_count == 1:
        return [compact]

    chunks: List[str] = []
    start = 0
    length = len(compact)
    for remaining in range(target_count, 0, -1):
        if remaining == 1:
            chunks.append(compact[start:].strip())
            break
        ideal = start + max(1, round((length - start) / remaining))
        window_end = min(length, ideal + 8)
        split_at = -1
        for index in range(min(length, window_end), max(start, ideal - 8), -1):
            if compact[index - 1] in "，。！？；,.!?;":
                split_at = index
                break
        if split_at <= start:
            split_at = min(length, ideal)
        chunks.append(compact[start:split_at].strip())
        start = split_at
    while len(chunks) < target_count:
        chunks.append("")
    return chunks[:target_count]


def short_clock(seconds: float) -> str:
    total = max(0, int(seconds))
    return f"{total // 60:02d}:{total % 60:02d}"


def srt_clock(seconds: float) -> str:
    millis = max(0, int(round(seconds * 1000)))
    hours = millis // 3_600_000
    minutes = (millis % 3_600_000) // 60_000
    secs = (millis % 60_000) // 1000
    ms = millis % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"


def handle_translate(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")
    text = payload.get("text", "")
    translated = translate_texts([text], nmt_dir)[0] if text.strip() else ""
    return ok(request_id, text=text, translation=translated)


def handle_transcribe_file(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    input_path = require_path(payload.get("input", ""), "Input media")
    asr_dir = require_path(payload.get("asr_model", ""), "ASR model")
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")
    output_dir = Path(payload.get("output_dir") or ".").expanduser()
    should_translate = truthy(payload.get("translate"), True)
    save_outputs = truthy(payload.get("save_outputs"), False)
    channel = payload.get("channel") or "file"
    offset = float(payload.get("offset") or 0.0)
    record_dir = unique_directory(output_dir, payload.get("base_name") or input_path.stem) if save_outputs else None

    with tempfile.TemporaryDirectory(prefix="freecommunication-") as tmp:
        wav_path = Path(tmp) / "audio.wav"
        run_ffmpeg_to_wav(input_path, wav_path)
        if record_dir is not None:
            shutil.copy2(wav_path, record_dir / "audio.wav")
        segments = transcribe_wav_chunked(wav_path, asr_dir, channel=channel, offset=offset, tmp_dir=Path(tmp))

    segments = coalesce_segments(
        segments,
        max_words=54 if channel == "file" else 42,
        max_duration=20.0 if channel == "file" else 14.0,
        max_gap=1.1 if channel == "file" else 0.9,
    )

    if should_translate:
        translations = translate_texts([segment.source_text for segment in segments], nmt_dir)
        for segment, translation in zip(segments, translations):
            segment.translated_text = translation

    record_path = None
    srt_path = None
    if save_outputs and record_dir is not None:
        txt_path = record_dir / "transcript.txt"
        write_txt(txt_path, title=record_dir.name, source_media=input_path, segments=segments, include_translation=should_translate)
        record_path = str(txt_path)
        subtitle_path = record_dir / "subtitles.srt"
        write_srt(subtitle_path, segments, include_translation=should_translate)
        srt_path = str(subtitle_path)

    return ok(
        request_id,
        text=" ".join(segment.source_text for segment in segments).strip(),
        translation=" ".join(segment.translated_text for segment in segments).strip(),
        record_path=record_path,
        srt_path=srt_path,
        segments=[segment.to_json() for segment in segments],
    )


def handle_transcribe_chunks(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    asr_dir = require_path(payload.get("asr_model", ""), "ASR model")
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")
    should_translate = truthy(payload.get("translate"), True)
    channel = payload.get("channel") or "microphone"
    offset = float(payload.get("offset") or 0.0)
    raw_inputs = payload.get("inputs_json") or "[]"
    try:
        input_values = json.loads(raw_inputs)
    except json.JSONDecodeError as exc:
        raise RuntimeError("inputs_json is not valid JSON") from exc
    if not isinstance(input_values, list):
        raise RuntimeError("inputs_json must be a list")
    input_paths = [Path(str(value)).expanduser() for value in input_values if str(value).strip()]
    if not input_paths:
        return ok(request_id, text="", translation="", segments=[])

    with tempfile.TemporaryDirectory(prefix="freecommunication-reconcile-") as tmp:
        tmp_dir = Path(tmp)
        wav_path = tmp_dir / "joined.wav"
        run_ffmpeg_concat_to_wav(input_paths, wav_path, tmp_dir / "chunks.txt")
        segments = transcribe_wav_chunked(wav_path, asr_dir, channel=channel, offset=offset, tmp_dir=tmp_dir)

    segments = coalesce_segments(
        segments,
        max_words=42,
        max_duration=14.0,
        max_gap=0.9,
    )

    if should_translate:
        translations = translate_texts([segment.source_text for segment in segments], nmt_dir)
        for segment, translation in zip(segments, translations):
            segment.translated_text = translation

    return ok(
        request_id,
        text=" ".join(segment.source_text for segment in segments).strip(),
        translation=" ".join(segment.translated_text for segment in segments).strip(),
        segments=[segment.to_json() for segment in segments],
    )


def handle_stream_start(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    session_id = payload.get("session_id") or request_id or datetime.now().isoformat()
    asr_dir = require_path(payload.get("asr_model", ""), "ASR model")
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")
    load_asr_model(asr_dir)
    if truthy(payload.get("translate"), True):
        load_nmt_model(nmt_dir)
    STREAM_SESSIONS[session_id] = {}
    return ok(request_id, session_id=session_id, message="Streaming session started.")


def handle_stream_push(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    session_id = payload.get("session_id") or ""
    if not session_id:
        raise RuntimeError("stream session_id is empty")
    asr_dir = require_path(payload.get("asr_model", ""), "ASR model")
    nmt_dir = require_path(payload.get("nmt_model", ""), "NMT model")
    channel = payload.get("channel") or "microphone"
    offset = float(payload.get("offset") or 0.0)
    final = truthy(payload.get("final"), False)
    should_translate = truthy(payload.get("translate"), True)
    encoded = payload.get("pcm", "")
    pcm_bytes = base64.b64decode(encoded) if encoded else b""

    model = load_asr_model(asr_dir)
    channel_sessions = STREAM_SESSIONS.setdefault(session_id, {})
    stream = channel_sessions.get(channel)
    if stream is None:
        stream = StreamingASRSession(model=model, channel=channel, offset=offset)
        channel_sessions[channel] = stream

    segments = stream.append_pcm_f32(pcm_bytes, final=final)
    if should_translate and segments:
        stream.translate_stable_segments(segments, nmt_dir, final=final)

    return ok(
        request_id,
        text=" ".join(segment.source_text for segment in segments).strip(),
        translation=" ".join(segment.translated_text for segment in segments).strip(),
        segments=[segment.to_json() for segment in segments],
    )


def handle_stream_end(payload: Dict[str, str], request_id: Optional[str]) -> Dict[str, Any]:
    session_id = payload.get("session_id") or ""
    STREAM_SESSIONS.pop(session_id, None)
    return ok(request_id, message="Streaming session ended.")


def handle(request: Dict[str, Any]) -> Dict[str, Any]:
    request_id = request.get("id")
    command = request.get("command")
    payload = request.get("payload") or {}
    try:
        if command == "check":
            return handle_check(payload, request_id)
        if command == "translate":
            return handle_translate(payload, request_id)
        if command == "transcribe_file":
            return handle_transcribe_file(payload, request_id)
        if command == "transcribe_chunks":
            return handle_transcribe_chunks(payload, request_id)
        if command == "stream_start":
            return handle_stream_start(payload, request_id)
        if command == "stream_push":
            return handle_stream_push(payload, request_id)
        if command == "stream_end":
            return handle_stream_end(payload, request_id)
        return fail(request_id, f"Unknown command: {command}")
    except Exception as exc:  # noqa: BLE001
        traceback.print_exc(file=sys.stderr)
        return fail(request_id, str(exc))


def serve() -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            emit(fail(None, f"Invalid JSON: {exc}"))
            continue
        emit(handle(request))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("serve")

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--asr-model", required=True)
    check_parser.add_argument("--nmt-model", required=True)

    transcribe_parser = subparsers.add_parser("transcribe-file")
    transcribe_parser.add_argument("--input", required=True)
    transcribe_parser.add_argument("--asr-model", required=True)
    transcribe_parser.add_argument("--nmt-model", required=True)
    transcribe_parser.add_argument("--output-dir", required=True)
    transcribe_parser.add_argument("--translate", action="store_true")
    transcribe_parser.add_argument("--save-outputs", action="store_true")

    args = parser.parse_args()
    if args.command == "serve":
        return serve()
    if args.command == "check":
        emit(handle({"id": "cli", "command": "check", "payload": {"asr_model": args.asr_model, "nmt_model": args.nmt_model}}))
        return 0
    if args.command == "transcribe-file":
        emit(
            handle(
                {
                    "id": "cli",
                    "command": "transcribe_file",
                    "payload": {
                        "input": args.input,
                        "asr_model": args.asr_model,
                        "nmt_model": args.nmt_model,
                        "output_dir": args.output_dir,
                        "translate": str(args.translate).lower(),
                        "save_outputs": str(args.save_outputs).lower(),
                    },
                }
            )
        )
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
