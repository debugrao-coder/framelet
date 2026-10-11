import Foundation
import Carbon

@MainActor func testShortcuts() throws {
    func expect(_ value:Bool,_ message:String) throws {if !value {throw FrameletError.message("shortcuts: " + message)}}
    func rejects(_ bindings:[CaptureShortcut]) -> Bool {do {try CaptureShortcut.validate(bindings);return false} catch {return true}}
    let defaults = CaptureShortcut.defaults
    try CaptureShortcut.validate(defaults)
    try expect(defaults.map(\.label) == ["⌃⇧2","⌃⇧3","⌃⇧4","⌃⇧5"],"default labels")
    var duplicate = defaults;duplicate[1] = duplicate[0]
    try expect(rejects(duplicate),"duplicate accepted")
    duplicate[1].enabled = false;try CaptureShortcut.validate(duplicate)
    var invalid = defaults;invalid[0].modifiers = UInt32(shiftKey)
    try expect(rejects(invalid),"bare shift accepted")
    invalid[0].modifiers = UInt32(cmdKey|shiftKey);invalid[0].key = 20
    try expect(rejects(invalid),"system screenshot shortcut accepted")
    invalid = defaults;invalid[0].key = 65535;try expect(rejects(invalid),"unknown key")
    invalid = defaults;invalid[0].modifiers |= UInt32(1<<31);try expect(rejects(invalid),"unknown modifier")
    try expect(rejects(Array(defaults.prefix(3))),"missing action")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("framelet-shortcuts-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let file = ShortcutFile(url:folder.appendingPathComponent("settings.json"))
    try expect(try file.load() == defaults,"missing file defaults")
    try file.save(defaults);try expect(try file.load() == defaults,"disk roundtrip")
    try Data("invalid".utf8).write(to:file.url)
    do {_ = try file.load();throw FrameletError.message("shortcuts: malformed accepted")} catch is DecodingError {}
    try file.save(defaults)
    var registry:[Int:CaptureShortcut] = [:], rejected = Set<UInt32>()
    var saved:[CaptureShortcut]?;var diskFails = false
    let controller = ShortcutController(initial:defaults,register:{index,binding in
        if rejected.contains(binding.key) || registry.values.contains(where: {$0.key == binding.key && $0.modifiers == binding.modifiers}) {return false}
        registry[index] = binding;return true
    },unregister:{registry.removeAll()},persist:{ value in
        if diskFails {throw FrameletError.message("synthetic disk failure")};saved = value
    })
    controller.start();try expect(controller.available.count == 4 && registry.count == 4,"startup registration")
    controller.draft[0].key = 0;rejected.insert(0)
    try expect(!controller.apply() && controller.active == defaults && registry.count == 4 && saved == nil,"conflict rollback")
    rejected.removeAll();diskFails = true
    try expect(!controller.apply() && controller.active == defaults && registry.count == 4,"disk rollback")
    diskFails = false
    try expect(controller.apply() && saved == controller.active && controller.active[0].key == 0,"successful apply")
    controller.draft.swapAt(0,1)
    try expect(controller.apply() && registry[1]?.key == 0,"swapped bindings")
    controller.draft[2].enabled = false
    try expect(controller.apply() && !controller.available.contains(2) && registry.count == 3,"disabled action")
    let stable = controller.active
    controller.draft[0] = controller.draft[1]
    try expect(!controller.apply() && controller.active == stable && registry.count == 3,"validation preserves registry")
    controller.restoreDraft();try expect(controller.draft == defaults && controller.active == stable,"reset is staged")
    controller.discardDraft();try expect(controller.draft == stable,"cancel restores draft")
    try file.save(stable);try expect(try file.load() == stable,"persist customized and disabled")
    rejected.insert(stable[0].key);controller.start()
    try expect(!controller.available.contains(0),"startup conflict visibility")
    print("PASS: shortcuts validation, reserved/duplicate keys, config roundtrip, conflict and disk failure rollback, swapping, disable, staged defaults, cancel")
}
