import AppKit
import Vision
import ImageIO
import UniformTypeIdentifiers

@_silgen_name("framelet_overlap")
func framelet_overlap(_ prev: UnsafePointer<UInt8>, _ next: UnsafePointer<UInt8>, _ width: UInt32, _ height: UInt32, _ stride: UInt32) -> Int32

enum FrameletError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
struct Pixels {
    let width: Int, height: Int
    var data: [UInt8]
    init(_ image: CGImage) throws {
        guard image.width <= 8192, image.height <= 40000, image.width * image.height <= 40_000_000 else { throw FrameletError.message("图片超过 4000 万像素上限，请分段处理。") }
        width = image.width; height = image.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        if !ok { throw FrameletError.message("无法读取图像像素。") }
    }
    init(width: Int, height: Int, data: [UInt8]) { self.width = width; self.height = height; self.data = data }
    func image() throws -> CGImage {
        let provider = CGDataProvider(data: Data(data) as CFData)!
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw FrameletError.message("无法合成图像。") }
        return image
    }
}
struct ScrollDocument {
    private(set) var frames: [Pixels] = []
    private(set) var deltas: [Int] = []
    var count: Int { frames.count }
    var height: Int { (frames.first?.height ?? 0) + deltas.reduce(0,+) }
    mutating func append(_ image: CGImage) throws -> Bool {
        let pixels = try Pixels(image)
        guard let previous = frames.last else { frames = [pixels]; return true }
        guard previous.width == pixels.width, previous.height == pixels.height else { throw FrameletError.message("选区尺寸变化，请重新开始。") }
        let delta = previous.data.withUnsafeBufferPointer { a in pixels.data.withUnsafeBufferPointer { b in
            framelet_overlap(a.baseAddress!, b.baseAddress!, UInt32(pixels.width), UInt32(pixels.height), UInt32(pixels.width * 4))
        }}
        if delta == 0 { return false }
        guard delta > 0, delta < pixels.height else { throw FrameletError.message("无法可靠拼接：请减小滚动距离，避免动画或重复内容。已完成片段仍保留。") }
        // The detector deliberately ignores outer sticky UI. Raw-row append is
        // only safe when those omitted overlap edges also agree after shifting.
        // Reject rather than silently duplicate a fixed footer or lose content.
        guard scrollEdgesAgree(previous, pixels, delta: Int(delta)) else {
            throw FrameletError.message("选区边缘含固定栏或变化内容，无法安全拼接。请只框选滚动正文，已完成片段仍保留。")
        }
        guard frames.count < 20, (height + Int(delta)) * pixels.width <= 24_000_000,
              (frames.count + 1) * pixels.data.count <= 160_000_000 else { throw FrameletError.message("达到当前长截图内存上限，请完成并分段截图。") }
        frames.append(pixels); deltas.append(Int(delta)); return true
    }
    mutating func undo() { if frames.count > 1 { frames.removeLast(); deltas.removeLast() } }
    /// Bounded preview directly samples stored strips. It never materializes the
    /// full stitched canvas or copies the retained capture frames.
    func preview(maxDimension: Int = 520) throws -> CGImage {
        guard let first = frames.first, (1...2048).contains(maxDimension) else {throw FrameletError.message("预览尺寸无效。")}
        let ratio = min(1, Double(maxDimension)/Double(max(first.width,height)))
        let w = max(1,Int(Double(first.width)*ratio)), h = max(1,Int(Double(height)*ratio))
        var out = [UInt8](repeating:0,count:w*h*4)
        var ends = [first.height]
        for delta in deltas {ends.append(ends.last!+delta)}
        func row(_ y: Int) -> (Int,Int) {
            let frame = ends.firstIndex(where: {y < $0})!
            let start = frame == 0 ? 0 : ends[frame-1]
            let sourceStart = frame == 0 ? 0 : frames[frame].height-deltas[frame-1]
            return (frame,(sourceStart+y-start)*first.width*4)
        }
        for y in 0..<h {
            let sy = max(0,min(Double(height-1),(Double(y)+0.5)*Double(height)/Double(h)-0.5))
            let y0 = Int(sy), y1 = min(height-1,y0+1), fy = sy-Double(y0)
            let a = row(y0), b = row(y1)
            for x in 0..<w {
                let sx = max(0,min(Double(first.width-1),(Double(x)+0.5)*Double(first.width)/Double(w)-0.5))
                let x0 = Int(sx), x1 = min(first.width-1,x0+1), fx = sx-Double(x0)
                for c in 0..<4 {
                    let top = Double(frames[a.0].data[a.1+x0*4+c])*(1-fx) + Double(frames[a.0].data[a.1+x1*4+c])*fx
                    let bottom = Double(frames[b.0].data[b.1+x0*4+c])*(1-fx) + Double(frames[b.0].data[b.1+x1*4+c])*fx
                    out[(y*w+x)*4+c] = UInt8(max(0,min(255,(top*(1-fy)+bottom*fy).rounded())))
                }
            }
        }
        return try Pixels(width:w,height:h,data:out).image()
    }
    func image() throws -> CGImage {
        guard let first = frames.first else { throw FrameletError.message("还没有截图片段。") }
        var data = first.data
        data.reserveCapacity(height * first.width * 4)
        for (i, delta) in deltas.enumerated() {
            let p = frames[i+1], start = (p.height - delta) * p.width * 4
            data.append(contentsOf: p.data[start...])
        }
        return try Pixels(width: first.width, height: height, data: data).image()
    }
}
// Exhaustive edge-band check (not sampling) of the actual overlapping rows.
// RGB channel noise <= 8 is tolerated, but any larger edge mismatch rejects.
// Blank identical edges cannot reveal a sticky blank bar; crop content-only.
func scrollEdgesAgree(_ previous: Pixels, _ next: Pixels, delta: Int) -> Bool {
    guard previous.width == next.width, previous.height == next.height,
          delta > 0, delta < next.height else { return false }
    let overlap = next.height - delta
    let band = min(max(16, next.height / 8), overlap)
    let rowBytes = next.width * 4
    for y in 0..<overlap where y < band || y >= overlap - band {
        let a = (y + delta) * rowBytes, b = y * rowBytes
        for x in stride(from: 0, to: rowBytes, by: 4) {
            for c in 0..<3 where abs(Int(previous.data[a+x+c]) - Int(next.data[b+x+c])) > 8 {
                return false
            }
        }
    }
    return true
}
struct OCRResult { let text: String; let milliseconds: Int }
func recognize(_ image: CGImage, request: VNRecognizeTextRequest = VNRecognizeTextRequest()) throws -> OCRResult {
    let start = Date()
    try Task.checkCancellation()
    // Stable local CPU fallback: default ANE compilation stalled > 60 s on
    // this host. The supplied request is owned by Model, which can call cancel.
    // Vision cancellation is cooperative; Model must enforce its own UI deadline.
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    // The macOS 14 per-stage CPU configuration still reached stalled ANE loading
    // on the tested host. Retain this deprecated but verified compatibility
    // switch until the replacement is proven on supported OS builds.
    request.usesCPUOnly = true
    try VNImageRequestHandler(cgImage: image).perform([request])
    try Task.checkCancellation()
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    return OCRResult(text: text, milliseconds: Int(Date().timeIntervalSince(start) * 1000))
}
func writePNG(_ image: CGImage, to url: URL) throws {
    let staging = url.deletingLastPathComponent().appendingPathComponent(".framelet-\(UUID().uuidString).png")
    defer {try? FileManager.default.removeItem(at:staging)}
    guard let out = CGImageDestinationCreateWithURL(staging as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw FrameletError.message("无法创建文件。") }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { throw FrameletError.message("图片保存失败。") }
    if FileManager.default.fileExists(atPath:url.path) { _ = try FileManager.default.replaceItemAt(url,withItemAt:staging) }
    else {try FileManager.default.moveItem(at:staging,to:url)}
}

func nsImage(_ image: CGImage) -> NSImage { NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
