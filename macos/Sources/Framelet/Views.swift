import SwiftUI
import AppKit
import AVKit

struct EditorView: View {
    @ObservedObject var model: AppModel
    private var theme: FrameletTheme {FrameletTheme(dark:model.dark)}
    var body: some View {
        VStack(spacing:0) {
            if let image = model.image {
                HStack(spacing:0) {
                    VStack(spacing:12) {
                        ForEach(DrawTool.allCases) { tool in
                            Button { model.tool = tool } label: { Image(systemName:tool.symbol).font(.system(size:18)).frame(width:38,height:38).background(model.tool == tool ? theme.accent.opacity(0.13):.clear,in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain).foregroundStyle(model.tool == tool ? theme.accent:Color.primary).help(tool.rawValue).accessibilityLabel(tool.rawValue)
                        }
                        Divider().padding(.horizontal,12)
                        Button { model.undoAnnotations() } label: { Image(systemName:"arrow.uturn.backward").frame(width:38,height:38) }.buttonStyle(.plain).disabled(!model.annotationHistory.canUndo || model.busy).help("撤销标注").accessibilityLabel("撤销标注")
                        Button { model.redoAnnotations() } label: { Image(systemName:"arrow.uturn.forward").frame(width:38,height:38) }.buttonStyle(.plain).disabled(!model.annotationHistory.canRedo || model.busy).help("重做标注").accessibilityLabel("重做标注")
                        Button { model.runOCR() } label: { Image(systemName:"text.viewfinder").frame(width:38,height:38) }.buttonStyle(.plain).disabled(model.busy).help("提取文字")
                        Spacer()
                    }.padding(.top,18).frame(width:60).background(theme.surface)
                    Divider()
                    ImageCanvas(model:model,source:image).id(ObjectIdentifier(image)).background(theme.canvas)
                    Divider()
                    if model.showOCR { ocrPanel } else { inspector }
                }
            } else if model.movie != nil { movieView }
            else { emptyView }
            Divider()
            HStack(spacing:10) {
                if model.busy { ProgressView().controlSize(.small) }
                Image(systemName:"lock.shield").foregroundStyle(.secondary)
                Text(model.status).lineLimit(2).font(.system(size:12)).foregroundStyle(.secondary)
                Spacer()
                if model.hasUnsavedContent {Text("未保存").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).help("导出或复制后再关闭，避免丢失内容")}
                if let image = model.image { Text("\(image.width) × \(image.height)").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary) }
            }.padding(.horizontal,20).frame(minHeight:36).background(theme.surface)
        }
        .background(theme.surface)

