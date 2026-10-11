# Framelet app icon

Current artwork: `framelet-master.png`. Created 2026-10-12 with the built-in image generator; the tool does not expose an explicit model selector. Full initial prompt and refinement intent are in `prompt.txt`.

Direction: blue optical glass tile, four pearl-white capture corners and a central translucent image pane. One recognizable silhouette; no text, brand logo or small feature badges. Square format is intentional for the app-icon target. This is a raster Apple-inspired icon, not a layered Icon Composer asset or a claim of dynamic Liquid Glass behavior.

Run `bash scripts/build-app-icons.sh` from the repository root to convert the checked-in artwork with macOS `sips` and `iconutil`. Python only assembles the ICO container; it does not edit the artwork. Output resources are checked in, so ordinary Windows builds do not require macOS tools.

- macOS: `macos/Resources/Framelet.icns`, connected through `CFBundleIconFile` in `scripts/build-mac.sh`.
- Windows: `windows/Assets/Framelet.ico`, embedded through `ApplicationIcon` in the project. MSIX uses the same artwork at 44, 50 and 150 px instead of the previous generated green placeholder.
- Local app preview: `build/icon-preview/Framelet.app`, resource-updated and ad-hoc signed; bundle and synthetic self-test pass. It has not replaced the authorized capture app at `build/arm64/Framelet.app` and was not launched for new permission prompts.

Validation: `artifacts/app-icon-validation.json`. PNG/ICNS/ICO sizes and alpha decode were checked; all seven ICO image payloads are present in the compiled Windows assembly. Windows Explorer/taskbar/MSIX rendering remains untested. Existing Windows published folders retain their prior executable until republished.

## Installed at user request

On 2026-10-12 Ethan explicitly requested replacing the current app. `build/arm64/Framelet.app` now contains the icon-enabled bundle; the earlier statement that it remained untouched describes the initial asset delivery only. A backup was retained, and the exact path, binary hashes and native About screenshot are in `artifacts/app-icon-installation.json`. Targeted LaunchServices registration and restart resolved the stale placeholder icon. The current version starts and passes synthetic self-tests; screen-capture permissions were not changed or revalidated in this replacement task.
