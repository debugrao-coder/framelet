import AppKit
import SwiftUI
import ScreenCaptureKit
import Carbon
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var editor: NSWindow!
    var statusItem: NSStatusItem!
    var overlays: [NSPanel] = []
    var controls: NSPanel?
    var fixture: NSWindow?
    var hotKeys: [Int:EventHotKeyRef] = [:]
    var shortcuts: ShortcutController!
    var settingsWindow: NSWindow?
    var captureShortcutMenus: [NSMenuItem] = []
    var selecting = false
    var modelChanges: AnyCancellable?
    var appearanceMode: ApplicationAppearance = .system
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle:"关于瞬帧",action:#selector(about),keyEquivalent:""); appMenu.addItem(.separator()); appMenu.addItem(withTitle:"设置…",action:#selector(showShortcutSettings),keyEquivalent:","); appMenu.addItem(.separator()); appMenu.addItem(withTitle:"退出瞬帧",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = appMenu
        installDocumentMenus(into:menu)
        let captureItem = NSMenuItem(); menu.addItem(captureItem); let capture = NSMenu(title:"捕获"); captureItem.submenu = capture
        for (index,mode) in CaptureMode.allCases.enumerated() {
            let entry = capture.addItem(withTitle:mode.rawValue,action:#selector(captureFromShortcutMenu(_:)),keyEquivalent:"")
            entry.tag = index;entry.target = self;captureShortcutMenus.append(entry)
        }
        capture.addItem(withTitle:"打开测试文档",action:#selector(openFixture),keyEquivalent:"")
        let fixtureItem = NSMenuItem(title:"仅采集合成测试窗口",action:nil,keyEquivalent:"")
        let fixtureMenu = NSMenu(title:"仅采集合成测试窗口")
        for (index, mode) in CaptureMode.allCases.enumerated() {
            let item = fixtureMenu.addItem(withTitle:mode.rawValue,action:#selector(captureFixture(_:)),keyEquivalent:"")
            item.tag = index; item.target = self
        }
        fixtureItem.submenu = fixtureMenu; capture.addItem(fixtureItem)
        let windowItem = NSMenuItem(); menu.addItem(windowItem)
        let windowMenu = NSMenu(title:"窗口"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle:"紧凑窗口",action:#selector(compactWindow),keyEquivalent:"")
        windowMenu.addItem(withTitle:"宽屏窗口",action:#selector(wideWindow),keyEquivalent:"")
        installAppearanceMenu(into:windowMenu)
        NSApp.mainMenu = menu
        editor = NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        editor.title = "瞬帧 · Framelet"; editor.titlebarAppearsTransparent = true; editor.isReleasedWhenClosed = false
        editor.contentView = NSHostingView(rootView:EditorView(model:model)); editor.center()
        installNativeToolbar()
        modelChanges = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {self?.editor.toolbar?.validateVisibleItems()}
        }
        model.onCapture = { [weak self] in self?.captureNow() }
        model.onShowEditor = { [weak self] in self?.showEditor() }
        model.onShowControls = { [weak self] in self?.showControls() }
        model.onCloseControls = { [weak self] in self?.controls?.close(); self?.controls = nil }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"viewfinder",accessibilityDescription:"瞬帧")
        let statusMenu = NSMenu(); statusMenu.addItem(withTitle:"截图  ⌃⇧2",action:#selector(captureNow),keyEquivalent:""); statusMenu.addItem(withTitle:"打开编辑器",action:#selector(showEditor),keyEquivalent:""); statusMenu.addItem(withTitle:"快捷键设置…",action:#selector(showShortcutSettings),keyEquivalent:""); statusMenu.addItem(.separator()); statusMenu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:""); statusItem.menu = statusMenu
        installShortcuts()
        if CommandLine.arguments.contains("--fixture") {openFixture()} else {showEditor()}
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"瞬帧 / Framelet",.applicationVersion:"0.1.0 · 本地开发预览",.credits:NSAttributedString(string:"本地优先。无账号、无上传。\n开发版尚未通过双端发布验收。")]) }
    @objc func openImage() {showEditor();model.openImage()}
    @objc func showEditor() {editor.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc func compactWindow() {editor.setContentSize(NSSize(width:900,height:600));showEditor()}
    @objc func wideWindow() {editor.setContentSize(NSSize(width:1240,height:800));showEditor()}
    @objc func openFixture() {
        if fixture == nil { fixture = NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:780),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);fixture!.title = "Framelet 合成验收文档";fixture!.contentView = NSHostingView(rootView:TestDocument());fixture!.isReleasedWhenClosed = false;fixture!.center() }
        fixture!.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    /// Explicit acceptance entry: single-window SCK filter, no desktop freeze.
    @objc func captureFixture(_ sender:NSMenuItem) {
        guard !selecting, !model.captureActive, NSApp.modalWindow == nil,
              CaptureMode.allCases.indices.contains(sender.tag), model.confirmDiscard() else {return}
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            model.error = "当前开发构建尚无屏幕录制权限；请在系统设置中重新允许瞬帧并重启。"
            showEditor();return
        }
        openFixture()
        guard let fixture else {return}
        let windowID = CGWindowID(fixture.windowNumber)
        let selectedMode = CaptureMode.allCases[sender.tag]
        selecting = true
        Task { [self] in
            defer {selecting = false}
            do {
                let content = try await model.service.content()
                guard let window = content.windows.first(where: {
                    $0.windowID == windowID && $0.owningApplication?.processID == getpid()
                    && $0.title == "Framelet 合成验收文档"
                }), let screen = fixture.screen,
                   let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                   let display = content.displays.first(where: {$0.displayID == number.uint32Value}) else {
                    throw FrameletError.message("合成测试窗口不可用；不会回退到桌面采集。")
                }
                let filter = SCContentFilter(desktopIndependentWindow:window)
                // Skip window chrome and scroll indicator; coordinates are window-local points.
                let inset = CGRect(x:24,y:48,width:window.frame.width-48,height:window.frame.height-72)
                guard inset.width > 4, inset.height > 4 else {throw FrameletError.message("测试窗口过小。")}
                let area = CaptureArea(display:display,sourceRect:inset,
                    scale:CGFloat(filter.pointPixelScale),isolatedWindow:window)
                let frozen = try await model.service.image(area)
                model.mode = selectedMode
                editor.orderOut(nil)
                model.begin(area,frozen:frozen)
            } catch {model.fail(error);showEditor()}
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if model.recording || model.busy || model.scroll.count > 0 { let a = NSAlert();a.messageText = "请先完成当前采集或导出";a.informativeText = "完成当前操作后再退出，避免丢失尚未保存的内容。";a.runModal();return .terminateCancel }
        guard model.confirmDiscard() else {return .terminateCancel}
        model.cleanup()
        return .terminateNow
    }
    @objc func captureNow() {
        guard !selecting,!model.busy,!model.recording,model.scroll.count == 0, NSApp.modalWindow == nil else { return }
        guard model.confirmDiscard() else {return}
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            model.error = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许瞬帧，然后重启应用。";showEditor();return
        }
        selecting = true; editor.orderOut(nil)
        Task { [self] in do {
            let content = try await model.service.content()
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber, let display = content.displays.first(where:{$0.displayID == number.uint32Value}) else {continue}
                let scale = screen.backingScaleFactor
                let area = CaptureArea(display:display,sourceRect:CGRect(origin:.zero,size:screen.frame.size),scale:scale)
                // Screenshots include foreground apps; our editor is hidden, overlays not yet shown.
                // Own fixture is explicitly allowed only for the controlled acceptance window.
                let filter = SCContentFilter(display:display,excludingWindows:[])
                let frozen = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:model.service.configuration(area))
                let panel = NSPanel(contentRect:screen.frame,styleMask:[.borderless],backing:.buffered,defer:false)
                panel.level = .screenSaver;panel.isOpaque = true;panel.backgroundColor = .clear;panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary];panel.isReleasedWhenClosed = false
                let view = SelectionView(frame:NSRect(origin:.zero,size:screen.frame.size),image:frozen,model:model)
                view.onCancel = { [weak self] in self?.dismissSelection(); self?.showEditor() }
                view.onComplete = { [weak self] rect in
                    guard let self else{return}
                    let crop = CGRect(x:floor(rect.minX*scale),y:floor(rect.minY*scale),width:floor(rect.width*scale/2)*2,height:floor(rect.height*scale/2)*2)
                    let normalized = CGRect(x:crop.minX/scale,y:crop.minY/scale,width:crop.width/scale,height:crop.height/scale)
                    guard let image = frozen.cropping(to:crop),crop.width>=4,crop.height>=4 else {return}
                    self.dismissSelection()
                    self.model.begin(CaptureArea(display:display,sourceRect:normalized,scale:scale),frozen:image)
                }
                panel.contentView = view;overlays.append(panel)
            }
            guard !overlays.isEmpty else {throw FrameletError.message("未找到可捕获的显示器。")}
            for panel in overlays {panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(panel.contentView)}
            NSApp.activate(ignoringOtherApps:true)
        } catch {dismissSelection();model.fail(error);showEditor()} }
    }
    func dismissSelection() {for panel in overlays {panel.close()};overlays = [];selecting = false}
    func showControls() {
        let p = NSPanel(contentRect:NSRect(x:0,y:0,width:316,height:440),styleMask:[.titled,.nonactivatingPanel,.utilityWindow],backing:.buffered,defer:false)
        p.title = "瞬帧";p.level = .floating;p.isReleasedWhenClosed = false;p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView:CaptureControls(model:model));p.isMovableByWindowBackground = true
        if let screen = NSScreen.main {p.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-340,y:screen.visibleFrame.maxY-490))}
        p.orderFrontRegardless();controls = p
    }
}
final class SelectionView: NSView {
    let image: CGImage
    let model: AppModel
    var onComplete: ((CGRect)->Void)?
    var onCancel: (()->Void)?
    var anchor: CGPoint?
    var selection = CGRect.zero
    var toolbar: NSVisualEffectView!
    var label: NSTextField!
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    @MainActor init(frame:NSRect,image:CGImage,model:AppModel) {
        self.image = image;self.model = model;super.init(frame:frame)
        toolbar = NSVisualEffectView(frame:NSRect(x:20,y:20,width:535,height:52));toolbar.material = .popover;toolbar.blendingMode = .withinWindow;toolbar.state = .active;toolbar.wantsLayer = true;toolbar.layer?.cornerRadius = 12;toolbar.isHidden = true
        let stack = NSStackView();stack.orientation = .horizontal;stack.spacing = 10
        for (i,mode) in CaptureMode.allCases.enumerated() {
            let b = NSButton(title:mode == .recording ? "GIF / 视频":mode.rawValue,target:self,action:#selector(changeMode(_:)));b.tag = i;b.bezelStyle = .rounded;b.image = NSImage(systemSymbolName:mode.symbol,accessibilityDescription:mode.rawValue);b.imagePosition = .imageLeading;b.state = mode == model.mode ? .on:.off;stack.addArrangedSubview(b)
        }
        let cancel = NSButton(title:"取消",target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;stack.addArrangedSubview(cancel)
        let finish = NSButton(title:"完成",target:self,action:#selector(finish));finish.bezelStyle = .rounded;finish.keyEquivalent = "\r";finish.bezelColor = .controlAccentColor;stack.addArrangedSubview(finish)
        stack.translatesAutoresizingMaskIntoConstraints = false;toolbar.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:toolbar.centerXAnchor),stack.centerYAnchor.constraint(equalTo:toolbar.centerYAnchor)])
        addSubview(toolbar)
        label = NSTextField(labelWithString:"拖动框选 · 双击全屏 · Esc 取消");label.font = .systemFont(ofSize:12,weight:.medium);label.textColor = .white;label.backgroundColor = NSColor.black.withAlphaComponent(0.7);label.drawsBackground = true;label.frame = NSRect(x:30,y:30,width:300,height:24);addSubview(label)
    }
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        nsImage(image).draw(in:bounds)
        let mask = NSBezierPath(rect:bounds); if !selection.isEmpty {mask.appendRect(selection)};mask.windingRule = .evenOdd;NSColor.black.withAlphaComponent(0.42).setFill();mask.fill()
        if !selection.isEmpty {NSColor.controlAccentColor.setStroke();let p = NSBezierPath(rect:selection);p.lineWidth = 2;p.stroke()}
    }
    override func mouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if event.clickCount == 2 {selection = bounds;finish();return}
        anchor = point;selection = .zero;toolbar.isHidden = true;needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) {
        guard let a = anchor else{return};let p = convert(event.locationInWindow,from:nil)
        selection = CGRect(x:min(a.x,p.x),y:min(a.y,p.y),width:abs(p.x-a.x),height:abs(p.y-a.y)).intersection(bounds)
        label.stringValue = "\(Int(selection.width)) × \(Int(selection.height)) pt";label.frame.origin = CGPoint(x:selection.minX,y:max(0,selection.minY-28));needsDisplay = true
    }
    override func mouseUp(with event:NSEvent) {anchor = nil;guard selection.width>4,selection.height>4 else{return};toolbar.frame.origin = CGPoint(x:min(bounds.width-555,max(12,selection.midX-267)),y:min(bounds.height-64,selection.maxY+14));toolbar.isHidden = false;needsDisplay = true}
    override func keyDown(with event:NSEvent) {if event.keyCode == 53 {cancel()} else if event.keyCode == 36 {finish()}}
    @objc func changeMode(_ sender:NSButton) {model.mode = CaptureMode.allCases[sender.tag];if let stack = toolbar.subviews.first as? NSStackView {for case let b as NSButton in stack.arrangedSubviews.prefix(4) {b.state = b.tag == sender.tag ? .on:.off}}}
    @objc func cancel(){onCancel?()}
    @objc func finish(){if selection.width>4 && selection.height>4 {onComplete?(selection)}}
}
@main struct FrameletMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { do {try selfTest()} catch {fputs("SELF_TEST_FAILED: \(error)\n",stderr);exit(1)};return }
        let app = NSApplication.shared
        let delegate = AppDelegate();app.delegate = delegate;app.run();withExtendedLifetime(delegate){}
    }
}
