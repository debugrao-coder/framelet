//! Bounded, dependency-free downward scroll overlap detection.
//! This is not a general image registration or stitching implementation.

const MAX_SIDE: usize = 16_384;
const MAX_PIXELS: usize = 64 * 1024 * 1024;
const MAX_SPAN: usize = 256 * 1024 * 1024;
const UNRELIABLE: i32 = -1;
const INVALID: i32 = -2;

#[derive(Clone, Copy)]
struct Layout {
    width: usize,
    height: usize,
    stride: usize,
    span: usize,
}

impl Layout {
    fn new(width: u32, height: u32, stride: u32) -> Option<Self> {
        let (width, height, stride) = (width as usize, height as usize, stride as usize);
        if width == 0 || height == 0 || width > MAX_SIDE || height > MAX_SIDE {
            return None;
        }
        if width.checked_mul(height)? > MAX_PIXELS || stride < width.checked_mul(4)? {
            return None;
        }
        let span = (height - 1).checked_mul(stride)?.checked_add(width * 4)?;
        if span > MAX_SPAN || span > isize::MAX as usize {
            return None;
        }
        Some(Self {
            width,
            height,
            stride,
            span,
        })
    }
}

/// Compare two equal-layout RGBA images, returning appended rows or a negative
/// status. Invalid scalar values and null pointers are rejected before reads.
///
/// # Safety
/// Both pointers must reference initialized, readable allocations of at least
/// `(height - 1) * stride + width * 4` bytes, kept immutable throughout this
/// call. The caller must check actual allocation lengths and pointer validity;
/// an FFI pointer carries no length and cannot be safely validated here. Images
/// may alias. Scalar caps do not make an otherwise invalid pointer safe.
#[no_mangle]
pub unsafe extern "C" fn framelet_overlap(
    prev: *const u8,
    next: *const u8,
    width: u32,
    height: u32,
    stride: u32,
) -> i32 {
    let Some(layout) = Layout::new(width, height, stride) else {
        return INVALID;
    };
    if prev.is_null() || next.is_null() {
        return INVALID;
    }
    // SAFETY: required by the caller contract above. Layout checked all scalar
    // multiplication/addition and ensured span <= isize::MAX.
    let a = unsafe { std::slice::from_raw_parts(prev, layout.span) };
    let b = unsafe { std::slice::from_raw_parts(next, layout.span) };
    detect(a, b, layout)
}

/// Length-checked Rust entry point. This rejects short buffers before indexing.
pub fn overlap(prev: &[u8], next: &[u8], width: u32, height: u32, stride: u32) -> i32 {
    let Some(layout) = Layout::new(width, height, stride) else {
        return INVALID;
    };
    if prev.len() < layout.span || next.len() < layout.span {
        return INVALID;
    }
    detect(prev, next, layout)
}

fn detect(a: &[u8], b: &[u8], l: Layout) -> i32 {
    // This full check, not sampling, is the sole path to "unchanged". Ignore
    // row padding, which can be uninitialized by native capture APIs (callers
    // must still initialize the full ABI span before constructing the buffer).
    if (0..l.height).all(|y| {
        let i = y * l.stride;
        a[i..i + l.width * 4] == b[i..i + l.width * 4]
    }) {
        return 0;
    }
    if l.width < 16 || l.height < 64 {
        return UNRELIABLE;
    }

    // Exclude the outer eighth to avoid modest fixed toolbars/footers. With a
    // downward scroll, compare a[y + delta] to b[y] inside both content bands.
    let margin = l.height / 8;
    let min_overlap = (l.height / 5).max(32);
    let Some(max_delta) = l.height.checked_sub(2 * margin + min_overlap + 3) else {
        return UNRELIABLE;
    };
    let mut candidates: Vec<(usize, f64)> = Vec::with_capacity(8);
    // Include zero as a competitor: a static region must not manufacture a
    // positive offset when only a caret or animation changes.
    for delta in 0..=max_delta {
        let s = score(a, b, l, delta, margin, 24, 40);
        if s.support < 24 || s.rows < 4 || s.ratio < 0.72 {
            continue;
        }
        candidates.push((delta, s.ratio));
        candidates.sort_unstable_by(|x, y| y.1.total_cmp(&x.1).then(x.0.cmp(&y.0)));
        candidates.truncate(8);
    }
    if candidates.is_empty() {
        return UNRELIABLE;
    }
    let mut verified: Vec<(usize, f64)> = candidates
        .into_iter()
        .filter_map(|(delta, _)| {
            let s = score(a, b, l, delta, margin, 96, 96);
            (s.support >= 64 && s.rows >= 8 && s.ratio >= 0.85).then_some((delta, s.ratio))
        })
        .collect();
    verified.sort_unstable_by(|x, y| y.1.total_cmp(&x.1).then(x.0.cmp(&y.0)));
    let Some(&(best, quality)) = verified.first() else {
        return UNRELIABLE;
    };
    if best == 0 {
        return UNRELIABLE;
    }
    if verified
        .get(1)
        .is_some_and(|other| quality - other.1 < 0.06)
    {
        return UNRELIABLE;
    }
    best as i32
}

