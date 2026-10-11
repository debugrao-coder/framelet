// Compile with actual Imaging.swift/Capture.swift via test-mac-preview.sh.
// Synthetic-only correctness and isolated-process preview microbenchmark.
import AppKit
import Foundation
import Darwin

private struct PreviewError: Error { let message:String }
private func require(_ ok:Bool,_ message:String) throws {if !ok {throw PreviewError(message:message)}}
private func syntheticFrame(width:Int,height:Int,worldOffset:Int) throws -> CGImage {
    var data=[UInt8](repeating:255,count:width*height*4)
    for y in 0..<height {for x in 0..<width {
        var v=UInt32(y+worldOffset) &* 1_664_525 ^ UInt32(x) &* 1_013_904_223
        v ^= v >> 13;v = v &* 2_246_822_519
        let i=(y*width+x)*4;data[i]=UInt8(truncatingIfNeeded:v);data[i+1]=UInt8(truncatingIfNeeded:v>>8);data[i+2]=UInt8(truncatingIfNeeded:v>>16)
    }}
    return try Pixels(width:width,height:height,data:data).image()
}
private func document(width:Int,height:Int,delta:Int,count:Int) throws -> ScrollDocument {
    var doc=ScrollDocument()
    for i in 0..<count {try autoreleasepool {
        try require(doc.append(try syntheticFrame(width:width,height:height,worldOffset:i*delta)),"Synthetic frame was not appended")
    }}
    try require(doc.count == count && doc.height == height+(count-1)*delta,"Unexpected stitched geometry")
    return doc
}
// Independent reference works only from an already fully stitched image. Integer
// rational pixel-center coordinates and four weights avoid reproducing the
// production strip locator or its floating-point operation order.
private func reference(_ full:Pixels,width:Int,height:Int) -> [UInt8] {
    var out=[UInt8](repeating:0,count:width*height*4)
    func axis(_ i:Int,_ source:Int,_ dest:Int)->(Int,Int,Int64,Int64) {
        let den=2*dest;let numerator=max(0,min((source-1)*den,(2*i+1)*source-dest))
        let lo=numerator/den
        return (lo,min(source-1,lo+1),Int64(numerator%den),Int64(den))
    }
    for y in 0..<height {
        let (y0,y1,fy,dy)=axis(y,full.height,height)
        for x in 0..<width {
            let (x0,x1,fx,dx)=axis(x,full.width,width),den=dx*dy
            let weights=[(dx-fx)*(dy-fy),fx*(dy-fy),(dx-fx)*fy,fx*fy]
            let indices=[(y0*full.width+x0)*4,(y0*full.width+x1)*4,(y1*full.width+x0)*4,(y1*full.width+x1)*4]
            for c in 0..<4 {
                var sum:Int64=0;for i in 0..<4 {sum += Int64(full.data[indices[i]+c])*weights[i]}
                out[(y*width+x)*4+c]=UInt8((sum+den/2)/den)
            }
        }
    }
    return out
}
private func compare(_ doc:ScrollDocument,maxDimension:Int) throws -> [String:Any] {
    let full=try Pixels(doc.image()),actual=try Pixels(doc.preview(maxDimension:maxDimension))
    let expected=reference(full,width:actual.width,height:actual.height)
    var mismatches=0,maxError=0
    for i in expected.indices {
        let error=abs(Int(expected[i])-Int(actual.data[i]));if error>0 {mismatches += 1};maxError=max(maxError,error)
    }
    var seam=doc.frames.first!.height,seams:[Int]=[]
    for delta in doc.deltas {seams.append(seam);seam += delta}
    var crossingRows=0
    for y in 0..<actual.height {
        let sy=max(0,min(Double(doc.height-1),(Double(y)+0.5)*Double(doc.height)/Double(actual.height)-0.5))
        if seams.contains(where:{Int(sy)<$0 && min(doc.height-1,Int(sy)+1)>=$0}) {crossingRows += 1}
    }
    // Exact .5 ties may differ by 1 due to production Double vs rational
    // arithmetic. Report every differing byte, never label that bit-exact.
    try require(maxError <= 1,"Preview differs from independent bilinear reference by more than one channel unit")
    return ["max_dimension":maxDimension,"width":actual.width,"height":actual.height,"maximum_channel_error":maxError,"different_channel_bytes":mismatches,"bit_exact":mismatches == 0,"bilinear_consistent_within_one_unit":maxError<=1,"sample_rows_crossing_seams":crossingRows]
}
private func peakRSS()->Int64 {var usage=rusage();getrusage(RUSAGE_SELF,&usage);return Int64(usage.ru_maxrss)}
private func oldPreview(_ doc:ScrollDocument) throws -> CGImage {
    let full=try doc.image(),ratio=min(1,520.0/Double(max(full.width,full.height)))
    let w=max(1,Int(Double(full.width)*ratio)),h=max(1,Int(Double(full.height)*ratio))
    guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else {throw PreviewError(message:"Reference CGContext allocation failed")}
    ctx.interpolationQuality = .high;ctx.draw(full,in:CGRect(x:0,y:0,width:w,height:h))
    guard let image=ctx.makeImage() else {throw PreviewError(message:"Reference CGContext output failed")};return image
}
@main struct TestMacPreview {
    static func main() {
        let mode=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"correctness"
        var report:[String:Any]=["status":"FAIL","mode":mode,"scope":"Synthetic retained-frame preview, not screen capture, full app RSS, or Windows evidence","os":ProcessInfo.processInfo.operatingSystemVersionString]
        do {
            if mode == "correctness" {
                var doc=try document(width:320,height:240,delta:70,count:4)
                var checks:[[String:Any]]=[]
                for dimension in [437,137,520,1] {checks.append(try compare(doc,maxDimension:dimension))}
                try require((checks[0]["sample_rows_crossing_seams"] as! Int)>0,"Chosen fixture did not exercise cross-seam interpolation")
                report["four_frame_checks"]=checks
                doc.undo();report["after_undo_checks"]=[try compare(doc,maxDimension:doc.height-7),try compare(doc,maxDimension:137)]
                var rejected=0
                for dim in [0,2049] {do {_=try doc.preview(maxDimension:dim)} catch {rejected += 1}}
                do {_=try ScrollDocument().preview()} catch {rejected += 1}
                try require(rejected==3,"Invalid preview bounds or empty document not rejected")
                report["invalid_input_rejections"]=rejected
            } else {
                try require(mode == "new" || mode == "old","Unknown test mode")
                let doc=try document(width:1920,height:1080,delta:500,count:9)
                let baseline=peakRSS();var times:[Double]=[],checksum=0
                for sample in 0..<11 {
                    try autoreleasepool {
                        let start=DispatchTime.now().uptimeNanoseconds
                        let image=try (mode == "new" ? doc.preview(maxDimension:520):oldPreview(doc))
                        checksum += image.width+image.height
                        let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                        if sample>0 {times.append(elapsed)}
                    }
                }
                let sorted=times.sorted()
                report["frame_count"]=doc.count;report["stitched_size"]=[1920,doc.height];report["preview_size"]=[196,520]
                report["timing_samples_ms"]=times;report["sample_count"]=times.count;report["warmup_count"]=1
                report["p50_ms"]=(sorted[4]+sorted[5])/2;report["nearest_rank_p95_ms"]=sorted[9]
                report["process_peak_rss_bytes"]=peakRSS();report["peak_rss_after_fixture_build_bytes"]=baseline
                report["rss_note"]="Darwin getrusage ru_maxrss is process high-water RSS in bytes; includes fixture construction, loaded frameworks and allocator retention. Separate old/new child processes; not incremental live-app capture memory."
                report["checksum"]=checksum
            }
            report["status"]="PASS"
        } catch {report["error"]=String(describing:error)}
        do {let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)} catch {fputs("JSON error: \(error)\n",stderr);exit(2)}
        if report["status"] as? String != "PASS" {exit(1)}
    }
}
