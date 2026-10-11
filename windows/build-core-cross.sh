#!/usr/bin/env bash
# Cross-build C ABI DLL on macOS/Linux. This does NOT execute a Windows test.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
linker="$(command -v x86_64-w64-mingw32-gcc || true)"
if [[ -z "$linker" ]]; then echo 'Install MinGW-w64 with an official package manager before building.' >&2; exit 1; fi
rustup target add x86_64-pc-windows-gnu
CARGO_TARGET_DIR="$here/bin/rust-cross" \
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$linker" \
cargo build --manifest-path "$here/../core/Cargo.toml" --release --locked --target x86_64-pc-windows-gnu
mkdir -p "$here/bin/publish-x64"
cp "$here/bin/rust-cross/x86_64-pc-windows-gnu/release/framelet_core.dll" "$here/bin/publish-x64/framelet_core.dll"
file "$here/bin/publish-x64/framelet_core.dll"
if command -v x86_64-w64-mingw32-objdump >/dev/null; then
  x86_64-w64-mingw32-objdump -p "$here/bin/publish-x64/framelet_core.dll" > "$here/native-x64-pe-validation.txt"
  grep 'DLL Name:\|framelet_overlap' "$here/native-x64-pe-validation.txt"
fi
