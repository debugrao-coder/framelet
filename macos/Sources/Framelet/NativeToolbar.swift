import AppKit

/// System-owned toolbar: grouping, overflow, material, focus and contrast follow
/// the running macOS release instead of a hand-drawn imitation of its chrome.
extension AppDelegate: NSToolbarDelegate, NSToolbarItemValidation {
    private var commandIDs: [NSToolbarItem.Identifier] {
        ["capture", "open", "export", "copy"].map {NSToolbarItem.Identifier("framelet."+$0)}
    }
    func installNativeToolbar() {
        let toolbar = NSToolbar(identifier:"framelet.editor")
        toolbar.delegate = self; toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        editor.toolbar = toolbar; editor.toolbarStyle = .unified
        editor.titleVisibility = .hidden
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        commandIDs + [.flexibleSpace]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [commandIDs[0], .flexibleSpace, commandIDs[1], commandIDs[2], commandIDs[3]]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == commandIDs[0] {
            let modes = CaptureMode.allCases
            let group = NSToolbarItemGroup(itemIdentifier:id,images:modes.map {NSImage(systemSymbolName:$0.symbol,accessibilityDescription:$0.rawValue)!},selectionMode:.momentary,labels:modes.map(\.rawValue),target:self,action:#selector(toolbarCapture(_:)))
            group.label = "捕获"; group.paletteLabel = "捕获"; group.toolTip = "截图、长截图、录制或提取文字"
            return group
        }
        let item = NSToolbarItem(itemIdentifier:id)
        let title: String, symbol: String, action: Selector
        switch id {
        case commandIDs[1]: title = "打开"; symbol = "folder"; action = #selector(openImage)
        case commandIDs[2]: title = "导出"; symbol = "square.and.arrow.up"; action = #selector(toolbarExport)
        case commandIDs[3]: title = "复制图片"; symbol = "doc.on.doc"; action = #selector(toolbarCopy)
        default: return nil
        }
        item.label = title; item.paletteLabel = title; item.toolTip = title
        item.image = NSImage(systemSymbolName:symbol,accessibilityDescription:title)
        item.target = self; item.action = action
        return item
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case commandIDs[0],commandIDs[1]: return !model.captureActive
        case commandIDs[2],commandIDs[3]: return model.image != nil && !model.busy
        default: return true
        }
    }
    @objc func toolbarCapture(_ group: NSToolbarItemGroup) {
        guard !model.captureActive, CaptureMode.allCases.indices.contains(group.selectedIndex) else {return}
        model.mode = CaptureMode.allCases[group.selectedIndex];captureNow()
    }
    @objc func toolbarExport() {model.saveImage()}
    @objc func toolbarCopy() {model.copyImage()}
}
