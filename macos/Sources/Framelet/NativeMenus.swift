import AppKit

/// Copy follows the responder chain; undo explicitly routes by text focus.
/// Editing text must never become an image copy or a canvas undo while typing.
extension AppDelegate: NSMenuItemValidation {
    func installDocumentMenus(into root: NSMenu) {
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); let child = NSMenu(title:title)
            item.submenu = child; root.addItem(item); return child
        }
        let file = menu("文件")
        file.addItem(withTitle:"打开图片…",action:#selector(openImage),keyEquivalent:"o")
        file.addItem(withTitle:"导出…",action:#selector(exportDocument),keyEquivalent:"s")
        file.addItem(.separator())
        file.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let edit = menu("编辑")
        edit.addItem(withTitle:"撤销",action:#selector(undoDocument),keyEquivalent:"z").target = self
        let redo = edit.addItem(withTitle:"重做",action:#selector(redoDocument),keyEquivalent:"z")
        redo.target = self
        redo.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(.separator())
        edit.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        edit.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        edit.addItem(.separator())
        let copyImage = edit.addItem(withTitle:"复制图片",action:#selector(toolbarCopy),keyEquivalent:"c")
        copyImage.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(withTitle:"提取图片文字",action:#selector(extractDocumentText),keyEquivalent:"")
    }
    private var editorIsActive: Bool {editor?.isKeyWindow == true && NSApp.modalWindow == nil}
    private var canEditDocument: Bool {editorIsActive && !model.captureActive}
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(changeAppearance(_:)):
            item.state = item.tag == appearanceMode.rawValue ? .on:.off
            return NSApp.modalWindow == nil
        case #selector(openImage): return !model.captureActive && NSApp.modalWindow == nil
        case #selector(exportDocument): return canEditDocument && (model.image != nil || model.movie != nil)
        case #selector(toolbarCopy), #selector(copy(_:)), #selector(extractDocumentText): return canEditDocument && model.image != nil
        case #selector(undoDocument):
            item.title = focusedText == nil ? "撤销标注":"撤销"
            if let text = focusedText {return editorIsActive && (text.undoManager?.canUndo ?? false)}
            return canEditDocument && model.annotationHistory.canUndo
        case #selector(redoDocument):
            item.title = focusedText == nil ? "重做标注":"重做"
            if let text = focusedText {return editorIsActive && (text.undoManager?.canRedo ?? false)}
            return canEditDocument && model.annotationHistory.canRedo
        default: return true
        }
    }
    @objc func exportDocument() {
        guard canEditDocument else {return}
        if model.image != nil {model.saveImage()}
        else if model.movie != nil {model.exportMovie(gif:false)}
    }
    @objc func extractDocumentText() {
        guard canEditDocument else {return}; model.runOCR()
    }
    @objc func copy(_ sender: Any?) {
        guard canEditDocument else {return}; model.copyImage()
    }
    private var focusedText: NSTextView? {editor?.firstResponder as? NSTextView}
    @objc func undoDocument() {
        guard editorIsActive else {return}
        if let text = focusedText {text.undoManager?.undo()}
        else {model.undoAnnotations()}
    }
    @objc func redoDocument() {
        guard editorIsActive else {return}
        if let text = focusedText {text.undoManager?.redo()}
        else {model.redoAnnotations()}
    }
}
