#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/freecommunication-core-logic-smoke"

cd "$ROOT_DIR"
/usr/bin/xcrun swiftc -parse-as-library \
  Support/Defaults.swift \
  Models/ModelManagement.swift \
  Services/ModelDownloadService.swift \
  script/core_logic_smoke.swift \
  -o "$OUTPUT"
"$OUTPUT"
