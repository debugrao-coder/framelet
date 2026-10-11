import AppKit

/// Per-process preview/choice. Never writes the global macOS appearance setting.
enum ApplicationAppearance: Int, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色"}
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named:.aqua)
        case .dark: return NSAppearance(named:.darkAqua)
        }
    }
}

extension AppDelegate {
    func installAppearanceMenu(into menu: NSMenu) {
        menu.addItem(.separator())
        let parent = NSMenuItem(title:"应用外观",action:nil,keyEquivalent:"")
        let options = NSMenu(title:"应用外观")
        for mode in ApplicationAppearance.allCases {
            let item = NSMenuItem(title:mode.title,action:#selector(changeAppearance(_:)),keyEquivalent:"")
            item.tag = mode.rawValue; item.target = self; options.addItem(item)
        }
        parent.submenu = options; menu.addItem(parent)
    }
    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let mode = ApplicationAppearance(rawValue:sender.tag) else {return}
        appearanceMode = mode
        NSApp.appearance = mode.appearance
    }
}
