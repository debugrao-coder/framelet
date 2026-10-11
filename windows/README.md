# Framelet Windows native milestone

Real WPF application source, not a web mockup. Floating capture strip + screenshot editor + system-appearance OCR side panel. The latest design direction supersedes the old cream/lime palette and forced dark OCR. All work is local; no network capture upload or telemetry code.

Why WPF: standard .NET Windows Desktop targeting can be compiled on the current Mac host; native HWND integration, clipboard and WIC are straightforward. Native WGC/D3D11 capture now supplements WPF, but neither source implementation nor cross-compilation proves runtime aesthetics/performance.

Implemented code paths: physical-pixel region capture (WGC/D3D11 first; explicit GDI fallback for unsupported/cross-monitor cases), manual downward scrolling stitched with `framelet_core.dll`, streaming GIF screen capture using WIC single-frame palettes (10 fps target / 60 seconds / 2.07MP cap), Windows packaged local OCR, basic arrows/rectangles/text/opaque-redaction editor, flattened PNG and clipboard. No dummy success buttons.

Build on Windows: `./build.ps1 -Architecture x64` for portable EXE, `./build.ps1 -Architecture x64 -Package` for MSIX. See [runtime acceptance](RUNTIME-CHECKLIST.md) for tool prerequisites and required package identity/signing. Build does not create trust or install the app.

Platform-neutral GIF mux tests: `dotnet run --project tests/GifMuxTests.csproj -c Release` (242 assertions; optional `-- --core /absolute/path/to/libframelet_core.dylib` adds 5 real host ABI checks; no Windows screen capture).

Cross-build on macOS (source/type validation only): `dotnet build Framelet.csproj -c Release -p:EnableWindowsTargeting=true`. The x64 native DLL can be cross-built with `./build-core-cross.sh` using official Rust `x86_64-pc-windows-gnu` plus MinGW-w64; Mac dylib is never substituted. ARM64 native DLL can now be cross-built with `./install-llvm-mingw.sh` then `./build-core-arm64-cross.sh` using the official `aarch64-pc-windows-gnullvm` target and pinned upstream llvm-mingw. The GNU DLL uses the same C ABI; it has not been loaded on a Windows machine.

References: [WPF GIF codec](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/how-to-encode-and-decode-a-gif-image), [Windows OCR package identity](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr), [Win32 BitBlt](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-bitblt), [MSIX package manifests](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/generate-package-manifest).

Status: **Windows runtime/visual/performance acceptance PENDING**. Native source or cross-compilation does not meet full dual-platform completion.

Safety follow-up: a positive core translation is now accepted only when the entire overlap (including edges) agrees exactly. Fixed headers/footers, changed carets or animated overlap are rejected rather than silently losing content. Successful full GIF output is retained at its `.partial` path if final rename fails; incomplete files are removed when possible and cleanup failures report their path.

## WGC backend (source implemented, Windows runtime PENDING)

`WgcInterop.cs` creates a hardware D3D11 device, wraps IDXGIDevice as the WinRT IDirect3DDevice, and creates a monitor capture item with IGraphicsCaptureItemInterop. `WgcCaptureSource.cs` owns **one device/session/two-surface frame pool per operation**, reused across the entire GIF or manual scrolling session. A free-threaded callback drains into a one-frame ownership slot; replacement frames are disposed immediately. The consumer reads back only requested frames, caches unchanged bitmap content, and has first-frame timeout/cancellation paths. The slot's concurrency and disposal model is covered by tests; the Windows callback/driver behavior is not yet validated.

The backend uses `SoftwareBitmap.CreateCopyFromSurfaceAsync` for **whole-monitor CPU readback, followed by selected-region cropping**. It therefore does **not** prove that small-region capture is faster than GDI, does not eliminate CPU/GPU copies, and does not provide hardware GIF or MP4 encoding. WIC remains the CPU GIF codec. Monitor/readback dimensions are capped; changed display dimensions stop capture instead of silently stretching or cropping incorrectly.

Unsupported WGC/D3D or cross-monitor selection permits an explicitly labeled GDI fallback. **Access denied, policy denial, timeout, cancellation, source closure and device loss do not trigger another capture API.** The app does not request GraphicsCaptureAccess or borderless permission, and leaves Windows' capture border enabled. The launcher requests WDA_EXCLUDEFROMCAPTURE only for its own window and retains hidden-window capture for still/scroll captures; the recorder still instructs moving the launcher out of the region. Exclusion must be checked on a real device.

