#!/usr/bin/env bash
# Format/size conversion only; the artwork is the checked-in generated master.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/design/app-icon/framelet-master.png"
SET="$ROOT/design/app-icon/Framelet.iconset"
mkdir -p "$SET" "$ROOT/macos/Resources" "$ROOT/windows/Assets"
for size in 16 32 128 256 512; do
 sips -z "$size" "$size" "$MASTER" --out "$SET/icon_${size}x${size}.png" >/dev/null
 double=$((size * 2))
 sips -z "$double" "$double" "$MASTER" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/macos/Resources/Framelet.icns"
for size in 16 24 32 48 64 128 256; do
 sips -z "$size" "$size" "$MASTER" --out "$ROOT/design/app-icon/windows-$size.png" >/dev/null
done
for size in 44 50 150; do
 sips -z "$size" "$size" "$MASTER" --out "$ROOT/windows/Assets/Logo$size.png" >/dev/null
done
# ICO container with lossless PNG entries. No artwork processing in Python.
python3 - "$ROOT" <<'PY'
import struct, sys
from pathlib import Path
root = Path(sys.argv[1])
sizes = [16, 24, 32, 48, 64, 128, 256]
blobs = [(root / f'design/app-icon/windows-{size}.png').read_bytes() for size in sizes]
offset = 6 + 16 * len(sizes)
entries = []
for size, blob in zip(sizes, blobs):
    entries.append(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(blob), offset))
    offset += len(blob)
(root / 'windows/Assets/Framelet.ico').write_bytes(
    struct.pack('<HHH', 0, 1, len(sizes)) + b''.join(entries) + b''.join(blobs))
PY
echo 'Built macOS ICNS and Windows ICO/MSIX PNG resources from the same master.'
