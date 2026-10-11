#!/usr/bin/env python3
"""Inspect a thin development bundle without launching UI or requesting capture.

Static checks do not prove target-machine compatibility, notarization or capture.
"""
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(app, expected_arch, expected_sdk):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["LSMinimumSystemVersion"] == "14.0", "unexpected deployment minimum"
    assert info["CFBundleExecutable"] == "Framelet"
    assert info["CFBundleIdentifier"] == "local.framelet.app"
    exe = app / "Contents/MacOS/Framelet"
    lib = app / "Contents/Frameworks/libframelet_core.dylib"
    binaries = {}
    for path in (exe, lib):
        architecture = run("lipo", "-archs", str(path))
        assert architecture == expected_arch, f"architecture mismatch: {path}"
        commands = run("otool", "-l", str(path))
        assert "LC_BUILD_VERSION" in commands
        minimum = re.search(r"\bminos\s+(\S+)", commands).group(1)
        sdk = re.search(r"\bsdk\s+(\S+)", commands).group(1)
        assert minimum == "14.0", f"deployment minimum mismatch: {path}"
        assert sdk == expected_sdk, f"SDK mismatch: {path}: {sdk}"
        string_offset = int(re.search(r"\bstroff\s+(\d+)", commands).group(1))
        assert string_offset % 8 == 0, f"misaligned Mach-O string pool: {path}"
        deps = [line.strip().split(" (compatibility")[0]
                for line in run("otool", "-L", str(path)).splitlines()[1:]]
        if path == lib:
            assert deps.pop(0) == "@rpath/libframelet_core.dylib", "nonportable library ID"
        else:
            assert "@executable_path/../Frameworks/libframelet_core.dylib" in deps
        for dependency in deps:
            assert dependency.startswith(("/System/Library/", "/usr/lib/")) or (
                path == exe and dependency == "@executable_path/../Frameworks/libframelet_core.dylib"
            ), f"unbundled non-system dependency: {dependency}"
        binaries[str(path.relative_to(app))] = {
            "sha256": sha(path), "architecture": architecture,
            "minos": minimum, "sdk": sdk, "string_pool_offset": string_offset,
            "dependencies": deps,
        }
    assert re.search(r"\b_framelet_overlap$", run("nm", "-gU", str(lib)), re.MULTILINE)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    return {"status": "PASS_SCOPED", "verified_at": datetime.now(timezone.utc).isoformat(),
            "app": str(app), "binaries": binaries,
            "signature": "local development signature verifies; NOT notarization",
            "scope": "Static architecture, SDK/minimum, alignment, relocation paths, ABI export and signature only; target runtime/capture NOT_TESTED"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--arch", required=True, choices=("arm64", "x86_64"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = inspect(args.app.resolve(), args.arch, run("xcrun", "--sdk", "macosx", "--show-sdk-version"))
    output = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output)
