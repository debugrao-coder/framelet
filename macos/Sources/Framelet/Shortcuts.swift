import AppKit
import SwiftUI
import Carbon

struct CaptureShortcut: Codable, Equatable, Hashable {
    var key: UInt32
    var modifiers: UInt32
    var enabled = true
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    static let keys: [(UInt32,String)] = [
        (0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),(45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),
        (29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),
        (122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),(101,"F9"),(109,"F10"),(103,"F11"),(111,"F12")]
    static let defaults = [19,20,21,23].map {CaptureShortcut(key:UInt32($0),modifiers:UInt32(controlKey|shiftKey))}
    var label: String {
        guard enabled else {return "未启用"}
        return [(UInt32(controlKey),"⌃"),(UInt32(optionKey),"⌥"),(UInt32(shiftKey),"⇧"),(UInt32(cmdKey),"⌘")].filter {modifiers & $0.0 != 0}.map(\.1).joined() + (Self.keys.first {$0.0 == key}?.1 ?? "?")
    }
    static func validate(_ bindings: [Self]) throws {
        guard bindings.count == CaptureMode.allCases.count else {throw FrameletError.message("快捷键配置数量不正确。")}
        var used = Set<String>()
        for binding in bindings where binding.enabled {
            guard keys.contains(where: {$0.0 == binding.key}), binding.modifiers & ~allowedModifiers == 0,
                  binding.modifiers.nonzeroBitCount >= 2,
                  binding.modifiers & UInt32(cmdKey|controlKey) != 0 else {
                throw FrameletError.message("请使用至少两个修饰键（包含 ⌘ 或 ⌃）加字母、数字或 F1–F12。")
            }
            if binding.modifiers == UInt32(cmdKey|shiftKey), [20,21,23,12].contains(binding.key) {
                throw FrameletError.message("\(binding.label) 是 macOS 常用系统快捷键，请换一个组合。")
            }
            guard used.insert("\(binding.key):\(binding.modifiers)").inserted else {throw FrameletError.message("多个功能不能使用同一个快捷键：\(binding.label)。")}
        }
    }
}

struct ShortcutFile {
    let url: URL
    static var user: Self {Self(url:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Framelet/shortcuts.json"))}
    func load() throws -> [CaptureShortcut] {
        guard FileManager.default.fileExists(atPath:url.path) else {return CaptureShortcut.defaults}
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 16384 else {throw FrameletError.message("快捷键配置过大。")}
        let value = try JSONDecoder().decode([CaptureShortcut].self,from:Data(contentsOf:url))
        try CaptureShortcut.validate(value);return value
    }
    func save(_ value: [CaptureShortcut]) throws {
        try CaptureShortcut.validate(value)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(value).write(to:url,options:.atomic)
    }
}

/// Registry and persistence are injected so conflict/rollback tests never capture screens.
@MainActor final class ShortcutController: ObservableObject {
    @Published private(set) var active: [CaptureShortcut]
    @Published var draft: [CaptureShortcut]
    @Published var message = ""
    private(set) var available = Set<Int>()
    let register: (Int,CaptureShortcut)->Bool
    let unregister: ()->Void
    let persist: ([CaptureShortcut]) throws ->Void
    var changed: (()->Void)?
    init(initial:[CaptureShortcut],register:@escaping (Int,CaptureShortcut)->Bool,unregister:@escaping ()->Void,persist:@escaping ([CaptureShortcut]) throws ->Void) {
        active = initial;draft = initial;self.register = register;self.unregister = unregister;self.persist = persist
    }
    func start() {
        unregister()
        available = install(active)
        message = availabilityMessage()
        changed?()
    }
    private func install(_ list: [CaptureShortcut]) -> Set<Int> {
        var ok = Set<Int>()
        for (index,binding) in list.enumerated() where binding.enabled {if register(index,binding) {ok.insert(index)}}
        return ok
    }
    private func availabilityMessage() -> String {
        let failed = active.indices.filter {active[$0].enabled && !available.contains($0)}
        return failed.isEmpty ? "快捷键已就绪；修改后点击应用。" : "以下快捷键被占用或无法注册：" + failed.map {CaptureMode.allCases[$0].rawValue}.joined(separator:"、") + "。仍可使用菜单。"
    }
    @discardableResult func apply() -> Bool {
        do {try CaptureShortcut.validate(draft)} catch {message = error.localizedDescription;return false}
        let previous = active
        unregister();available.removeAll()
        let installed = install(draft)
        do {
            let failures = draft.indices.filter {draft[$0].enabled && !installed.contains($0)}
            guard failures.isEmpty else {throw FrameletError.message("快捷键被其他应用占用或注册失败：" + failures.map {CaptureMode.allCases[$0].rawValue}.joined(separator:"、"))}
            try persist(draft)
            active = draft;available = installed;message = "已保存并立即生效。";changed?();return true
        } catch {
            unregister();active = previous;available = install(previous)
            let restored = previous.indices.allSatisfy {!previous[$0].enabled || available.contains($0)}
            message = error.localizedDescription + (restored ? " 旧设置已恢复。":" 部分旧快捷键无法恢复，请重新设置；仍可使用菜单。")
            changed?();return false
        }
    }
    func restoreDraft() {draft = CaptureShortcut.defaults;message = "已填入默认值，点击应用后生效。"}
    func discardDraft() {draft = active;message = availabilityMessage()}
}

struct ShortcutSettingsView: View {
    @ObservedObject var shortcuts: ShortcutController
    let close: ()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:12) {
                Image(systemName:"keyboard").font(.system(size:28)).foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:4) {
                    Text("快捷键").font(.title2.weight(.semibold))
                    Text("在任意应用中唤起瞬帧，设置只保存在这台 Mac。").font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(spacing:0) {
                ForEach(Array(CaptureMode.allCases.enumerated()),id:\.offset) { index, mode in
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Toggle(isOn:$shortcuts.draft[index].enabled) {Label(mode.rawValue,systemImage:mode.symbol).frame(width:120,alignment:.leading)}
                            Spacer()
                            Text(shortcuts.draft[index].label).font(.system(.body,design:.monospaced)).foregroundStyle(.secondary)
                            Picker("按键",selection:$shortcuts.draft[index].key) {
                                ForEach(CaptureShortcut.keys,id:\.0) {key,label in Text(label).tag(key)}
                            }.labelsHidden().frame(width:80).accessibilityLabel("\(mode.rawValue)按键")
                        }
                        HStack(spacing:18) {
                            ForEach([(UInt32(controlKey),"⌃ Control"),(UInt32(optionKey),"⌥ Option"),(UInt32(shiftKey),"⇧ Shift"),(UInt32(cmdKey),"⌘ Command")],id:\.0) {flag,title in
                                Toggle(title,isOn:Binding(get:{shortcuts.draft[index].modifiers & flag != 0},set:{ value in
                                    if value {shortcuts.draft[index].modifiers |= flag} else {shortcuts.draft[index].modifiers &= ~flag}
                                })).toggleStyle(.checkbox).accessibilityLabel("\(mode.rawValue) \(title)")
                            }
                        }.disabled(!shortcuts.draft[index].enabled)
                    }.padding(14)
                    if index < CaptureMode.allCases.count-1 {Divider()}
                }
            }.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
            Text("至少两个修饰键，包含 ⌘ 或 ⌃。系统已占用的组合不会强制接管。\n功能启动后仍需选择采集区域；提取文字使用离线 OCR，无需 AI 模型或 API Key。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(shortcuts.message).font(.callout).foregroundStyle(shortcuts.message.contains("失败") || shortcuts.message.contains("不能") ? .red:.secondary).frame(minHeight:36,alignment:.topLeading).accessibilityLabel("快捷键状态：\(shortcuts.message)")
            HStack {
                Button("恢复默认") {shortcuts.restoreDraft()}
                Spacer()
                Button("取消") {shortcuts.discardDraft();close()}.keyboardShortcut(.cancelAction)
                Button("应用") {shortcuts.apply()}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:590)
    }
}

