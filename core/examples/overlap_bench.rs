//! Synthetic-only latency probe; not capture, OCR, or end-to-end evidence.
use std::time::Instant;
fn make_frame(w: u32, h: u32, offset: u32) -> Vec<u8> {
    let mut image = vec![0; (w * h * 4) as usize];
    for y in 0..h {
        for x in 0..w {
            let mut v = x.wrapping_mul(1_013_904_223) ^ (y + offset).wrapping_mul(1_664_525);
            v ^= v >> 13;
            v = v.wrapping_mul(2_246_822_519);
            let i = ((y * w + x) * 4) as usize;
            image[i..i + 4].copy_from_slice(&[v as u8, (v >> 8) as u8, (v >> 16) as u8, 255]);
        }
    }
    image
}
fn main() {
    for (w, h, delta) in [(1920, 1080, 300), (3840, 2160, 700)] {
        let prev = make_frame(w, h, 0);
        let next = make_frame(w, h, delta);
        let mut times = Vec::new();
        for _ in 0..10 {
            let start = Instant::now();
            assert_eq!(
                framelet_core::overlap(&prev, &next, w, h, w * 4),
                delta as i32
            );
            times.push(start.elapsed().as_secs_f64() * 1000.0);
        }
        times.sort_by(f64::total_cmp);
        println!("synthetic_rgba={w}x{h} delta={delta} samples=10 median_ms={:.3} nearest_rank_p95_ms={:.3}", (times[4]+times[5])/2.0,times[9]);
    }
}
