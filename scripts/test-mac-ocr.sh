#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/macos/.build/ocr-validation"
(cd "$ROOT/core" && cargo build --release)
swiftc -O -parse-as-library "$ROOT/macos/Sources/Framelet/Imaging.swift" "$ROOT/scripts/test-mac-ocr.swift" -L "$ROOT/core/target/release" -lframelet_core -Xlinker -rpath -Xlinker "$ROOT/core/target/release" -o "$ROOT/macos/.build/ocr-validation/test-mac-ocr"
"$ROOT/macos/.build/ocr-validation/test-mac-ocr" "$ROOT"
