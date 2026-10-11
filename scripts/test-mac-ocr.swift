import AppKit
import Vision
import CryptoKit
@main struct OCRValidation {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let input = root.appendingPathComponent("artifacts/fixtures/ocr-input.png")
        let source = CGImageSourceCreateWithURL(input as CFURL,nil)!
        let result = try recognize(CGImageSourceCreateImageAtIndex(source,0,nil)!)
        guard result.text.contains("Framelet local fixture 2026"),result.text.contains("1234567890"),result.text.components(separatedBy:"\n").count == 9 else {throw FrameletError.message("OCR fixture regression")}
        let code = try Data(contentsOf:root.appendingPathComponent("macos/Sources/Framelet/Imaging.swift"))
        let payload: [String:Any] = ["status":"PASS_SCOPED","engine":"Vision accurate / verified CPU-only compatibility fallback / zh-Hans + en-US","milliseconds":result.milliseconds,"text":result.text,"source_sha256":SHA256.hash(data:code).map {String(format:"%02x",$0)}.joined(),"scope":"Synthetic 1600x1000 image. Digits and nine lines checked; spacing/punctuation not exact. Not screen capture or universal OCR accuracy."]
        let data = try JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.appendingPathComponent("artifacts/mac-ocr-validation.json")); print(String(data:data,encoding:.utf8)!)
    }
}
