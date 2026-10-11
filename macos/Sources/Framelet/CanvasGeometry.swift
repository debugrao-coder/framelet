import CoreGraphics

enum CanvasZoom: String, CaseIterable, Identifiable {
    case fit = "适应窗口", width = "适应宽度", actual = "100%", double = "200%"
    var id: String { rawValue }
}

/// Source pixels stay canonical. Zoom affects presentation, never stored annotations.
struct CanvasGeometry {
    let source: CGSize
    let scale: CGFloat
    var displayed: CGSize {CGSize(width:source.width * scale,height:source.height * scale)}
    init(source: CGSize, viewport: CGSize, zoom: CanvasZoom, displayScale: CGFloat = 1) {
        self.source = source
        let w = max(1,viewport.width - 48), h = max(1,viewport.height - 48)
        switch zoom {
        case .fit: scale = min(1,min(w/max(1,source.width),h/max(1,source.height)))
        case .width: scale = min(1,w/max(1,source.width))
        case .actual: scale = 1 / max(1,displayScale)
        case .double: scale = 2 / max(1,displayScale)
        }
    }
    func sourcePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x:min(source.width,max(0,point.x / scale)),y:min(source.height,max(0,point.y / scale)))
    }
}
