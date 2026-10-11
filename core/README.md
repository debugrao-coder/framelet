# Framelet shared overlap core

Dependency-free Rust library; native ABI is fixed by the root `AGENTS.md`.
No network, telemetry, global mutable state, image storage or screen capture.

```c
int32_t framelet_overlap(const uint8_t *prev, const uint8_t *next,
                        uint32_t width, uint32_t height, uint32_t stride);
```

- Input: same-sized **RGBA8**, top-to-bottom rows, stride in **bytes**. Native BGRA buffers must be consistently converted to the documented RGBA contract.
- `> 0`: estimated positive downward scroll in pixels; previous row `y + delta` corresponds to new row `y` within the content band.
- `0`: exact equality of every visible RGBA pixel. Row padding is ignored. Identical blank images correctly return unchanged, not a guessed scroll.
- `-1`: unreliable/ambiguous, insufficient texture, unsupported motion or too little overlap. The caller must pause/retry/manual-fallback, **never append** this result.
- `-2`: null pointer or invalid scalar parameters (safe Rust API also rejects short buffers).

## Build and checks

```sh
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
cargo run --release --example overlap_bench
```

Native linking: library name `framelet_core`; `include/framelet_core.h`. Rust builds `staticlib`, `cdylib`, and `rlib`. On macOS release outputs include `target/release/libframelet_core.a` and `target/release/libframelet_core.dylib`. Windows requires its own Rust target/toolchain build; no Windows runtime validation is implied by a Mac build.

## Memory and ABI safety

Each pointer must cover `(height - 1) * stride + width * 4` **initialized readable bytes**, remain alive and immutable throughout the call, and obey Rust slice allocation/provenance requirements. Aliasing between read-only inputs is allowed. **This ABI cannot inspect allocation lengths or validate arbitrary addresses.** Native callers must check buffer lengths and arithmetic before the call. The safe Rust `overlap` wrapper checks supplied slice lengths.

Checks cap either side at 16,384 pixels, total pixels at 67,108,864 and each buffer span at 268,435,456 bytes, with checked arithmetic before reads. The algorithm borrows the inputs, only stores a bounded candidate list, and creates no image-sized copies. `panic=abort` applies in release; panic catching is not a replacement for input validation. The RGBA alpha channel is ignored during motion scoring; callers should composite transparent frames to the same background first.

## Detection strategy and deliberate limits

1. Scan all visible RGBA bytes for exact unchanged classification.
2. Exclude the outer 1/8 of image height on each end to tolerate modest fixed headers/footers.
3. Search integer positive vertical shifts plus zero using deterministic jittered sampling. Only textured local patches count as matching evidence; blank margins cannot dominate confidence.
4. Recheck the eight strongest candidates with denser sampling. Require sufficient textured support over several rows, at least 85% patch matches, and a 6 percentage point uniqueness margin between verified candidates. Small changed/animated areas and small RGB noise may be tolerated.

This implementation is **conservative, not a guarantee of correct stitching**. It does not estimate header/footer crop boundaries, remove sticky elements, append pixels, or handle horizontal motion, zooming, rotation, fractional-pixel registration or scrolling beyond the overlap window. The caller owns cropping/stitching and must not append a fixed footer as content. Minimum supported changed frame is 16 x 64; smaller exact-equal images still return zero. Required content overlap is at least max(32 pixels, 1/5 height), after the excluded margins and patch safety band. Larger sticky bars, sparse text, highly regular layouts, significant animation and smooth gradients can return `-1` even for real scrolls. Sampling can miss unobserved differences; do not describe accepted matches as proof of whole-frame correctness.

## Evidence scope

Unit tests cover synthetic known offsets, unrelated frames, reverse motion, exact equality, padding, static headers/footers, repeated patterns, blank frames, moderate noise/dynamic regions, null pointers and bounds. The optional benchmark reports only synthetic RGBA registration latency, excluding capture, copies, native UI, compositing and export. These results are **not** real-app scrolling acceptance, end-to-end performance, or Windows runtime evidence.
