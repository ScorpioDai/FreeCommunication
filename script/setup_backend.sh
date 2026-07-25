#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/Backend/.venv"
PYTHON_BIN="${PYTHON_BIN:-}"

if [ -z "$PYTHON_BIN" ]; then
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      version="$("$candidate" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
      major="${version%%.*}"
      minor="${version#*.}"
      if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }; then
        PYTHON_BIN="$(command -v "$candidate")"
        break
      fi
    fi
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  echo "Python 3.10 or newer is required for parakeet-mlx." >&2
  echo "Install one with Homebrew or set PYTHON_BIN=/path/to/python3.10 and rerun." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required. Install it with: brew install ffmpeg" >&2
  exit 1
fi

rm -rf "$VENV_DIR"
"$PYTHON_BIN" -m venv --copies "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
REQUIREMENTS_FILE="$ROOT_DIR/Backend/requirements-lock.txt"
if [ ! -f "$REQUIREMENTS_FILE" ]; then
  REQUIREMENTS_FILE="$ROOT_DIR/Backend/requirements.txt"
fi
"$VENV_DIR/bin/python" -m pip install -r "$REQUIREMENTS_FILE"

echo "Backend environment ready:"
echo "$VENV_DIR/bin/python"
