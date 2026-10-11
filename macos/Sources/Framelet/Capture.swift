import AppKit
import ScreenCaptureKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct CaptureArea {
    let display: SCDisplay
    let sourceRect: CGRect // display-local points, top-left origin
    let scale: CGFloat
    // A non-nil target is strictly window-only, never a display fallback.
    var isolatedWindow: SCWindow? = nil
    var width: Int { max(2, Int(sourceRect.width * scale) / 2 * 2) }
    var height: Int { max(2, Int(sourceRect.height * scale) / 2 * 2) }
}
final class CaptureService {
    func content() async throws -> SCShareableContent { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    func filter(_ area: CaptureArea) async throws -> SCContentFilter {
        if let window = area.isolatedWindow {
            guard window.owningApplication?.processID == getpid(),
                  window.title == "Framelet 合成验收文档" else {
                throw FrameletError.message("受控采集目标不是本应用的合成测试窗口。")
            }
            return SCContentFilter(desktopIndependentWindow:window)
        }
        let content = try await content()
        let ours = content.applications.filter { $0.processID == getpid() }
        let fixtures = content.windows.filter { $0.owningApplication?.processID == getpid() && $0.title == "Framelet 合成验收文档" }
        return SCContentFilter(display: area.display, excludingApplications: ours, exceptingWindows: fixtures)
    }
    func configuration(_ area: CaptureArea) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.sourceRect = area.sourceRect; c.width = area.width; c.height = area.height
        c.showsCursor = false; c.queueDepth = 3
        c.capturesAudio = false
        if area.isolatedWindow != nil { c.ignoreShadowsSingleWindow = true }
        c.pixelFormat = kCVPixelFormatType_32BGRA
        return c
    }
    func image(_ area: CaptureArea) async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter(area), configuration: configuration(area))
    }
}
// ScreenCaptureKit PTS and CMClockGetHostTimeClock share the host time domain.
// Record pause boundaries at the user's action, never at a later complete frame.
// Value type accepts explicit times so static-screen pauses can be unit tested.
struct RecordingTimeline {
    private(set) var pauseStart: CMTime?
    private(set) var offset = CMTime.zero
    private(set) var resumeBoundary: CMTime?
    var paused: Bool { pauseStart != nil }
    mutating func toggle(at hostTime: CMTime) {
        if let start = pauseStart {
            offset = CMTimeAdd(offset, CMTimeMaximum(.zero, CMTimeSubtract(hostTime, start)))
            pauseStart = nil
            resumeBoundary = hostTime
        } else {
            pauseStart = hostTime
        }
    }
    func adjusted(_ pts: CMTime) -> CMTime? {
        guard pts.isNumeric, !paused else { return nil }
        // Delayed callbacks from before resume must not use the new offset.
        if let resumeBoundary, CMTimeCompare(pts, resumeBoundary) < 0 { return nil }
        return CMTimeSubtract(pts, offset)
    }
    func endTime(at hostTime: CMTime) -> CMTime {
        CMTimeSubtract(pauseStart ?? hostTime, offset)
    }
}
struct RecordingResult {
    let url: URL
    let duration: Double
    let frames: Int
    let dropped: Int
    let warning: String?
}
/// Serially owned by Recorder's sample queue. Capture and encoding are separate
/// so the exact writer can also be exercised with synthetic CMSampleBuffers.
final class RecordingWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var timeline = RecordingTimeline()
    private var lastPTS: CMTime?
    private var firstPTS: CMTime?
    private(set) var frameCount = 0
    private(set) var dropped = 0
    let url: URL
    init(url: URL, width: Int, height: Int) throws {
        guard width >= 2, height >= 2, width <= 8192, height <= 8192,
              width % 2 == 0, height % 2 == 0, width * height <= 40_000_000
        else {throw FrameletError.message("录制尺寸无效或超过上限。")}
        self.url = url
        writer = try AVAssetWriter(outputURL:url,fileType:.mp4)
        input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:6_000_000,AVVideoMaxKeyFrameIntervalKey:60]])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {throw FrameletError.message("录制编码器不可用。")}
        writer.add(input)
        guard writer.startWriting() else {throw writer.error ?? FrameletError.message("无法开始录制。")}
    }
    func togglePause(at time: CMTime) {timeline.toggle(at:time)}
    func cancel() {writer.cancelWriting()}
    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard sampleBuffer.isValid, CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let pts = timeline.adjusted(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) else {return}
        guard writer.status == .writing else {throw writer.error ?? FrameletError.message("录制编码器已停止。")}
        if let lastPTS, CMTimeCompare(pts,lastPTS) <= 0 {return}
        guard input.isReadyForMoreMediaData else {dropped += 1;return}
        var timing = CMSampleTimingInfo(duration:CMSampleBufferGetDuration(sampleBuffer),presentationTimeStamp:pts,decodeTimeStamp:.invalid)
        var adjusted: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sampleBuffer,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleBufferOut:&adjusted)
        guard status == noErr, let adjusted else {dropped += 1;return}
        if !started {writer.startSession(atSourceTime:pts);started = true;firstPTS = pts}
        guard input.append(adjusted) else {throw writer.error ?? FrameletError.message("录制帧写入失败。")}
        frameCount += 1; lastPTS = pts
    }
    /// Caller stops all append/pause calls before finalizing.
    func finish(at hostTime: CMTime, captureError: Error?) async throws -> RecordingResult {
        guard started, let firstPTS, let lastPTS else {cancel();throw captureError ?? FrameletError.message("未收到画面，录制未保存。请检查权限。")}
        let end = CMTimeMaximum(timeline.endTime(at:hostTime),CMTimeAdd(lastPTS,CMTime(value:1,timescale:30)))
        let duration = CMTimeSubtract(end,firstPTS).seconds
        guard duration.isFinite, duration > 0 else {cancel();throw FrameletError.message("录制时间轴无效。")}
        writer.endSession(atSourceTime:end)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {throw writer.error ?? FrameletError.message("录制保存失败。")}
        // A source disappearing is not a reason to erase a valid finalized movie.
        // Keep the finalized timeline: editor setup must not depend on a second,
        // fallible metadata read that could erase an already completed recording.
        return RecordingResult(url:url,duration:duration,frames:frameCount,dropped:dropped,warning:captureError?.localizedDescription)
    }
}
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label:"framelet.record",qos:.userInitiated)
    private var stream: SCStream?
    private var encoder: RecordingWriter?
    private var failure: Error?
    private var failureTime: CMTime?
    private var active = false
    let url: URL
    init(url: URL) {self.url = url}
    func start(area: CaptureArea, service: CaptureService) async throws {
        let config = service.configuration(area)
        config.minimumFrameInterval = CMTime(value:1,timescale:30);config.showsCursor = true
        let filter = try await service.filter(area)
        let encoder = try RecordingWriter(url:url,width:area.width,height:area.height)
        let stream = SCStream(filter:filter,configuration:config,delegate:self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)
            queue.sync {self.encoder = encoder;active = true}
            try await stream.startCapture()
        } catch {queue.sync {active = false;encoder.cancel()};throw error}
    }
    func togglePause() {
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        queue.sync {encoder?.togglePause(at:time)}
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async {if self.failure == nil {self.failure = error;self.failureTime = time};self.active = false}
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .screen, let encoder else {return}
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]], let status = attachments.first?[.status] as? Int, status != SCFrameStatus.complete.rawValue {return}
        do {try encoder.append(sampleBuffer)} catch {failure = error;failureTime = CMClockGetTime(CMClockGetHostTimeClock());active = false}
    }
    func stop() async throws -> RecordingResult {
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        if let stream {try? await stream.stopCapture()}
        let state = queue.sync {active = false;return (encoder,failure,failureTime ?? time)}
        guard let encoder = state.0 else {throw FrameletError.message("录制尚未开始。")}
        return try await encoder.finish(at:state.2,captureError:state.1)
    }
}
func exportGIF(from movie: URL, to output: URL, fps: Int = 12, maxWidth: Int = 960, range: ClosedRange<Double>? = nil) async throws {
    guard (1...30).contains(fps), (64...1920).contains(maxWidth) else {throw FrameletError.message("GIF 帧率或尺寸超出范围。") }
    let asset = AVURLAsset(url: movie)
    let duration = try await asset.load(.duration).seconds
    let start = max(0, range?.lowerBound ?? 0), end = min(duration, range?.upperBound ?? duration)
    guard start.isFinite, end.isFinite, end > start, end - start <= 60 else { throw FrameletError.message("GIF 最长导出 60 秒，请先裁剪，或保存 MP4。") }
    let count = max(1, Int(ceil((end-start) * Double(fps))))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
    guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw FrameletError.message("无法创建 GIF。") }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<count {
        try Task.checkCancellation()
        let time = CMTime(seconds: min(end-0.001, start + Double(i)/Double(fps)), preferredTimescale: 600)
        let image = try await generator.image(at: time).image
        // GIF stores centiseconds. Distribute rounding rather than accelerating 12 fps to 12.5 fps.
        let tickStart = Int((Double(i)/Double(fps)*100).rounded())
        let tickEnd = Int((min(end-start,Double(i+1)/Double(fps))*100).rounded())
        let delay = Double(max(1,tickEnd-tickStart))/100
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { throw FrameletError.message("GIF 编码失败。") }
}
