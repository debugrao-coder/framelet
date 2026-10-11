#ifndef FRAMELET_CORE_H
#define FRAMELET_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* RGBA8, equal-sized, row-major, top-to-bottom images. stride is bytes.
 * Returns vertical pixels to append (>0), exactly unchanged (0), unreliable
 * or unsupported motion (-1), or invalid scalar parameters/null pointers (-2).
 * The algorithm is deliberately conservative; -1 must never be appended.
 *
 * SAFETY: each non-null pointer MUST address at least
 * ((size_t)height - 1) * stride + (size_t)width * 4 readable initialized bytes,
 * valid and immutable for the entire call. The ABI cannot check buffer length,
 * pointer provenance or concurrent mutation. Caller MUST verify lengths first.
 * Buffers may alias. No ownership transfer, callbacks or mutable global state.
 * Caps: width/height <= 16384, pixels <= 67108864, each span <= 268435456.
 * The detector ignores alpha for motion matching, but unchanged requires exact
 * visible RGBA bytes. Composite transparency before calling. See README.md.
 */
int32_t framelet_overlap(const uint8_t *prev, const uint8_t *next,
                        uint32_t width, uint32_t height, uint32_t stride);
#ifdef __cplusplus
}
#endif
#endif
