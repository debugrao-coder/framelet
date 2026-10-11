import AppKit
import Foundation
import Vision
import CoreMedia
@MainActor func selfTest() throws {
    try testShortcuts()
    guard ApplicationAppearance.system.appearance == nil,
          ApplicationAppearance.light.appearance?.name == .aqua,
          ApplicationAppearance.dark.appearance?.name == .darkAqua,
          ApplicationAppearance(rawValue:99) == nil
    else {throw FrameletError.message("application appearance mapping")}
    var history = AnnotationHistory<Int>(cost: {_ in 1})
    guard !history.undo(), !history.redo() else {throw FrameletError.message("empty annotation history")}
    history.replace([1]); history.replace([1,2])
    guard history.undo(), history.current == [1], history.redo(), history.current == [1,2] else {throw FrameletError.message("annotation undo redo order")}
    history.replace([])
    guard history.undo(), history.current == [1,2] else {throw FrameletError.message("clear annotations cannot be undone")}
    history.replace([3])
    guard !history.canRedo, !history.redo(), history.current == [3] else {throw FrameletError.message("new annotation did not invalidate redo")}
    history.reset()
    guard history.current.isEmpty, !history.canUndo, !history.canRedo else {throw FrameletError.message("document history leaked")}
    var bounded = AnnotationHistory<Int>(limit:2,costLimit:10,cost: {_ in 1})
    bounded.replace([1]); bounded.replace([2]); bounded.replace([3])
    guard bounded.undo(), bounded.undo(), !bounded.undo(), bounded.current == [1], bounded.redo(), bounded.current == [2] else {throw FrameletError.message("annotation history count bound")}
    var weighted = AnnotationHistory<Int>(costLimit:2,cost: {$0})
    weighted.replace([Int.max]); weighted.replace([1])
    guard weighted.current == [1], !weighted.canUndo else {throw FrameletError.message("annotation budget overflow/truncation")}
    var disabled = AnnotationHistory<Int>(limit:0,cost: {_ in 1}); disabled.replace([1])
    guard disabled.current == [1], !disabled.canUndo else {throw FrameletError.message("zero annotation history limit")}
    var ocr = OCRRevision()
    guard !ocr.needsConfirmation(for:"") else {throw FrameletError.message("empty OCR confirmation")}
    ocr.recognized("Original")
    guard !ocr.needsConfirmation(for:"Original"), ocr.needsConfirmation(for:"Corrected") else {throw FrameletError.message("OCR edit detection failed")}
    let inFlight = ocr.token
    guard ocr.canApply(inFlight) else {throw FrameletError.message("unchanged OCR rejected")}
    ocr.changed()
    guard !ocr.canApply(inFlight) else {throw FrameletError.message("OCR overwrote in-flight edit")}
    let previousText = ocr.token; ocr.reset()
    guard !ocr.canApply(previousText), ocr.recognizedText.isEmpty else {throw FrameletError.message("OCR revision reset failed")}
    var save = DocumentSaveState()
    guard !save.isDirty else {throw FrameletError.message("empty document dirty")}
    save.reset(needsSave:true)
    guard save.isDirty else {throw FrameletError.message("new capture not dirty")}
    let capture = save.token
    guard save.saved(capture), !save.isDirty else {throw FrameletError.message("capture save not acknowledged")}
    save.edited();let edit = save.token;save.edited()
    guard !save.saved(edit), save.isDirty else {throw FrameletError.message("stale save erased later edit")}
    let previous = save.token;save.reset(needsSave:true)
    guard !save.saved(previous), save.isDirty else {throw FrameletError.message("another document marked saved")}
    save.reset(needsSave:false)
    guard !save.isDirty else {throw FrameletError.message("unmodified imported image dirty")}

    // Long images must be inspectable without changing canonical source coordinates.
    let canvasSource = CGSize(width:1600,height:8000), viewport = CGSize(width:848,height:648)
    for (zoom,expected) in [(CanvasZoom.fit,CGFloat(0.075)),(.width,0.5),(.actual,1),(.double,2)] {
        let geometry = CanvasGeometry(source:canvasSource,viewport:viewport,zoom:zoom)
        guard abs(geometry.scale-expected) < 0.000001 else {throw FrameletError.message("canvas zoom scale mismatch")}
        let point = geometry.sourcePoint(CGPoint(x:120*geometry.scale,y:7000*geometry.scale))
        guard abs(point.x-120) < 0.000001, abs(point.y-7000) < 0.000001,
            geometry.sourcePoint(CGPoint(x:-10,y:-10)) == .zero,
            geometry.sourcePoint(CGPoint(x:999999,y:999999)) == CGPoint(x:1600,y:8000)
        else {throw FrameletError.message("zoom annotation coordinate mismatch")}
    }
    let retina = CanvasGeometry(source:canvasSource,viewport:viewport,zoom:.actual,displayScale:2)
    guard retina.scale == 0.5, retina.displayed.width*2 == canvasSource.width,
        retina.sourcePoint(CGPoint(x:100,y:100)) == CGPoint(x:200,y:200)
    else {throw FrameletError.message("Retina actual-pixel zoom mismatch")}
    let tiny = CanvasGeometry(source:canvasSource,viewport:.zero,zoom:.fit)
    guard tiny.scale > 0, tiny.scale.isFinite else {throw FrameletError.message("collapsed canvas invalid scale")}
    let w = 320,h = 240,delta = 70
    var full = [UInt8](repeating:255,count:w*(h+delta)*4)
    for y in 0..<(h+delta) {for x in 0..<w {let i=(y*w+x)*4;full[i]=UInt8((y*17+x*11)%251);full[i+1]=UInt8((y*7+x*19)%253);full[i+2]=UInt8((y*31+x*3)%249)}}
    let a = try Pixels(width:w,height:h,data:Array(full[0..<(w*h*4)])).image()
    let b = try Pixels(width:w,height:h,data:Array(full[(delta*w*4)..<full.count])).image()
    var doc = ScrollDocument();_ = try doc.append(a);_ = try doc.append(b)
    guard doc.height == h+delta,doc.count == 2 else {throw FrameletError.message("scroll height mismatch")}
    let joined = try Pixels(doc.image())
    guard try Pixels(doc.preview(maxDimension:320)).data == full else {throw FrameletError.message("native-size preview pixels mismatch")}
    let small = try doc.preview(maxDimension:104)
    guard small.width == 104, small.height == 100 else {throw FrameletError.message("preview dimensions mismatch")}
    var invalidPreview = false
    do {_ = try doc.preview(maxDimension:0)} catch {invalidPreview = true}
    guard invalidPreview else {throw FrameletError.message("invalid preview accepted")}
    guard joined.data == full else {throw FrameletError.message("scroll output pixel mismatch")}
    guard try doc.append(b) == false else {throw FrameletError.message("duplicate not rejected")}
    doc.undo();guard doc.height == h else {throw FrameletError.message("undo failed")}
    for footer in [false,true] {
        var pa = try Pixels(a), pb = try Pixels(b)
        let row = footer ? h-8 : 0
        for y in row..<(row+8) { for x in 0..<w { for c in 0..<3 {pa.data[(y*w+x)*4+c] = 30;pb.data[(y*w+x)*4+c] = 30} } }
        var guarded = ScrollDocument(); _ = try guarded.append(pa.image())
        var rejected = false
        do {_ = try guarded.append(pb.image())} catch {rejected = true}
        guard rejected, guarded.count == 1 else {throw FrameletError.message("sticky edge not rejected")}
    }
    func t(_ seconds: Double) -> CMTime {CMTime(seconds:seconds,preferredTimescale:600)}
    var timeline = RecordingTimeline();timeline.toggle(at:t(10));timeline.toggle(at:t(20))
    guard timeline.adjusted(t(21))?.seconds == 11, timeline.adjusted(t(19)) == nil else {throw FrameletError.message("pause timeline mismatch")}
    timeline.toggle(at:t(22))
    guard timeline.endTime(at:t(30)).seconds == 12 else {throw FrameletError.message("paused stop mismatch")}
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("framelet-selftest-\(UUID())")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    // Deliberately unreadable media proves adoption does not depend on metadata
    // parsing. This is not a claim that malformed bytes are playable.
    let retained = dir.appendingPathComponent("metadata-unavailable.mp4")
    let sentinel = Data("synthetic metadata unavailable".utf8)
    try sentinel.write(to:retained)
    let model = AppModel()
    model.acceptRecording(RecordingResult(url:retained,duration:2,frames:1,dropped:0,warning:"Synthetic source failure"))
    guard model.movie == retained, model.trimStart == 0, model.trimEnd == 2,
          model.hasUnsavedContent, model.status.contains("Synthetic source failure"),
          try Data(contentsOf:retained) == sentinel
    else {throw FrameletError.message("finalized recording lost during editor adoption")}
    model.cleanup()
    let path = dir.appendingPathComponent("roundtrip.png");try writePNG(a,to:path)
    let source = CGImageSourceCreateWithURL(path as CFURL,nil)!,loaded = CGImageSourceCreateImageAtIndex(source,0,nil)!
    guard try Pixels(loaded).data == Pixels(a).data else {throw FrameletError.message("PNG roundtrip failed")}
    try writePNG(b,to:path)
    let replacement = CGImageSourceCreateWithURL(path as CFURL,nil)!
    guard try Pixels(CGImageSourceCreateImageAtIndex(replacement,0,nil)!).data == Pixels(b).data else {throw FrameletError.message("atomic PNG replacement failed")}
    guard try FileManager.default.contentsOfDirectory(atPath:dir.path).count == 1 else {throw FrameletError.message("PNG staging leaked")}
    print("PASS: finalized recording adoption without metadata dependency, dirty-document revision protection, canvas zoom coordinates and bounds, shared ABI, known scroll pixel-perfect output, duplicate, undo, sticky edge rejection, no-frame pause timeline, PNG roundtrip")
    print("Scope: synthetic integration tests only; native capture, GIF, OCR and Windows runtime not implied.")
}
