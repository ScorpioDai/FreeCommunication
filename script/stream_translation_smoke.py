#!/usr/bin/env python3
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys


def send(process: subprocess.Popen, command: str, payload: dict) -> dict:
    request = {
        "id": command,
        "command": command,
        "payload": payload,
    }
    assert process.stdin is not None
    assert process.stdout is not None
    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("Backend exited without a response.")
    response = json.loads(line)
    if not response.get("ok"):
        raise RuntimeError(response.get("error") or f"{command} failed")
    return response


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    python = root / "Backend/.venv/bin/python"
    backend = root / "Backend/freecommunication_backend.py"
    ffmpeg = root / "Vendor/FFmpeg/ffmpeg"
    asr = Path.home() / (
        "Documents/AI Models/"
        "animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit"
    )
    nmt = Path.home() / "Documents/AI Models/Helsinki-NLP:opus-mt-en-zh"

    converted = subprocess.run(
        [
            str(ffmpeg),
            "-v", "error",
            "-i", args.input,
            "-t", "18",
            "-ac", "1",
            "-ar", "16000",
            "-f", "f32le",
            "pipe:1",
        ],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    if len(converted) < 48_000 * 4:
        raise RuntimeError("Smoke-test input is too short.")

    environment = os.environ.copy()
    environment["FREECOMMUNICATION_FFMPEG"] = str(ffmpeg)
    environment["HF_HUB_OFFLINE"] = "1"
    environment["TRANSFORMERS_OFFLINE"] = "1"
    process = subprocess.Popen(
        [str(python), str(backend), "serve"],
        cwd=backend.parent,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        bufsize=1,
    )

    common = {
        "session_id": "stream-translation-smoke",
        "asr_model": str(asr),
        "nmt_model": str(nmt),
    }
    try:
        send(process, "stream_start", {**common, "translate": "true"})
        phase_word_counts = {"on_before": 0, "off": 0, "on_after": 0}
        translation_recovered = False
        chunk_size = 48_000

        for index, start in enumerate(range(0, len(converted), chunk_size)):
            pcm = converted[start : start + chunk_size]
            elapsed = index * 0.75
            if elapsed < 6:
                enabled = True
                phase = "on_before"
            elif elapsed < 12:
                enabled = False
                phase = "off"
            else:
                enabled = True
                phase = "on_after"

            response = send(
                process,
                "stream_push",
                {
                    **common,
                    "translate": str(enabled).lower(),
                    "channel": "microphone",
                    "offset": "0",
                    "final": "false",
                    "pcm": base64.b64encode(pcm).decode("ascii"),
                },
            )
            words = len((response.get("text") or "").split())
            phase_word_counts[phase] = max(phase_word_counts[phase], words)
            if not enabled and response.get("translation"):
                raise RuntimeError("Translation was emitted while disabled.")
            if phase == "on_after" and response.get("translation"):
                translation_recovered = True

        response = send(
            process,
            "stream_push",
            {
                **common,
                "translate": "true",
                "channel": "microphone",
                "offset": "0",
                "final": "true",
                "pcm": "",
            },
        )
        translation_recovered = translation_recovered or bool(response.get("translation"))
        send(process, "stream_end", {"session_id": common["session_id"]})

        if phase_word_counts["off"] <= phase_word_counts["on_before"]:
            raise RuntimeError("ASR did not continue growing while translation was disabled.")
        if phase_word_counts["on_after"] <= phase_word_counts["off"]:
            raise RuntimeError("ASR did not continue after translation was re-enabled.")
        if not translation_recovered:
            raise RuntimeError("Translation did not recover after re-enabling.")

        print(json.dumps(phase_word_counts, sort_keys=True))
        print("stream-translation-smoke-ok")
        return 0
    finally:
        if process.stdin is not None:
            process.stdin.close()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
