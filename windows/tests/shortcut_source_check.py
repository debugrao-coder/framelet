#!/usr/bin/env python3
"""Static native UI wiring contract; not an OS registration/visual execution test."""
import pathlib,json,hashlib
root=pathlib.Path(__file__).resolve().parents[1]
names=['Launcher.cs','ShortcutSettings.cs','ShortcutWindow.cs'];sources={n:(root/n).read_text() for n in names};a,b,c=(sources[n] for n in names);checks=[]
def check(ok,name):
 assert ok,name
 checks.append(name)
check('快捷键设置' in a and 'ShowShortcuts()' in a,'visible settings entry')
check('Environment.SpecialFolder.LocalApplicationData' in a and '"shortcuts.json"' in a,'per-user local persistence')
check('store.Load()' in a and 'store.Save' in a,'real file store wired')
check('AtomicFileSave.Save' in b,'atomic persistence uses tested helper')
check('binding.Modifiers | 0x4000' in a,'MOD_NOREPEAT prevents repeated captures')
check('shortcuts.TryGetAction' in a and 'Capture(action)' in a,'all configured actions route to capture')
check('RecordRegisteredBinding' in a and 'IsKeyboardFocusWithin' in c,'existing hotkeys record into focused settings field, not capture')
check('shortcutSummary.Text' in a and 'shortcuts.Current' in a,'current active bindings displayed')
check('Restore' not in c and '恢复默认' in c and 'draft = ShortcutConfig.Defaults()' in c,'defaults are staged until apply')
check('IsCancel = true' in c and 'coordinator.Apply(draft)' in c,'cancel and explicit apply')
check('ShortcutConfig.Label(action)' in c and 'AutomationProperties.SetName' in c,'native shortcut fields labeled')
check('无需第三方 AI 账号或 API Key' in c and 'Windows 系统 OCR' in c,'OCR local-only explanation')
check('shortcuts?.Dispose()' in a,'owned registrations released on close')
check(b.index('persist(next.Snapshot())')<b.index('current = next; active = wanted;'),'persist before active replacement')
print(json.dumps({'status':'PASS_SCOPED','assertions':len(checks),'scope':'native shortcut source wiring only; actual RegisterHotKey, dialog keys, restart and Windows file persistence NOT_TESTED','checks':checks,'source_sha256':{n:hashlib.sha256(t.encode()).hexdigest() for n,t in sources.items()}},indent=2))