Official API sources: [CreateFreeThreaded](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.direct3d11captureframepool.createfreethreaded), [CreateForMonitor](https://learn.microsoft.com/windows/win32/api/windows.graphics.capture.interop/nf-windows-graphics-capture-interop-igraphicscaptureiteminterop-createformonitor), [D3D11 WinRT bridge](https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.directx.direct3d11.interop/nf-windows-graphics-directx-direct3d11-interop-createdirect3d11devicefromdxgidevice), [surface readback](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.imaging.softwarebitmap.createcopyfromsurfaceasync).

## Safe PNG save (host-tested filesystem logic; Windows WIC/runtime PENDING)

PNG export no longer opens the destination for writing. `AtomicFileSave.cs` creates an exclusive, uniquely named sibling staging file, encodes there, flushes file contents to disk, closes the stream, then uses `File.Replace` for an existing destination or no-overwrite `File.Move` for a new destination. Unsupported atomic replacement fails without falling back to truncate/copy/delete. A destination that appears during a new-file encode is not overwritten. Failure removes the owned staging file; if cleanup itself fails, the exact orphan path and all primary/close/cleanup errors remain visible. This does not promise crash durability of directory metadata or coordinate other programs concurrently editing an already-existing destination.

The editor creates and freezes its flattened snapshot on the WPF Dispatcher before background encoding. Save re-entry is guarded before the modal dialog; editing/undo/copy/OCR are blocked while saving, and closing is rejected until completion. OCR already running or an unfinished drag blocks starting a save. Dirty state clears only after commit. Frozen cross-thread image sharing follows [WPF Freezable guidance](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/freezable-objects-overview); the worker creates its own encoder/frame and never accesses the UI canvas.

The platform-neutral suite includes 43 additional assertions using only synthetic temporary files on this Mac: new/overwrite success, byte-for-byte preservation after partial encode, open/flush/close/commit faults, operation order, sibling staging, owned-file cleanup, multi-error preservation, a newly competing destination and real directory-destination rejection. **Windows filesystem replacement behavior, WIC encoding on the worker, dialog/close/shortcut interactions and UI responsiveness remain untested.**

## System appearance / style synchronization

Windows matches the Mac information architecture, **not Apple native rendering**. No Apple fonts, Liquid Glass claim, blur, translucent image overlay or copied Apple control implementation is used. `Theme.cs` is the shared Windows appearance owner; `App.xaml` owns grouped control shapes, semantic resources, focus/pressed/disabled states and the system message font. Launcher capture actions and editor export/annotation actions use the same rounded group primitive. Content and OCR remain opaque and distinct from the command layer.

`UISettings.GetColorValue(Foreground)` chooses the neutral light/dark palette and `ColorValuesChanged` refreshes it on the WPF Dispatcher. `SystemParameters.HighContrast` takes precedence and all UI color roles map to matching Windows system brushes. Subscriptions are released at app shutdown. The title bar receives the optional documented DWM dark-mode hint; an unsupported hint leaves OS chrome unchanged. WPF owns ComboBox keyboard/popup geometry and paired Windows system colors; it may retain the OS's lighter native dropdown treatment even within a dark app. No OS preferences or permissions are changed.

Canonical owners: application chrome/colors → `Theme.cs` + `App.xaml`; native language select/scrollbars/dialogs → WPF/Windows; operation status and save/close guards → existing Launcher/Editor logic; image pixels and intentional annotation/redaction colors → unchanged canvas/flatten path, never theme resources. `README.md` records this Windows mapping; root `DESIGN.md` remains design authority.

`python3 tests/theme_source_check.py` checks 54 source contracts, palette text contrast ≥4.5:1, focus/boundary contrast ≥3:1, dynamic appearance wiring and retained save guards. This is **not rendered UI/accessibility evidence**. The managed suite (now 242 assertions) and both architecture builds remain separate checks. Light/dark/high-contrast rendering, native dropdown, screen-reader/keyboard behavior, DPI, narrow layout and real Windows capture still require Windows runtime acceptance. No VM is installed for this milestone.

## OCR content protection

`OcrDocument.cs` is the platform-neutral state machine actually used by `Editor`: recognition progress appears only in status, failure or blank output retains existing text, and replacing manually edited text requires a default-No confirmation. Each request carries its original text revision; typing (including edit-then-revert) makes its eventual result stale. A late request cannot end a newer request or modify a closed document.

Only successful full-text clipboard copy acknowledges that exact text. The explicit Copy Text button and Ctrl+C with the entire OCR text selected use this path; partial selection and native context-menu copy conservatively leave the close warning active. Subsequent editing marks text unacknowledged again. PNG saving never clears text protection. Closing with unacknowledged OCR, unsaved annotations or a running recognition asks for discard with No selected by default.

Recognition uses a frozen UI snapshot on a worker. UI waiting is limited to 30 seconds; timeout/accepted close requests WinRT cancellation, invalidates the result and observes any late task fault. The worker keeps its SoftwareBitmap alive until the OS operation really ends. Native cancellation is best effort: a timed-out worker can remain alive, and the same editor cannot start another OCR until it ends. No claim is made that an OS operation is forcibly terminated within 30 seconds.

34 new managed assertions cover manual confirmation refusal, preserved failure/blank text, revisions, copy identity, stale/closed requests, success/failure and real synthetic bounded-wait cancellation; the suite now totals 242 (247 with the real Mac core ABI checks), including the later shortcut tests. `python3 tests/ocr_source_check.py` adds 16 source-wiring checks. Windows packaged OCR, actual clipboard failure, modal close, IME editing and actual WinRT cancel/resource timing remain **NOT_TESTED**. Both local self-contained publish directories have subsequently been refreshed with these OCR guards and architecture-matched native DLLs; neither bundle has been executed on Windows.

## Windows ARM64 native core — cross-build only

Official Rust documents `aarch64-pc-windows-gnullvm` and llvm-mingw cross-compilation support. The isolated upstream macOS-universal toolchain is pinned to **llvm-mingw 20261006 / LLVM 23.1.3**, verified against the GitHub release asset SHA-256 `a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6`. Installation uses `windows/.tools`, not a replacement for the global LLVM toolchain; rustup adds the official ARM64 target to the existing Rust 1.94.1 toolchain without changing its default. No Windows SDK/EULA, VM, certificate or network capture is involved.

`build-core-arm64-cross.sh` leaves core source untouched and places Cargo outputs under `windows/bin/rust-cross`. It uses `-C target-feature=+crt-static`: default linkage was observed to require `libunwind.dll`, whereas the selected build imports only KERNEL32, ntdll and Windows CRT/core API sets. The script validates raw PE ARM64 (`0xAA64`), DLL/PE32+ flags, the exact `framelet_overlap` export and a system dependency allowlist **before copying** into the local ARM64 bundle. LLVM license text accompanies that local bundle. This is C ABI metadata validation, not a claim of Windows loading, calling-convention execution, MSIX OCR or runtime compatibility.

Evidence: `native-arm64-toolchain.json`, `native-arm64-validation.json`, `native-arm64-pe-validation.txt`, `native-arm64-build-validation.txt`; negative validator checks reject an x64 DLL and an injected non-system import. Existing x64 DLL/build evidence is retained unchanged. Native GNU/LLVM artifacts expose only the documented C boundary; no Rust-owned values cross the DLL boundary.

Reproduce locally from `windows/`:
```sh
export DOTNET_CLI_TELEMETRY_OPTOUT=1
./.tools/dotnet/dotnet run --project tests/GifMuxTests.csproj -c Release
./.tools/dotnet/dotnet run --project tests/GifMuxTests.csproj -c Release -- --core ../core/target/release/libframelet_core.dylib
python3 tests/theme_source_check.py
python3 tests/ocr_source_check.py
./install-llvm-mingw.sh
./build-core-arm64-cross.sh
./.tools/dotnet/dotnet publish -c Release -r win-x64 --self-contained true -p:Platform=x64 -o bin/publish-x64
./.tools/dotnet/dotnet publish -c Release -r win-arm64 --self-contained true -p:Platform=ARM64 -o bin/publish-arm64
```
Both `publish` commands only create local packages, with no upload/sign/install. A fresh x64 native build remains `./build-core-cross.sh` (requires the existing MinGW-w64 GCC). Source references: [Rust target](https://doc.rust-lang.org/rustc/platform-support/windows-gnullvm.html), [pinned upstream release](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261006).

## Native shortcut settings

The launcher exposes **快捷键设置** and always displays the currently active screenshot / scroll / GIF / OCR bindings. Defaults remain `Ctrl+Shift+2`, `Ctrl+Shift+3`, `Ctrl+Shift+4`, `Ctrl+Shift+5`. Each can be recorded, disabled, or restored to defaults; restoration only edits the draft until Apply. Cancel/Escape discards unapplied changes. At least two modifiers including Ctrl or Alt are required, with a letter, digit or F1–F11; Windows combinations and debugger-reserved F12 are intentionally excluded. Existing app hotkeys route into the focused recording field while the modal settings is open instead of starting a capture.

`ShortcutCoordinator` validates duplicate/invalid candidates before touching registrations. New combinations are registered with fresh IDs while old registrations remain active. Swaps reuse the same reserved combinations; only after atomic per-user persistence succeeds does the action mapping switch and retire unused registrations. OS registration or persistence failure preserves the previous working action map and registrations. Rare cleanup failure is reported; a retained inactive registration never dispatches a capture and is retried for cleanup at exit. At startup, an occupied requested combination disables only that action and shows a warning; buttons remain usable. Invalid/oversized config falls back to defaults with a warning and is not overwritten automatically.

Settings are stored only in `%LOCALAPPDATA%\Framelet\shortcuts.json` (schema 1, 16 KB read limit), using the same exclusive sibling staging/flush/atomic commit helper as PNG. No account, cloud sync or AI model/API configuration is involved. The settings window explicitly explains that OCR is local Windows system OCR; MSIX identity and installed language support remain required.

Verification adds **48 managed assertions** for validation, duplicate/system conflict, swap reuse, candidate/persistence rollback, retained inactive cleanup, startup partial conflict, real synthetic JSON files and atomic-write failure, plus **14 source-wiring checks** (`python3 tests/shortcut_source_check.py`). Windows hotkey delivery, key recording/Alt behavior, actual OS conflict, modal keyboard focus, restart persistence and visual layout are still **NOT_TESTED**. The icon assets, ApplicationIcon and package-logo build logic were not changed.
