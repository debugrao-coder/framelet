import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenCaptureKit
import AVKit
import Vision

enum CaptureMode: String, CaseIterable, Identifiable {
    case screenshot = "截图", scrolling = "长截图", recording = "录制", text = "提取文字"
    var id: String { rawValue }
    var symbol: String { switch self { case .screenshot: return "viewfinder"; case .scrolling: return "rectangle.portrait"; case .recording: return "record.circle"; case .text: return "text.viewfinder" } }
}
enum DrawTool: String, CaseIterable, Identifiable {
    case pointer = "浏览", rectangle = "矩形", arrow = "箭头", pen = "画笔", cover = "遮盖"
    var id: String { rawValue }
    var symbol: String { switch self { case .pointer: return "cursorarrow"; case .rectangle: return "rectangle"; case .arrow: return "arrow.up.right"; case .pen: return "pencil.tip"; case .cover: return "square.fill" } }
}
struct Mark: Identifiable { let id = UUID(); let tool: DrawTool; var points: [CGPoint]; let width: CGFloat; let color: NSColor }
@MainActor final class AppModel: ObservableObject {
    @Published var image: CGImage?
    @Published var mode: CaptureMode = .screenshot
    @Published var screenshotShortcut = "⌃⇧2"
    @Published var tool: DrawTool = .arrow
    @Published private(set) var annotationHistory = AnnotationHistory<Mark>(cost: {$0.points.count + 1})
    var marks: [Mark] {
        get {annotationHistory.current}
        set {annotationHistory.replace(newValue); saveState.edited()}
    }
    func undoAnnotations() {
        guard !captureActive, annotationHistory.undo() else {return}; saveState.edited()
    }
    func redoAnnotations() {
        guard !captureActive, annotationHistory.redo() else {return}; saveState.edited()
    }
    @Published private(set) var saveState = DocumentSaveState()
    private var copiedOCRText = ""
    @Published var ink: Color = .red
    @Published var lineWidth: Double = 4
    @Published var ocrText = "" {didSet {ocrRevision.changed()}}
    private var ocrRevision = OCRRevision()
    @Published var keepLines = true
    @Published var showOCR = false
    @Published var busy = false
    @Published var status = "本地处理 · 不上传截图"
    @Published var error: String?
    @Published var dark = false
    @Published var movie: URL?
    @Published var player: AVPlayer?
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var gifFPS = 12
    @Published var gifWidth = 960
    @Published var scroll = ScrollDocument()
    @Published var paused = false
    @Published var recording = false
    @Published var elapsed = 0
    @Published var automatic = true
    let service = CaptureService()
    var area: CaptureArea?
    var recorder: Recorder?
    var timer: Timer?
    var onCapture: (() -> Void)?
    var onShowEditor: (() -> Void)?
    var onShowControls: (() -> Void)?
    var onCloseControls: (() -> Void)?
    var exportTask: Task<Void, Never>?
    @Published private(set) var scrollBusy = false
    @Published var scrollPreview: CGImage?
    private var ocrRequest: VNRecognizeTextRequest?
    private var ocrID: UUID?
    private var ocrDeadline: Task<Void, Never>?
    var captureActive: Bool { busy || recording || scroll.count > 0 }
    var hasUnsavedContent: Bool {saveState.isDirty || (!ocrText.isEmpty && ocrText != copiedOCRText)}
    func confirmDiscard() -> Bool {
        guard hasUnsavedContent else {return true}
        let alert = NSAlert();alert.alertStyle = .warning
        alert.messageText = "保留尚未保存的内容？"
        alert.informativeText = "当前有尚未保存或复制的截图、录屏或文字。继续将丢弃这些内容，无法撤销。取消后可先导出或复制。"
        alert.addButton(withTitle:"取消");alert.addButton(withTitle:"放弃并继续")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func discardMovie() {
        player?.pause(); player = nil
        if let movie { try? FileManager.default.removeItem(at:movie) }
        movie = nil
    }
    func cancelOCR() {
        guard ocrID != nil else { return }
        ocrRequest?.cancel(); ocrDeadline?.cancel(); ocrDeadline = nil
        ocrID = nil; busy = false; status = "文字识别已取消"
    }
    func cleanup() { cancelOCR(); discardMovie() }
    func updateScrollPreview() {
        // Allocation depends on thumbnail size, not full stitched canvas size.
        scrollPreview = try? scroll.preview()
    }

    func undoScroll() { guard !scrollBusy else {return}; scroll.undo(); updateScrollPreview() }
    func fail(_ e: Error) { error = e.localizedDescription; status = e.localizedDescription }
    func setImage(_ img: CGImage, isCapture: Bool = false) { cancelOCR(); discardMovie(); image = img; annotationHistory.reset(); saveState.reset(needsSave:isCapture); ocrText = ""; ocrRevision.reset(); copiedOCRText = ""; showOCR = false; status = "\(img.width) × \(img.height) · 本地截图" }
    func openImage() {
        guard !captureActive, confirmDiscard() else {return}
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff,.heic,.webP]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any], let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0, w <= 8192, h <= 40000, w*h <= 24_000_000 else { throw FrameletError.message("图片过大或格式不受支持。") }
            guard let img = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw FrameletError.message("无法读取图片。") }
            setImage(img)
        } catch { fail(error) }
    }
    func rendered() -> CGImage? {
        guard let image else { return nil }; if marks.isEmpty { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h)); ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
        for mark in marks {
            guard let first = mark.points.first, let last = mark.points.last else { continue }
            ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor); ctx.setLineWidth(mark.width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            let r = CGRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(first.x-last.x),height:abs(first.y-last.y))
            switch mark.tool {
            case .rectangle: ctx.stroke(r)
            case .cover: ctx.setFillColor(NSColor.black.cgColor); ctx.fill(r)
            case .arrow:
                ctx.move(to:first); ctx.addLine(to:last); ctx.strokePath()
                let a = atan2(last.y-first.y,last.x-first.x), len = max(14,mark.width*4)
                ctx.move(to:last); ctx.addLine(to:CGPoint(x:last.x-len*cos(a-0.5),y:last.y-len*sin(a-0.5)))
                ctx.move(to:last); ctx.addLine(to:CGPoint(x:last.x-len*cos(a+0.5),y:last.y-len*sin(a+0.5))); ctx.strokePath()
            case .pen: ctx.addLines(between:mark.points); ctx.strokePath()
            case .pointer: break
            }
        }
        return ctx.makeImage()
    }
    func copyImage() {
        guard !busy, let img = rendered() else {return}
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([nsImage(img)]) {saveState.saved(saveState.token);status = "已复制图片"}
        else {status = "复制失败，内容仍保留，请重试或导出。"}
    }
    func saveImage() {
        guard !busy, let img = rendered() else { return }
        let snapshot = saveState.token
        let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "瞬帧-\(stamp()).png"
        guard p.runModal() == .OK, let url = p.url else { return }
        busy = true; status = "正在保存 PNG…"
        Task {
            do {try await Task.detached(priority:.userInitiated) {try writePNG(img,to:url)}.value; saveState.saved(snapshot); status = "已保存 \(url.lastPathComponent)"}
            catch {fail(error)}
            busy = false
        }
    }
    func runOCR() {
        guard !busy, ocrRequest == nil, let img = rendered() else { return }
        if ocrRevision.needsConfirmation(for:ocrText) {
            let alert = NSAlert(); alert.alertStyle = .warning
            alert.messageText = "替换手动修改的文字？"
            alert.informativeText = "重新识别成功后会替换当前文字。取消、识别失败或超时不会清空已有内容。"
            alert.addButton(withTitle:"取消"); alert.addButton(withTitle:"重新识别")
            guard alert.runModal() == .alertSecondButtonReturn else {return}
        }
        let textSnapshot = ocrRevision.token
        let id = UUID(), request = VNRecognizeTextRequest()
        ocrID = id; ocrRequest = request; showOCR = true; busy = true; status = "正在本地识别…"
        ocrDeadline = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(30)) } catch {return}
            guard let self, self.ocrID == id else {return}
            self.cancelOCR(); self.status = "识别超时，已请求取消；可继续编辑或退出。"
        }
        Task {
            defer { ocrRequest = nil }
            do {
                let result = try await Task.detached(priority:.userInitiated) { try recognize(img,request:request) }.value
                guard ocrID == id else {return}
                if !ocrRevision.canApply(textSnapshot) {
                    status = "文字已修改，已保留你的编辑，未覆盖为识别结果。"
                } else if result.text.isEmpty {
                    status = "未识别到文字，已有内容已保留。请尝试更清晰的选区。"
                } else {
                    ocrText = result.text; ocrRevision.recognized(result.text)
                    status = "本地识别 · \(result.milliseconds) ms · 请核对数字与标点"
                }
            } catch { if ocrID == id { fail(error) } }
            if ocrID == id {ocrDeadline?.cancel(); ocrID = nil; busy = false}
        }
    }
    func copyText() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(keepLines ? ocrText:ocrText.replacingOccurrences(of:"\n",with:" "),forType:.string) {copiedOCRText = ocrText;status = "已复制文字"}
        else {status = "复制失败，文字仍保留，请重试。"}
    }
    func begin(_ selected: CaptureArea, frozen: CGImage) {
        area = selected; paused = false; elapsed = 0
        switch mode {
        case .screenshot: setImage(frozen,isCapture:true); onShowEditor?()
        case .text: setImage(frozen); onShowEditor?(); runOCR()
        case .scrolling:
            scroll = ScrollDocument(); do { _ = try scroll.append(frozen) } catch { fail(error); return }
            updateScrollPreview(); status = "请避开固定工具栏；滚动目标窗口后自动拼接。"; onShowControls?()
            timer = Timer.scheduledTimer(withTimeInterval:0.85,repeats:true) { [weak self] _ in Task { @MainActor in guard let self, self.automatic, !self.paused else { return }; self.appendScroll() } }
        case .recording:
            busy = true; status = "正在准备录制…"; onShowControls?()
            Task { [self] in do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Framelet",isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let r = Recorder(url:folder.appendingPathComponent(UUID().uuidString+".mp4")); recorder = r
                try await r.start(area:selected,service:service); recording = true; status = "录制中 · 无音频 · 最长 5 分钟"
                timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in guard let self else { return }; if !self.paused { self.elapsed += 1 }; if self.elapsed >= 300 { self.finish() } } }
            } catch { if let url = recorder?.url {try? FileManager.default.removeItem(at:url)}; recorder = nil; fail(error); onCloseControls?(); onShowEditor?() }; busy = false }
        }
    }
    func appendScroll() {
        guard let area, !scrollBusy else { return }; scrollBusy = true
        Task { do {
            let frame = try await service.image(area)
            // CPU matching is detached; capture controls and cancellation stay responsive.
            let previous = scroll
            let result = try await Task.detached(priority:.userInitiated) { var updated = previous; let changed = try updated.append(frame); return (updated,changed) }.value
            if result.1 { scroll = result.0; updateScrollPreview(); status = "已拼接 \(scroll.count) 段 · \(scroll.height) px" }
        } catch { paused = true; status = error.localizedDescription }; scrollBusy = false }
    }
    func togglePause() { paused.toggle(); if recording { recorder?.togglePause() } }
    func finish() {
        guard !busy else { return }
        guard !scrollBusy else { status = "正在处理当前片段，请稍后完成。"; return }
        timer?.invalidate(); timer = nil
        if scroll.count > 0 {
            busy = true
            let document = scroll
            Task {
                do {let result = try await Task.detached(priority:.userInitiated) {try document.image()}.value; setImage(result,isCapture:true); scroll = ScrollDocument(); scrollPreview = nil; onCloseControls?(); onShowEditor?()}
                catch {fail(error); paused = true}
                busy = false
            }
        } else if let recorder {
            busy = true; recording = false
            Task {
                do {
                    let result = try await recorder.stop()
                    acceptRecording(result)
                } catch {
                    // Only an unsuccessful encoder finalization reaches cleanup.
                    try? FileManager.default.removeItem(at:recorder.url)
                    fail(error)
                }
                self.recorder = nil; busy = false; onCloseControls?(); onShowEditor?()
            }
        }
    }
    /// Nonthrowing adoption: playback/metadata availability cannot invalidate a
    /// successfully finalized file or turn editor setup into destructive cleanup.
    func acceptRecording(_ result: RecordingResult) {
        discardMovie(); movie = result.url; image = nil; annotationHistory.reset()
        ocrText = ""; ocrRevision.reset(); copiedOCRText = ""; saveState.reset(needsSave:true)
        player = AVPlayer(url:result.url); trimStart = 0; trimEnd = result.duration
        status = result.warning.map {"采集中断，已保留可播放片段 · \($0)"}
            ?? "录制完成 · \(result.frames) 帧 · 丢帧 \(result.dropped)"
    }
    func exportMovie(gif: Bool) {
        guard let movie, !busy else { return }; let p = NSSavePanel(); p.allowedContentTypes = gif ? [.gif] : [.mpeg4Movie]; p.nameFieldStringValue = "瞬帧-\(stamp())."+(gif ? "gif":"mp4")
        guard p.runModal() == .OK, let url = p.url else { return }
        busy = true; status = gif ? "正在导出 GIF…" : "正在导出 MP4…"
        let start = trimStart, end = trimEnd, fps = gifFPS, width = gifWidth, snapshot = saveState.token
        exportTask = Task { do {
            // Encode to a sibling staging file; never damage an existing destination on failure.
            let staging = url.deletingLastPathComponent().appendingPathComponent(".framelet-\(UUID().uuidString)."+(gif ? "gif":"mp4"))
            defer { try? FileManager.default.removeItem(at:staging) }
            if gif { try await exportGIF(from:movie,to:staging,fps:fps,maxWidth:width,range:start...max(start,end)) }
            else {
                guard let session = AVAssetExportSession(asset:AVURLAsset(url:movie),presetName:AVAssetExportPresetHighestQuality) else { throw FrameletError.message("无法创建导出任务。") }
                session.outputURL = staging; session.outputFileType = .mp4
                session.timeRange = CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),end:CMTime(seconds:end,preferredTimescale:600))
                await session.export(); guard session.status == .completed else { throw session.error ?? FrameletError.message("导出失败。") }
            }
            if FileManager.default.fileExists(atPath:url.path) { _ = try FileManager.default.replaceItemAt(url,withItemAt:staging) } else { try FileManager.default.moveItem(at:staging,to:url) }
            // A partial export does not acknowledge the unsaved original recording.
            if let duration = try? await AVURLAsset(url:movie).load(.duration), duration.seconds.isFinite,
               start <= 0.001 && end >= duration.seconds-0.001 {saveState.saved(snapshot)}
            status = "已导出 \(url.lastPathComponent)"
        } catch { fail(error) }; busy = false; exportTask = nil }
    }
    func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from:Date()) }
}
