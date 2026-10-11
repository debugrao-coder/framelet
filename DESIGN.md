# Framelet native design context

Status: implementation in progress. Authority: Ethan's latest request on 2026-10-11, “样式要是苹果最新原生的”; local-only product boundary in AGENTS.md. Last reviewed: 2026-10-11.

## Direction
Follow current Apple native design and Liquid Glass, not a fixed blue/mint skin. Existing design images remain layout references only; the latest request supersedes their colors and explicit dark OCR mode. Keep screenshot and recognized text dominant and readable. Glass belongs to the control layer, never over the captured image or editable text. Use system typography, SF Symbols, semantic colors and system appearance; no ornamental animation.

## Ownership
- NativeToolbar.swift uses an actual AppKit NSToolbar and NSToolbarItemGroup; macOS owns material, grouped shapes, focus and overflow.
- Theme.swift maps semantic NSColor values; it does not own a duplicated static palette. Editor and OCR default to system appearance without changing OS settings. ApplicationAppearance.swift provides app-only session light/dark previews via the Window menu, restoring system inheritance with nil; it never writes a global or persistent preference.
- scripts/build-mac.sh links the actual selected SDK version while retaining macOS 14 deployment minimum. The observed SDK-14 binary compatibility appearance must not be confused with current native rendering.
- NativeMenus.swift adds standard file/edit commands. Text copy uses the responder chain; undo explicitly chooses the focused text undo manager or canvas marks. Text undo must not remove annotations.
- SwiftUI/AppKit own controls, native panels and scroll behavior. NSAlert defaults preserve user content.
- Model.swift owns async/errors/OCR revisions and successful save/copy acknowledgment, not visual-only success.
- Windows retains matching information architecture, not Apple native components. Browser CSS is an explicitly labeled approximation, never proof of capture or native materials.

## Verification
Release build/self-test plus current native app UI readback at 1240 and 900 point widths. Synthetic image import, actual Vision OCR, copy and PNG export are checked separately from appearance. System dark appearance and app-scoped light/dark appearance verified. Light empty/editor and compact light/dark OCR remain readable; switching preserves content and both exported PNGs equal the imported fixture pixel-for-pixel. Older macOS, reduced transparency/high contrast and Windows runtime remain unverified. Do not change OS settings solely for visual QA. Version-bound artifacts: artifacts/mac-native-style-validation.json and artifacts/mac-appearance-validation.json. Screenshots alone do not prove real screen capture or release readiness.

## Primary references
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/materials

## Competitive baseline, verified 2026-10-11

These are representative specialist references, not a measured ranking or a claim that Framelet already matches them. Facts below come from the vendors' current product/help pages, not hands-on competitor benchmarks.

