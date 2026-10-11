#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/artifacts" "$ROOT/macos/.build/media-validation"
(cd "$ROOT/core" && cargo build --release)
swiftc -O -parse-as-library \
  "$ROOT/macos/Sources/Framelet/Imaging.swift" \
  "$ROOT/macos/Sources/Framelet/Capture.swift" \
  "$ROOT/scripts/test-mac-media.swift" \
  -L "$ROOT/core/target/release" -lframelet_core \
  -Xlinker -rpath -Xlinker "$ROOT/core/target/release" \
  -o "$ROOT/macos/.build/media-validation/test-mac-media"
"$ROOT/macos/.build/media-validation/test-mac-media" "$ROOT"
