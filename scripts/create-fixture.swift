import AppKit
import ImageIO
import UniformTypeIdentifiers
let dest = URL(fileURLWithPath:CommandLine.arguments[1])
let w = 1600,h = 1000
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:w*4,bitsPerPixel:32)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)!
NSColor.white.setFill(); NSRect(x:0,y:0,width:w,height:h).fill()
let lines: [(String,CGFloat)] = [("瞬帧 · 本地验收样本",44),("为什么需要长截图？",32),("记录完整内容，不遗漏重要的上下文。",26),("截图、长截图、GIF 录屏与文字提取。",26),("Framelet local fixture 2026",26),("Invoice: 1234567890 / Total: 128.50",26),("const count = 42;",26),("数字与代码请核对，不自动改写。",26),("此图片为合成测试，不包含真实工作资料。",22)]
var y:CGFloat = 880
for (text,size) in lines { (text as NSString).draw(at:CGPoint(x:90,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:size>30 ? .semibold:.regular),.foregroundColor:NSColor.black]);y -= size+48 }
NSGraphicsContext.restoreGraphicsState()
let writer = CGImageDestinationCreateWithURL(dest as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(writer,rep.cgImage!,nil);precondition(CGImageDestinationFinalize(writer))
print(dest.path)
