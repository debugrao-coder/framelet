// Compiled together with the actual Imaging.swift and Capture.swift by
// scripts/test-mac-media.sh. No screen capture, microphone, or private fixtures.
import AppKit
import AVFoundation
import ImageIO
import CryptoKit
import Foundation

private struct MediaValidationError: Error { let message: String }
private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw MediaValidationError(message: message) }
}
private func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined()
}
private func pixelBuffer(frame: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_32BGRA,
        [kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer)
    guard status == kCVReturnSuccess, let buffer else { throw MediaValidationError(message:"CVPixelBuffer allocation failed") }
    CVPixelBufferLockBaseAddress(buffer,[])
    defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
    let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    // Four unmistakable half-second color changes, plus a moving white square.
    let palette: [[UInt8]] = [[240,20,20],[20,230,20],[20,20,240],[230,220,20]]
    let rgb = palette[frame/15]
    for y in 0..<240 { for x in 0..<320 {
        let white = y >= 10 && y < 34 && x >= (frame*4)%280 && x < (frame*4)%280+24
        let i = y*rowBytes+x*4
        ptr[i] = white ? 250:rgb[2]; ptr[i+1] = white ? 250:rgb[1]; ptr[i+2] = white ? 250:rgb[0]; ptr[i+3] = 255
    }}
    return buffer
}
private func synthesizeMovie(_ output: URL) async throws {
    let writer = try AVAssetWriter(outputURL:output,fileType:.mp4)
    let input = AVAssetWriterInput(mediaType:.video,outputSettings:[
        AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240,
        AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:2_000_000,AVVideoMaxKeyFrameIntervalKey:60]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,
        sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    try require(writer.canAdd(input),"Cannot attach synthetic video input")
    writer.add(input)
    try require(writer.startWriting(),"Cannot start synthetic writer")
    writer.startSession(atSourceTime:.zero)
    let deadline = Date().addingTimeInterval(20)
    for frame in 0..<60 {
        while !input.isReadyForMoreMediaData {
            try require(Date() < deadline && writer.status == .writing,"Synthetic encoder stalled")
            try await Task.sleep(nanoseconds:1_000_000)
        }
        try require(adaptor.append(try pixelBuffer(frame:frame),withPresentationTime:CMTime(value:Int64(frame),timescale:30)),"Synthetic frame append failed")
    }
    writer.endSession(atSourceTime:CMTime(value:2,timescale:1))
    input.markAsFinished()
    await writer.finishWriting()
    try require(writer.status == .completed,"Synthetic MP4 finalization failed")
}
private func centerRGB(_ image: CGImage) throws -> [Int] {
    let pixels = try Pixels(image)
    let i = ((pixels.height/2)*pixels.width+pixels.width/2)*4
    return [Int(pixels.data[i]),Int(pixels.data[i+1]),Int(pixels.data[i+2])]
}
private func expectedColor(_ rgb: [Int], phase: Int) -> Bool {
    // H.264 YUV conversion/color management is lossy: check dominant hue,
    // not exact source RGB values. Four phases are deliberately far apart.
    switch phase {
    case 0: return rgb[0] > 170 && rgb[0] - max(rgb[1],rgb[2]) > 100
    case 1: return rgb[1] > 170 && rgb[1] - max(rgb[0],rgb[2]) > 100
    case 2: return rgb[2] > 170 && rgb[2] - max(rgb[0],rgb[1]) > 100
    default: return rgb[0] > 150 && rgb[1] > 150 && min(rgb[0],rgb[1]) - rgb[2] > 100
    }
}
@main struct TestMacMedia {
    static func main() async {
        let root = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("artifacts/mac-media-validation.json")
        var report: [String:Any] = ["status":"FAIL","scope":"Synthetic MP4 through actual app exportGIF; not native screen recording or Windows acceptance", "timestamp_utc":ISO8601DateFormatter().string(from:Date()),"os":ProcessInfo.processInfo.operatingSystemVersionString]
        do {
            let fixture = root.appendingPathComponent("artifacts/fixtures/mac-media-test",isDirectory:true)
            try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
            let movie = fixture.appendingPathComponent("synthetic-source.mp4"), gif = fixture.appendingPathComponent("actual-export.gif")
            // Only these synthetic outputs belong to this test; no user files.
            for path in [movie,gif] where FileManager.default.fileExists(atPath:path.path) { try FileManager.default.removeItem(at:path) }
            report["source_sha256"] = try Dictionary(uniqueKeysWithValues:["macos/Sources/Framelet/Capture.swift","macos/Sources/Framelet/Imaging.swift","scripts/test-mac-media.swift"].map {($0,try sha256(root.appendingPathComponent($0)))})
            try await synthesizeMovie(movie)
            let asset = AVURLAsset(url:movie)
            let duration = try await asset.load(.duration).seconds
            try require(abs(duration-2) < 0.04,"Synthetic source duration is not 2 seconds")
            report["source_duration_seconds"] = duration
            // Verify the source itself at exact timestamps before testing export.
            let exact = AVAssetImageGenerator(asset:asset)
            exact.requestedTimeToleranceBefore = .zero; exact.requestedTimeToleranceAfter = .zero
            var sourceColors: [[Int]] = []
            for phase in 0..<4 {
                let decoded = try await exact.image(at:CMTime(seconds:Double(phase)*0.5+0.25,preferredTimescale:600)).image
                let rgb = try centerRGB(decoded); sourceColors.append(rgb)
                report["source_center_colors"] = sourceColors
                try require(expectedColor(rgb,phase:phase),"Source color phase mismatch at phase \(phase), RGB \(rgb)")
            }
            report["source_center_colors"] = sourceColors
            let start = Date()
            try await exportGIF(from:movie,to:gif,fps:12,maxWidth:320,range:0...2)
            report["actual_export_duration_ms"] = Int(Date().timeIntervalSince(start)*1000)
            guard let source = CGImageSourceCreateWithURL(gif as CFURL,nil) else {throw MediaValidationError(message:"Cannot read actual GIF")}
            let count = CGImageSourceGetCount(source)
            report["gif_frame_count"] = count
            var delays: [Double] = [], colors: [[Int]] = [], dimensions: [[Int]] = []
            for i in 0..<count {
                guard let frame = CGImageSourceCreateImageAtIndex(source,i,nil) else {throw MediaValidationError(message:"GIF frame decode failed")}
                dimensions.append([frame.width,frame.height]); colors.append(try centerRGB(frame))
                let properties = CGImageSourceCopyPropertiesAtIndex(source,i,nil) as? [CFString:Any]
                let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString:Any]
                let delay = (gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gifProperties?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? -1
                delays.append(delay)
            }
            report["gif_delays_seconds"] = delays;report["gif_total_delay_seconds"] = delays.reduce(0,+)
            report["gif_dimensions"] = dimensions;report["gif_center_colors"] = colors
            report["gif_bytes"] = try Data(contentsOf:gif).count
            report["fixture_paths"] = [movie.path,gif.path]
            let colorChecks = [3,9,15,21].enumerated().map { phase,index in index < colors.count && expectedColor(colors[index],phase:phase) }
            report["checks"] = ["frame_count_24":count == 24,"all_dimensions_320x240":dimensions.allSatisfy{$0 == [320,240]},"per_frame_delay_12fps_centisecond_tolerance":delays.allSatisfy{abs($0-1.0/12.0) <= 0.011},"total_duration_within_one_centisecond":abs(delays.reduce(0,+)-2) <= 0.011,"all_four_color_phases_at_expected_times":colorChecks.allSatisfy{$0}]
            try require(count == 24,"Expected 24 GIF frames")
            try require(dimensions.allSatisfy{$0 == [320,240]},"Unexpected GIF dimensions")
            try require(delays.allSatisfy{abs($0-1.0/12.0) <= 0.011},"Unexpected GIF frame delay")
            try require(abs(delays.reduce(0,+)-2) <= 0.011,"GIF cumulative delay must preserve 2-second source within one centisecond")
            try require(colorChecks.allSatisfy{$0},"Actual GIF does not preserve all four color phases at requested times")
            // Exercise a nonzero trim start plus actual requested downscaling.
            let trimmed = fixture.appendingPathComponent("actual-trimmed-export.gif")
            if FileManager.default.fileExists(atPath:trimmed.path) {try FileManager.default.removeItem(at:trimmed)}
            try await exportGIF(from:movie,to:trimmed,fps:12,maxWidth:160,range:0.5...1.5)
            guard let trimmedSource = CGImageSourceCreateWithURL(trimmed as CFURL,nil) else {throw MediaValidationError(message:"Cannot read trimmed GIF")}
            let trimmedCount = CGImageSourceGetCount(trimmedSource)
            var trimmedColors: [[Int]] = [], trimmedDelays: [Double] = [], trimmedDimensions: [[Int]] = []
            for i in 0..<trimmedCount {
                guard let frame = CGImageSourceCreateImageAtIndex(trimmedSource,i,nil) else {throw MediaValidationError(message:"Trimmed frame decode failed")}
                trimmedColors.append(try centerRGB(frame));trimmedDimensions.append([frame.width,frame.height])
                let properties = CGImageSourceCopyPropertiesAtIndex(trimmedSource,i,nil) as? [CFString:Any]
                let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString:Any]
                trimmedDelays.append((gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gifProperties?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? -1)
            }
            let trimCorrect = trimmedCount == 12 && trimmedDimensions.allSatisfy{$0 == [160,120]} && abs(trimmedDelays.reduce(0,+)-1) <= 0.011 && trimmedColors.count > 9 && expectedColor(trimmedColors[3],phase:1) && expectedColor(trimmedColors[9],phase:2)
            report["trim_validation"] = ["requested_range_seconds":[0.5,1.5],"frame_count":trimmedCount,"dimensions":trimmedDimensions,"center_colors":trimmedColors,"delays_seconds":trimmedDelays,"total_delay_seconds":trimmedDelays.reduce(0,+),"pass":trimCorrect,"path":trimmed.path]
            try require(trimCorrect,"Trimmed export lost correct duration, geometry or green/blue phases")
            report["status"] = "PASS"
        } catch { report["error"] = String(describing:error) }
        do {
            let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
            try data.write(to:output,options:.atomic)
            print(String(data:data,encoding:.utf8)!)
        } catch { fputs("Cannot save validation report: \(error)\n",stderr);exit(2) }
        if report["status"] as? String != "PASS" {exit(1)}
    }
}
