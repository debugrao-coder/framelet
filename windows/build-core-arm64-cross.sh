#!/usr/bin/env bash
# Builds Windows ARM64 PE C ABI DLL on macOS; never executes a Windows binary.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
toolchain="$here/.tools/llvm-mingw-20261006-ucrt-macos-universal"
linker="$toolchain/bin/aarch64-w64-mingw32-clang"
[[ -x "$linker" ]] || { echo 'Run windows/install-llvm-mingw.sh first (isolated upstream open-source bundle).' >&2; exit 1; }
rustup target add aarch64-pc-windows-gnullvm
RUSTFLAGS="-C target-feature=+crt-static" \
CARGO_TARGET_DIR="$here/bin/rust-cross" \
CARGO_TARGET_AARCH64_PC_WINDOWS_GNULLVM_LINKER="$linker" \
cargo build --manifest-path "$here/../core/Cargo.toml" --release --locked --offline --target aarch64-pc-windows-gnullvm
dll="$here/bin/rust-cross/aarch64-pc-windows-gnullvm/release/framelet_core.dll"
"$toolchain/bin/llvm-readobj" --file-headers --coff-exports --coff-imports "$dll" > "$here/native-arm64-pe-validation.txt"
grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64' "$here/native-arm64-pe-validation.txt"
grep -q 'Name: framelet_overlap' "$here/native-arm64-pe-validation.txt"
python3 "$here/tests/verify_arm64_pe.py" "$dll" "$here/native-arm64-pe-validation.txt" > "$here/native-arm64-validation.json"
mkdir -p "$here/bin/publish-arm64"
cp "$dll" "$here/bin/publish-arm64/framelet_core.dll"
cp "$toolchain/LICENSE.TXT" "$here/bin/publish-arm64/LLVM-LICENSE.txt"
file "$dll"
shasum -a 256 "$dll"
grep 'Name:\|Machine:' "$here/native-arm64-pe-validation.txt"