        .alert("未完成操作",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) { Button("知道了",role:.cancel) {model.error = nil} } message: {Text(model.error ?? "")}
        .frame(minWidth:900,minHeight:580)
    }
    var emptyView: some View {
        VStack(spacing:22) {
            Image(systemName:"viewfinder").font(.system(size:44,weight:.ultraLight)).foregroundStyle(Color.accentColor)
            Text("捕捉想表达的瞬间").font(.system(size:27,weight:.semibold))
            Text("截图、长截图、录屏与文字提取。\n在本机完成，不需要账号。").font(.system(size:14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            HStack(spacing:12) {
                Button { model.mode = .screenshot; model.onCapture?() } label: { Label("开始截图",systemImage:"viewfinder").padding(.horizontal,10).padding(.vertical,4) }.buttonStyle(.borderedProminent).tint(FrameletTheme(dark:model.dark).primaryFill)
                Button("打开图片") {model.openImage()}.controlSize(.large)
            }.padding(.top,6)
            Text("\(model.screenshotShortcut)   全局截图快捷键 · ⌘, 设置").font(.system(size:12,design:.monospaced)).foregroundStyle(.tertiary)
            Text("首次采集需允许屏幕录制权限；仅在你启动采集时访问屏幕。").font(.system(size:11)).foregroundStyle(.secondary).padding(.top,30)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    var inspector: some View {
        VStack(alignment:.leading,spacing:22) {
            Text("标注样式").font(.system(size:16,weight:.semibold))
            Divider()
            Text(model.tool.rawValue).font(.system(size:13,weight:.medium))
            ColorPicker("颜色",selection:$model.ink,supportsOpacity:false)
            VStack(alignment:.leading) { Text("线条粗细  \(Int(model.lineWidth)) px").font(.system(size:12)).foregroundStyle(.secondary); Slider(value:$model.lineWidth,in:2...16,step:1) }
            Divider()
            Label("敏感内容请用实色遮盖",systemImage:"lock").font(.system(size:12)).foregroundStyle(.secondary)
            Text("复制与导出会合并标注。原图不被改写。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button {model.runOCR()} label: {Label("提取图片文字",systemImage:"text.viewfinder")}.disabled(model.busy)
            Spacer()
            Button("清除全部标注") {model.marks.removeAll()}.disabled(model.marks.isEmpty || model.busy)
        }.padding(20).frame(width:225).background(theme.surface)
    }
    var ocrPanel: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("提取文字").font(.system(size:17,weight:.semibold)); Spacer(); Button {model.showOCR = false} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("关闭文字面板") }
            Text("离线识别 · 请核对数字、空格与标点").font(.system(size:11)).foregroundStyle(.secondary)
            TextEditor(text:$model.ocrText).font(.system(size:13,design:.monospaced)).scrollContentBackground(.hidden).padding(10).background(theme.canvas,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(theme.line)).accessibilityLabel("识别文字，可编辑")
            Toggle("保留换行",isOn:$model.keepLines).font(.system(size:12))
            HStack { if model.busy { Button("取消") {model.cancelOCR()} }; Button("重新识别") {model.runOCR()}.disabled(model.busy); Spacer(); Button("复制文字") {model.copyText()}.buttonStyle(.borderedProminent).tint(FrameletTheme(dark:model.dark).primaryFill).disabled(model.ocrText.isEmpty) }
        }.padding(20).frame(width:320).background(theme.surface)
    }
    var movieView: some View {
        VStack(spacing:18) {
            if let player = model.player { VideoPlayer(player:player).frame(maxWidth:.infinity,maxHeight:.infinity) }
            HStack {
                Text("导出区间（秒）")
                TextField("起点",value:$model.trimStart,format:.number).frame(width:65)
                Text("至")
                TextField("终点",value:$model.trimEnd,format:.number).frame(width:65)
                Picker("GIF 帧率",selection:$model.gifFPS) { Text("12 fps").tag(12); Text("15 fps").tag(15) }.frame(width:150)
                Picker("最长边",selection:$model.gifWidth) { Text("640 px").tag(640);Text("960 px").tag(960);Text("1280 px").tag(1280) }.frame(width:170)
                Spacer()
                Button("导出 MP4") {model.exportMovie(gif:false)}.disabled(model.busy || model.trimStart < 0 || model.trimEnd <= model.trimStart)
                Button("导出 GIF") {model.exportMovie(gif:true)}.buttonStyle(.borderedProminent).tint(FrameletTheme(dark:model.dark).primaryFill).disabled(model.busy || model.trimStart < 0 || model.trimEnd <= model.trimStart)
            }.font(.system(size:12))
            Text("GIF 无声音，单次最多导出 60 秒。当前录制版本不采集音频。").font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(24)
    }
}
struct ImageCanvas: View {
    @ObservedObject var model: AppModel
    let source: CGImage
    @State private var current: Mark?
    @State private var zoom: CanvasZoom = .fit
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Label("画布",systemImage:"photo").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("画布缩放",selection:$zoom) {
                    ForEach(CanvasZoom.allCases) {Text($0.rawValue).tag($0)}
                }.labelsHidden().frame(width:132).accessibilityLabel("画布缩放")
                Text("滚动查看").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(.horizontal,16).frame(height:42)
            Divider()
            GeometryReader { geo in
            let geometry = CanvasGeometry(source:CGSize(width:source.width,height:source.height),viewport:geo.size,zoom:zoom,displayScale:displayScale)
            let scale = geometry.scale
            let size = geometry.displayed
            ScrollView([.horizontal,.vertical]) {
            ZStack {
                Image(nsImage:nsImage(source)).resizable().interpolation(.high).frame(width:size.width,height:size.height)
                Canvas {ctx,_ in
                    for mark in model.marks + (current.map {[$0]} ?? []) {
                        let points = mark.points.map {CGPoint(x:$0.x*scale,y:$0.y*scale)}
                        guard let a = points.first, let b = points.last else {continue}
                        var p = Path()
                        let r = CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
                        if mark.tool == .rectangle || mark.tool == .cover {p.addRect(r)} else {p.addLines(points)}
                        if mark.tool == .arrow {
                            let angle = atan2(b.y-a.y,b.x-a.x), len = max(14,mark.width*4)*scale
                            p.move(to:b); p.addLine(to:CGPoint(x:b.x-len*cos(angle-0.5),y:b.y-len*sin(angle-0.5)))
                            p.move(to:b); p.addLine(to:CGPoint(x:b.x-len*cos(angle+0.5),y:b.y-len*sin(angle+0.5)))
                        }
                        if mark.tool == .cover {ctx.fill(p,with:.color(.black))} else {ctx.stroke(p,with:.color(Color(nsColor:mark.color)),style:StrokeStyle(lineWidth:mark.width*scale,lineCap:.round,lineJoin:.round))}
                    }
                }.frame(width:size.width,height:size.height)

            }.frame(width:size.width,height:size.height).shadow(color:.black.opacity(0.08),radius:8,y:2)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:1).onChanged { value in
                guard model.tool != .pointer, !model.busy else {current = nil;return}
                let p = geometry.sourcePoint(value.location)
                if current == nil { current = Mark(tool:model.tool,points:[geometry.sourcePoint(value.startLocation)],width:model.lineWidth,color:NSColor(model.ink)) }
                if current?.tool == .pen { current?.points.append(p) } else if let first = current?.points.first { current?.points = [first,p] }
            }.onEnded {_ in if let current { model.marks.append(current) }; current = nil })
            .padding(24)
            .frame(minWidth:max(0,geo.size.width),minHeight:max(0,geo.size.height),alignment:.center)
            }.id(zoom)
            .onChange(of:zoom) {_,_ in current = nil}
            .onChange(of:model.tool) {_,_ in current = nil}
            }
        }
    }
}
struct CaptureControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(model.mode == .scrolling ? "长截图":"录制中",systemImage:model.mode.symbol).font(.system(size:14,weight:.semibold)); Spacer(); if model.mode == .recording { Text(String(format:"%02d:%02d",model.elapsed/60,model.elapsed%60)).monospacedDigit().foregroundStyle(.red) } }
            if model.mode == .scrolling {
                if let image = model.scrollPreview { Image(nsImage:nsImage(image)).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:260).background(Color.white).clipped() }
                Text("已拼接 \(model.scroll.count) 段 · \(model.scroll.height) px").font(.system(size:12)).foregroundStyle(.secondary)
                Toggle("滚动后自动捕获",isOn:$model.automatic).font(.system(size:12))
            }
            Text(model.status).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(4)
            HStack {
                Button(model.paused ? "继续":"暂停") {model.togglePause()}.disabled(model.busy)
                if model.mode == .scrolling { Button("撤回") {model.undoScroll()}.disabled(model.scroll.count<2 || model.scrollBusy); Button("添加") {model.appendScroll()}.disabled(model.busy || model.scrollBusy) }
                Spacer()
                Button(model.mode == .recording ? "停止":"完成") {model.finish()}.buttonStyle(.borderedProminent).tint(FrameletTheme(dark:model.dark).primaryFill).disabled(model.busy)
            }
        }.padding(18).frame(width:280).background(.regularMaterial)
    }
}
struct TestDocument: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("瞬帧 · 捕获验收文档").font(.system(size:28,weight:.semibold))
                Text("这是一份本地合成测试内容。不包含真实账号或工作数据。").foregroundStyle(.secondary)
                ForEach(1...30,id:\.self) { i in
                    VStack(alignment:.leading,spacing:12) {
                        Text(String(format:"%02d  /  记录屏幕上的细节",i)).font(.system(size:20,weight:.semibold))
                        Text("第 \(i) 段：截图、长截图、录屏与文字提取。Framelet sample \(i * 7919) — 用唯一行号检查是否漏行或重复。")
                        Text("Local-first. No account. No upload. 1234567890").font(.system(size:15,design:.monospaced))
                        Divider()
                    }.padding(.vertical,10)
                }
            }.padding(50).frame(maxWidth:1000,alignment:.leading)
        }.background(Color.white).foregroundStyle(.black)
    }
}