struct Score {
    ratio: f64,
    support: usize,
    rows: usize,
}

fn rgb_distance(a: &[u8], ai: usize, b: &[u8], bi: usize) -> u32 {
    (0..3).map(|c| a[ai + c].abs_diff(b[bi + c]) as u32).sum()
}

fn score(
    a: &[u8],
    b: &[u8],
    l: Layout,
    delta: usize,
    margin: usize,
    row_samples: usize,
    col_samples: usize,
) -> Score {
    let first = margin;
    let end = l.height - margin - delta - 2; // y+1 patch stays within the band
    let rows = row_samples.min(end - first);
    let cols = col_samples.min(l.width - 4);
    let mut support = 0;
    let mut matched = 0;
    let mut supported_rows = 0;
    for r in 0..rows {
        let y = first + (2 * r + 1) * (end - first) / (2 * rows);
        let mut row_matches = 0;
        for c in 0..cols {
            // Cell-centered x sampling, with deterministic row jitter. Jitter
            // avoids always sampling a repeated blank inter-character column.
            let cell = (l.width - 4) / cols;
            let x = ((2 * c + 1) * (l.width - 4) / (2 * cols) + r.wrapping_mul(7) % cell.max(1))
                .min(l.width - 4);
            let ai = (y + delta) * l.stride + x * 4;
            let bi = y * l.stride + x * 4;
            let offsets = [0, 12, l.stride];
            // Flat pixels are not evidence of registration. Text edges and
            // texture supply information; broad white margins do not.
            if rgb_distance(a, ai, a, ai + 12).max(rgb_distance(a, ai, a, ai + l.stride)) < 30 {
                continue;
            }
            support += 1;
            let distance: u32 = offsets
                .iter()
                .map(|o| rgb_distance(a, ai + o, b, bi + o))
                .sum();
            if distance <= 72 {
                matched += 1;
                row_matches += 1;
            }
        }
        if row_matches >= 2 {
            supported_rows += 1;
        }
    }
    Score {
        ratio: matched as f64 / support.max(1) as f64,
        support,
        rows: supported_rows,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const W: u32 = 160;
    const H: u32 = 240;
    fn content(world_y: u32, x: u32) -> [u8; 4] {
        let mut v =
            (world_y.wrapping_mul(1_664_525) ^ x.wrapping_mul(1_013_904_223)).wrapping_add(19);
        v ^= v >> 13;
        v = v.wrapping_mul(2_246_822_519);
        [v as u8, (v >> 8) as u8, (v >> 16) as u8, 255]
    }
    fn frame(offset: u32) -> Vec<u8> {
        (0..H)
            .flat_map(|y| (0..W).flat_map(move |x| content(y + offset, x)))
            .collect()
    }
    fn detect_frames(a: &[u8], b: &[u8]) -> i32 {
        overlap(a, b, W, H, W * 4)
    }
    #[test]
    fn known_downward_overlap() {
        for delta in [1, 7, 29, 80, 120] {
            assert_eq!(detect_frames(&frame(0), &frame(delta)), delta as i32);
        }
    }
    #[test]
    fn no_overlap_and_upward_motion() {
        assert_eq!(detect_frames(&frame(0), &frame(1000)), UNRELIABLE);
        assert_eq!(detect_frames(&frame(80), &frame(0)), UNRELIABLE);
    }
    #[test]
    fn unchanged_is_exact() {
        assert_eq!(detect_frames(&frame(0), &frame(0)), 0);
        let mut changed = frame(0);
        changed[20] ^= 128;
        assert_eq!(detect_frames(&frame(0), &changed), UNRELIABLE);
    }
    #[test]
    fn fixed_header_footer() {
        let mut a = frame(0);
        let mut b = frame(40);
        for y in (0..H / 8).chain(H - H / 8..H) {
            for x in 0..W {
                let i = (y * W * 4 + x * 4) as usize;
                a[i..i + 4].copy_from_slice(&content(y, x));
                b[i..i + 4].copy_from_slice(&content(y, x));
            }
        }
        assert_eq!(detect_frames(&a, &b), 40);
    }
    #[test]
    fn blank_and_periodic_content_are_not_positive_evidence() {
        let a = vec![255; (W * H * 4) as usize];
        assert_eq!(detect_frames(&a, &a), 0);
        let mut b = a.clone();
        b[100] = 0;
        assert_eq!(detect_frames(&a, &b), UNRELIABLE);
        let periodic = |offset| {
            (0..H)
                .flat_map(|y| (0..W).flat_map(move |x| content((y + offset) % 12, x)))
                .collect::<Vec<_>>()
        };
        assert_eq!(detect_frames(&periodic(0), &periodic(3)), UNRELIABLE);
    }
    #[test]
    fn modest_noise_and_dynamic_area() {
        let a = frame(0);
        let mut b = frame(35);
        for (i, byte) in b.iter_mut().enumerate() {
            if i % 4 != 3 {
                *byte = byte.saturating_add((i % 4) as u8);
            }
        }
        for y in 60..100 {
            for x in 40..70 {
                let i = ((y * W + x) * 4) as usize;
                b[i..i + 4].copy_from_slice(&[255, 0, 0, 255]);
            }
        }
        assert_eq!(detect_frames(&a, &b), 35);
        assert_eq!(detect_frames(&a, &vec![0; a.len()]), UNRELIABLE);
    }
    #[test]
    fn validates_lengths_dimensions_and_caps() {
        let a = frame(0);
        assert_eq!(overlap(&a, &a, 0, H, W * 4), INVALID);
        assert_eq!(overlap(&a, &a, W, H, W * 4 - 1), INVALID);
        assert_eq!(overlap(&a[..100], &a, W, H, W * 4), INVALID);
        assert_eq!(overlap(&a, &a, u32::MAX, u32::MAX, u32::MAX), INVALID);
        assert_eq!(overlap(&a, &a, 16_384, 16_384, 65_536), INVALID);
        assert_eq!(overlap(&a, &a, 100, 100, u32::MAX), INVALID);
        assert_eq!(
            unsafe { framelet_overlap(std::ptr::null(), a.as_ptr(), W, H, W * 4) },
            INVALID
        );
        assert_eq!(overlap(&[0; 4], &[1; 4], 1, 1, 4), UNRELIABLE);
    }
    #[test]
    fn padding_is_ignored_and_ffi_matches_safe_entry() {
        let stride = W * 4 + 16;
        let span = ((H - 1) * stride + W * 4) as usize;
        let mut a = vec![17; span];
        let mut b = vec![99; span];
        let source = frame(0);
        for y in 0..H as usize {
            a[y * stride as usize..y * stride as usize + W as usize * 4]
                .copy_from_slice(&source[y * W as usize * 4..(y + 1) * W as usize * 4]);
            b[y * stride as usize..y * stride as usize + W as usize * 4]
                .copy_from_slice(&source[y * W as usize * 4..(y + 1) * W as usize * 4]);
        }
        assert_eq!(overlap(&a, &b, W, H, stride), 0);
        assert_eq!(
            unsafe { framelet_overlap(a.as_ptr(), b.as_ptr(), W, H, stride) },
            0
        );
    }
}