extension AppDelegate {
    func installShortcuts() {
        let file = ShortcutFile.user
        let initial: [CaptureShortcut]
        var loadError: String?
        do {initial = try file.load()} catch {initial = CaptureShortcut.defaults;loadError = "无法读取快捷键配置，已使用默认值：\(error.localizedDescription)"}
        shortcuts = ShortcutController(initial:initial,register:{[weak self] index,binding in
            guard let self else {return false}
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.key,binding.modifiers,EventHotKeyID(signature:0x46524D4C,id:UInt32(index+1)),GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&ref)
            if status == noErr, let ref {self.hotKeys[index] = ref;return true};return false
        },unregister:{[weak self] in
            guard let self else {return};for ref in self.hotKeys.values {UnregisterEventHotKey(ref)};self.hotKeys.removeAll()
        },persist:{try file.save($0)})
        shortcuts.changed = {[weak self] in self?.refreshShortcutLabels()}
        var eventType = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), {_,event,userData -> OSStatus in
            guard let event,let userData else {return noErr}
            var id = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr,
                  id.signature == 0x46524D4C else {return noErr}
            let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let index = Int(id.id)-1
            Task {@MainActor in app.captureShortcut(index)};return noErr
        },1,&eventType,Unmanaged.passUnretained(self).toOpaque(),nil)
        shortcuts.start()
        if let loadError {shortcuts.message = loadError;model.status = loadError}
    }
    func refreshShortcutLabels() {
        guard let shortcuts else {return}
        model.screenshotShortcut = shortcuts.available.contains(0) ? shortcuts.active[0].label : "未启用 / 被占用"
        for (index,item) in captureShortcutMenus.enumerated() {
            item.title = "\(CaptureMode.allCases[index].rawValue)  \(shortcuts.available.contains(index) ? shortcuts.active[index].label : "未启用 / 被占用")"
        }
        statusItem.menu?.items.first?.title = "截图  \(model.screenshotShortcut)"
    }
    @objc func captureFromShortcutMenu(_ item: NSMenuItem) {startCaptureMode(item.tag)}
    func captureShortcut(_ index:Int) {
        guard shortcuts?.available.contains(index) == true else {return}
        if settingsWindow?.isKeyWindow == true {
            shortcuts.message = "已收到「\(CaptureMode.allCases[index].rawValue)」快捷键；设置窗口内不启动屏幕采集。"
            return
        }
        startCaptureMode(index)
    }
    private func startCaptureMode(_ index:Int) {
        guard CaptureMode.allCases.indices.contains(index), !selecting, !model.captureActive, NSApp.modalWindow == nil else {return}
        model.mode = CaptureMode.allCases[index];captureNow()
    }
    @objc func showShortcutSettings() {
        guard !selecting, !model.captureActive, NSApp.modalWindow == nil else {return}
        if settingsWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:638,height:660),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title = "瞬帧设置";window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:ShortcutSettingsView(shortcuts:shortcuts,close:{[weak window] in window?.close()}))
            window.center();settingsWindow = window
        }
        if settingsWindow?.isVisible != true {shortcuts.discardDraft()}
        settingsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
}