| Reference | Verified capability relevant to this product | Framelet design implication / remaining gap |
| --- | --- | --- |
| [CleanShot X](https://cleanshot.com/) | Mac-native capture and markup, scrolling capture, on-device text recognition, MP4/GIF export | Keep capture → edit → copy/export short and native. Current app has these implementation paths, but actual capture/recording remains unverified; no equivalence claim. Cloud/history/studio features are not adopted by default. |
| [Snagit features](https://www.techsmith.com/snagit/features/) and [product](https://www.techsmith.com/snagit/) | Scrolling capture, text recognition, annotation and video/GIF; screenshots can be edited on Windows and Mac using a compatible format | Cross-platform means comparable task completion, not just two builds. Framelet currently exports flattened PNG, not a shared editable document; Windows native workflows still require runtime testing. |
| [ShareX](https://getsharex.com/) | Windows region/scrolling capture, GIF recording, OCR, editor and configurable after-capture tasks | Validate keyboard-first operation and reliable file/clipboard completion. Do not copy upload actions into this local-only app; implementation and tests do not prove Windows execution. |
| [Shottr](https://shottr.cc/) | Mac scrolling capture, OCR, annotation, pixel zoom and measurement | Keep original pixels and explicit pixel/point scaling. Its published screenshot/display timings are vendor claims with a different/unspecified test setup, not our performance target or comparative evidence. |

The visual authority remains Ethan's Apple-native request, not any competitor's skin. We borrow workflow principles, not brand assets or proprietary implementation.

## Completion audit, 2026-10-11

Current app/validation hashes were checked against the actual files. This audit does **not** mark the overall task complete.

| User requirement | Evidence available | Missing decisive evidence |
| --- | --- | --- |
| macOS + Windows application | Mac arm64/x86_64 bundles and Windows x64/ARM64 managed/native files exist; Mac signature/bundle checks and Windows PE checks pass | Windows launch, installed MSIX OCR identity, native DLL execution; Intel Mac runtime |
| Screenshot | Mac image editor/export verified with an imported synthetic image; native capture implementations on both platforms | Real permission-authorized capture, display scale and multi-monitor behavior |
| Long screenshot | Shared overlap tests, known synthetic pixel-perfect output, bounded preview microbenchmark | Actual scrolling across representative apps, fixed headers, scroll speed and display scale |
| GIF recording | Mac actual encoder/export tested with synthetic frames/movie; Windows mux and lifecycle tests | Real source frames, playback/duration after pause/stop, resource release and sustained recording on target OS |
| Extract text | Mac Vision succeeds on the imported Chinese/English fixture, with known punctuation/spacing errors; edit protection tested | Windows packaged OCR and language packs; broader OCR accuracy corpus |
| Good performance | Bounded buffers/history and a specific Mac preview microbenchmark | Same-hardware real-capture latency P50/P95, CPU, RSS, dropped frames and battery use; no claim of beating competitor timings |
| Latest Apple-native visual style | Actual AppKit toolbar, semantic colors, SwiftUI content; light/dark editor and OCR screenshots bound to the current Mac binary | Windows rendered UI, reduced-transparency/high-contrast review and older macOS behavior |

Next critical dependency is authorized target-runtime testing, not additional decoration. The user has no Windows environment. On 2026-10-12 the user enabled screen permission; see the current-build update below. Do not install a VM, change capture permissions, or sample private screens to manufacture acceptance evidence. Existing test-window menu opens only a synthetic document; the normal capture path still obtains display images, so authorization limited to that document must not be treated as permission to capture other windows/displays.

## Controlled window capture update, 2026-10-12

The user enabled Framelet in System Settings; the switch was read back as on. The rebuilt app still reports `CGPreflightScreenCaptureAccess() == false`, including after a clean restart of the unchanged final binary. Permission is therefore **not effective for the current build**. Ad-hoc signing changes or duplicate app paths are possible causes, not established facts. No capture was performed.

Added Capture → Only synthetic test window → Screenshot / Long screenshot / Recording / OCR. This entry finds the exact own-process window ID and synthetic title and uses Apple's `SCContentFilter(desktopIndependentWindow:)`; it never freezes a desktop or falls back to a display if the window is unavailable. Shared image, stitching, recording and OCR paths remain in use. The current ARM64 build, synthetic self-tests and bundle validation pass. Window-local crop coordinates and runtime capture remain **NOT_TESTED** until effective permission; Intel remains at the prior appearance build.

Evidence: `artifacts/mac-window-capture-validation.json` and `artifacts/mac-window-capture-bundle-validation.json`. Earlier appearance screenshots remain bound to their older executable, not this new build. The normal full-display selection entry has not been used for scoped validation. Next action is to refresh permission for the exact current app and restart without rebuilding; do not modify TCC databases or broaden test capture scope.

### Permission recovery and first real capture, 2026-10-12

Supersedes the permission blocker immediately above for the unchanged current ARM64 binary. TCC logs confirmed stale code-requirement mismatch (old cdhash versus current binary). The user approved refreshing Framelet permission. Simple toggling and adding over the existing entry did not update it. A narrowly targeted built-in `tccutil reset ScreenCapture local.framelet.app`, followed by adding the exact current app in System Settings, restored access; other app permissions and TCC database files were not modified.

Actual single-window SCK capture now produced a 1904×1480 PNG containing only the synthetic fixture; native display and saved artifact were inspected. Vision OCR on that real capture completed in 602 ms per UI, but omitted some Chinese characters and altered spacing/punctuation. This is scoped functional evidence, not OCR accuracy or overall performance acceptance. Long capture, live recording/GIF and Windows remain pending.

New issue: creating the fixture and capturing immediately initially returned “window unavailable” safely, without desktop fallback. Explicitly opening the fixture before retry succeeded. This suggests a registration/readiness race and remains to be fixed/verified before release. Do not conflate this with permission failure or automatically rebuild the just-authorized app during acceptance.

Current evidence is `artifacts/mac-window-capture-validation.json`, `artifacts/fixtures/real-window-capture.png`, and the real-window screenshots/AX readback named there.
