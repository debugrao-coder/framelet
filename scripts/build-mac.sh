#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_ARCH="$(uname -m)"
ARCH="${1:-$HOST_ARCH}"
if [[ $# -gt 1 || ( "$ARCH" != arm64 && "$ARCH" != x86_64 ) ]]; then
 echo "Usage: bash scripts/build-mac.sh [arm64|x86_64]" >&2; exit 2
fi
SWIFT_ARGS=()
# rustc 1.94's implicit debug stripping can misalign Mach-O LINKEDIT with SDK27.
# Preserve linker output instead of patching bytes or weakening loader checks.
# https://github.com/rust-lang/rust/issues/157750
export CARGO_PROFILE_RELEASE_STRIP=none
if [[ $# -eq 0 ]]; then
 (cd "$ROOT/core" && cargo build --release)
 CORE_LIB_DIR="$ROOT/core/target/release"
 APP="$ROOT/build/Framelet.app"
else
 if [[ "$ARCH" == arm64 ]]; then RUST_TARGET=aarch64-apple-darwin; else RUST_TARGET=x86_64-apple-darwin; fi
 if ! rustup target list --installed | grep -qx "$RUST_TARGET"; then
  echo "Missing Rust target. Install with: rustup target add $RUST_TARGET" >&2; exit 2
 fi
 (cd "$ROOT/core" && MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --target "$RUST_TARGET")
 CORE_LIB_DIR="$ROOT/core/target/$RUST_TARGET/release"
 SWIFT_ARGS=(--triple "$ARCH-apple-macosx14.0" --scratch-path "$ROOT/macos/.build/$ARCH-isolated")
 APP="$ROOT/build/$ARCH/Framelet.app"
fi
# SwiftPM's linker can stamp the deployment version as the SDK version.
# Keep macOS 14 compatibility, but link with the actual selected SDK so AppKit
# can adopt the current native appearance rather than its legacy compatibility UI.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
(cd "$ROOT/macos" && FRAMELET_CORE_LIB_DIR="$CORE_LIB_DIR" swift build -c release "${SWIFT_ARGS[@]}" -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
BIN_DIR="$(cd "$ROOT/macos" && FRAMELET_CORE_LIB_DIR="$CORE_LIB_DIR" swift build -c release "${SWIFT_ARGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/macos/Resources/Framelet.icns" "$APP/Contents/Resources/Framelet.icns"
cp "$BIN_DIR/Framelet" "$APP/Contents/MacOS/Framelet"
[[ "$(lipo -archs "$APP/Contents/MacOS/Framelet")" == "$ARCH" ]]
# Bundle the Rust dylib if linked dynamically, with an application-relative path.
if otool -L "$APP/Contents/MacOS/Framelet" | grep -q libframelet_core; then
 mkdir -p "$APP/Contents/Frameworks"
 cp "$CORE_LIB_DIR/libframelet_core.dylib" "$APP/Contents/Frameworks/"
 [[ "$(lipo -archs "$APP/Contents/Frameworks/libframelet_core.dylib")" == "$ARCH" ]]
 LIB=$(otool -L "$APP/Contents/MacOS/Framelet" | awk '/libframelet_core/{print $1}')
 install_name_tool -change "$LIB" @executable_path/../Frameworks/libframelet_core.dylib "$APP/Contents/MacOS/Framelet"
 install_name_tool -id @rpath/libframelet_core.dylib "$APP/Contents/Frameworks/libframelet_core.dylib"
 codesign --force --sign - "$APP/Contents/Frameworks/libframelet_core.dylib"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Framelet</string><key>CFBundleIdentifier</key><string>local.framelet.app</string><key>CFBundleName</key><string>瞬帧</string><key>CFBundleDisplayName</key><string>瞬帧</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>NSScreenCaptureUsageDescription</key><string>仅在你启动截图或录制时捕获所选屏幕内容。所有处理在本机完成。</string>
<key>CFBundleIconFile</key><string>Framelet.icns</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
if [[ "$ARCH" == "$HOST_ARCH" ]]; then
 "$APP/Contents/MacOS/Framelet" --self-test
else
 echo "Cross-build only: $ARCH execution NOT_TESTED on $HOST_ARCH. No Rosetta installation or launch attempted."
fi
printf '\nBuilt local development app: %s\nNot notarized; Windows/runtime acceptance separate.\n' "$APP"
