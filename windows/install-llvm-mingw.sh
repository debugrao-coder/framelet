#!/usr/bin/env bash
# Pinned upstream open-source toolchain, isolated to windows/.tools. No SDK EULA.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'This pinned bundle is for macOS hosts.' >&2; exit 1; }
name=llvm-mingw-20261006-ucrt-macos-universal
sha=a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6
url="https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/$name.tar.xz"
mkdir -p "$here/.tools"
archive="$here/.tools/$name.tar.xz"
if [[ ! -f "$archive" ]]; then
  temporary="$(mktemp "$here/.tools/llvm-mingw-download.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT
  curl --fail --location --retry 2 "$url" -o "$temporary"
  echo "$sha  $temporary" | shasum -a 256 -c -
  mv "$temporary" "$archive"
  trap - EXIT
fi
echo "$sha  $archive" | shasum -a 256 -c -
if [[ ! -d "$here/.tools/$name" ]]; then tar -xJf "$archive" -C "$here/.tools"; fi
"$here/.tools/$name/bin/aarch64-w64-mingw32-clang" --version
