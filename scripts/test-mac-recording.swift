import AppKit
import AVFoundation
import CryptoKit

func require(_ condition: Bool, _ message: String) throws {
    if !condition {throw FrameletError.message(message)}
}
func time(_ seconds: Double) -> CMTime {CMTime(seconds:seconds,preferredTimescale:600)}
func sample(_ seconds: Double, _ rgb: [UInt8], invalidDuration: Bool = false) throws -> CMSampleBuffer {
    var pixel: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_32BGRA,nil,&pixel)
    guard status == kCVReturnSuccess, let pixel else {throw FrameletError.message("pixel allocation failed")}
    CVPixelBufferLockBaseAddress(pixel,[])
    let bytes = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to:UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixel)
    for y in 0..<240 {for x in 0..<320 {let p = y*stride+x*4;bytes[p] = rgb[2];bytes[p+1] = rgb[1];bytes[p+2] = rgb[0];bytes[p+3] = 255}}
    CVPixelBufferUnlockBaseAddress(pixel,[])
    var format: CMVideoFormatDescription?
    try require(CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescriptionOut:&format) == noErr,"format failed")
    var timing = CMSampleTimingInfo(duration:invalidDuration ? .invalid:time(1.0/30),presentationTimeStamp:time(seconds),decodeTimeStamp:.invalid)
    var result: CMSampleBuffer?
    try require(CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescription:format!,sampleTiming:&timing,sampleBufferOut:&result) == noErr,"sample failed")
    return result!
}
func appendReady(_ encoder: RecordingWriter, _ seconds: Double, _ rgb: [UInt8], invalidDuration: Bool = false) async throws {
    let before = encoder.frameCount, buffer = try sample(seconds,rgb,invalidDuration:invalidDuration)
    for _ in 0..<200 {
        try encoder.append(buffer)
        if encoder.frameCount > before {return}
        try await Task.sleep(for:.milliseconds(5))
    }
    throw FrameletError.message("writer not ready within 1 second")
}
func decode(_ url: URL, _ seconds: Double) async throws -> [Int] {
    let generator = AVAssetImageGenerator(asset:AVURLAsset(url:url))
    generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
    let img = try await generator.image(at:time(seconds)).image
    let p = try Pixels(img), i = ((p.height/2)*p.width+p.width/2)*4
    return [Int(p.data[i]),Int(p.data[i+1]),Int(p.data[i+2])]
}
@main struct RecordingValidation {
    static func main() async {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let directory = root.appendingPathComponent("artifacts/fixtures/mac-recording-test")
        var report: [String:Any] = ["status":"FAIL","scope":"Actual RecordingWriter fed synthetic CMSampleBuffers; not ScreenCaptureKit permission/capture or Windows acceptance","verified_at":ISO8601DateFormatter().string(from:Date())]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var cases: [[String:Any]] = []
            for name in ["static","static-invalid-duration","pause-before-first","paused-static","pause-resume","source-failure","immediate-stop"] {
                let url = directory.appendingPathComponent(name+".mp4")
                if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
                let writer = try RecordingWriter(url:url,width:320,height:240)
                var stop = 102.0, expected = 2.0
                if name == "pause-before-first" {
                    writer.togglePause(at:time(100));writer.togglePause(at:time(104))
                    try await appendReady(writer,105,[240,20,20]);stop = 106;expected = 1
                } else {
                    try await appendReady(writer,100,[240,20,20],invalidDuration:name == "static-invalid-duration")
                }
                if name == "paused-static" {writer.togglePause(at:time(101));stop = 104;expected = 1}
                if name == "immediate-stop" {stop = 100;expected = 1.0/30}
                if name == "pause-resume" {
                    try await appendReady(writer,100.5,[20,230,20])
                    writer.togglePause(at:time(101));try writer.append(sample(102,[240,240,20]))
                    writer.togglePause(at:time(105));try writer.append(sample(104,[240,240,20]))
                    try await appendReady(writer,105.5,[20,20,240]);stop = 106
                    try require(writer.frameCount == 3,"paused or late sample was encoded")
                }
                let result = try await writer.finish(at:time(stop),captureError:name == "source-failure" ? FrameletError.message("Synthetic source disconnected"):nil)
                let duration = try await AVURLAsset(url:url).load(.duration).seconds
                print("\(name): duration=\(duration), expected=\(expected), frames=\(result.frames)")
                try require(abs(duration-expected)<0.05,"\(name) static duration lost: \(duration), expected \(expected)")
                try require(result.duration.isFinite && result.duration > 0 && abs(result.duration-expected)<0.001,"\(name) finalized timeline duration mismatch")
                try require(abs(result.duration-duration)<0.002,"\(name) editor duration differs from actual MP4")
                var timelineColors: [[Int]] = []
                if name == "pause-resume" {
                    for (position,channel) in [(0.25,0),(0.75,1),(1.75,2)] {
                        let color = try await decode(url,position)
                        try require(color[channel] > 170 && color[(channel+1)%3] < 70,"pause compaction moved color phase at \(position)")
                        timelineColors.append(color)
                    }
                }
                let tail = try await decode(url,max(0,expected-0.1))
                let channel = name == "pause-resume" ? 2:0
                try require(tail[channel] > 170 && tail[(channel+1)%3] < 70,"\(name) final frame not retained")
                try require((result.warning != nil) == (name == "source-failure"),"interrupted recording warning missing")
                cases.append(["name":name,"duration":duration,"editor_duration":result.duration,"expected":expected,"input_frames":result.frames,"dropped":result.dropped,"tail_rgb":tail,"timeline_rgb":timelineColors,"warning":result.warning ?? ""])
            }
            let emptyURL = directory.appendingPathComponent("empty.mp4")
            if FileManager.default.fileExists(atPath:emptyURL.path) {try FileManager.default.removeItem(at:emptyURL)}
            let empty = try RecordingWriter(url:emptyURL,width:320,height:240)
            var rejected = false
            do {_ = try await empty.finish(at:time(102),captureError:nil)} catch {rejected = true}
            try require(rejected,"empty recording reported success")
            var invalid = false
            do {_ = try RecordingWriter(url:directory.appendingPathComponent("invalid.mp4"),width:321,height:240)} catch {invalid = true}
            try require(invalid,"odd encoding size accepted")
            report["cases"] = cases;report["empty_rejected"] = rejected;report["odd_size_rejected"] = invalid
            report["status"] = "PASS_SCOPED"
        } catch {report["error"] = String(describing:error)}
        var hashes: [String:String] = [:]
        for file in ["macos/Sources/Framelet/Capture.swift","macos/Sources/Framelet/Model.swift","scripts/test-mac-recording.swift"] {
            if let data = try? Data(contentsOf:root.appendingPathComponent(file)) {hashes[file] = SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        }
        report["sha256"] = hashes
        let output = root.appendingPathComponent("artifacts/mac-recording-validation.json")
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output)}
        print(report)
        if report["status"] as? String != "PASS_SCOPED" {exit(1)}
    }
}
