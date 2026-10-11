using Framelet;
internal static class ShortcutTests
{
    internal static int Run()
    {
        int n = 0;
        void Check(bool ok, string name) { if (!ok) throw new Exception(name); n++; }
        void Reject(Action action, string name) { try { action(); } catch (Exception) { n++; return; } throw new Exception(name); }
        var defaults = ShortcutConfig.Defaults(); defaults.Validate(); Check(defaults.Bindings["shot"] == new ShortcutBinding(6, 50), "original screenshot default");
        Check(defaults.Bindings["ocr"]!.Display == "Ctrl + Shift + 5", "readable binding display");
        foreach (var binding in new[] { new ShortcutBinding(0,65), new ShortcutBinding(2,65), new ShortcutBinding(1,65), new ShortcutBinding(4,65), new ShortcutBinding(10,65), new ShortcutBinding(2,123), new ShortcutBinding(2,27), new ShortcutBinding(2,500) }) Reject(binding.Validate,"invalid combination accepted");
        var duplicate = defaults.Snapshot(); duplicate.Bindings["ocr"] = duplicate.Bindings["shot"]; Reject(duplicate.Validate,"duplicate accepted");
        var badVersion = new ShortcutConfig(2, defaults.Bindings); Reject(badVersion.Validate,"unknown version accepted");
        var missing = defaults.Snapshot(); missing.Bindings.Remove("gif"); Reject(missing.Validate,"missing action accepted");
        var registry = new FakeRegistration(); var persisted = new List<ShortcutConfig>(); bool failSave = false;
        using var manager = new ShortcutCoordinator(registry, c => { if (failSave) throw new IOException("injected persistence failure"); persisted.Add(c); });
        Check(manager.Initialize(defaults).Count == 0 && registry.Live.Count == 4,"four startup bindings");
        Check(persisted.Count == 0,"startup does not rewrite config");
        int shotId = registry.Live.Single(p => p.Value == defaults.Bindings["shot"]).Key;
        Check(manager.TryGetAction(shotId,out var action) && action == "shot","active hotkey resolves action");
        var external = manager.Current; external.Bindings["shot"] = null; Check(manager.Current.Bindings["shot"] != null,"current snapshot cannot mutate coordinator");
        int registrations = registry.Registrations; Reject(() => manager.Apply(duplicate),"duplicate applied"); Check(registry.Registrations == registrations,"duplicate rejected before OS changes");
        var swap = defaults.Snapshot(); (swap.Bindings["shot"],swap.Bindings["ocr"]) = (swap.Bindings["ocr"],swap.Bindings["shot"]);
        manager.Apply(swap); Check(registry.Registrations == registrations && registry.Unregistrations == 0,"swap reuses reserved registrations without gaps"); Check(manager.TryGetAction(shotId,out action) && action == "ocr","swap remaps existing ID");
        var conflict = swap.Snapshot(); conflict.Bindings["shot"] = new(3,65); registry.Denied.Add(conflict.Bindings["shot"]!);
        Reject(() => manager.Apply(conflict),"OS conflict accepted"); Check(manager.Current.Bindings["shot"] == swap.Bindings["shot"] && manager.TryGetAction(shotId,out action) && action == "ocr","OS conflict retains old bindings"); Check(persisted.Count == 1,"OS conflict not persisted");
        var midway = swap.Snapshot(); midway.Bindings["shot"] = new(3,66); midway.Bindings["scroll"] = new(3,65);
        Reject(() => manager.Apply(midway),"partial candidate conflict accepted"); Check(!registry.Live.Values.Contains(new ShortcutBinding(3,66)) && registry.Live.Count == 4,"partial reservation rollback cleans only new IDs");
        var changed = swap.Snapshot(); changed.Bindings["shot"] = new(3,67); failSave = true;
        Reject(() => manager.Apply(changed),"save failure accepted"); Check(registry.Live.Count == 4 && manager.Current.Bindings["shot"] == swap.Bindings["shot"],"persistence failure preserves working bindings");
        registry.FailUnregister = true;
        Reject(() => manager.Apply(changed),"cleanup failure accepted"); int dormant = registry.Live.Single(p => p.Value == changed.Bindings["shot"]).Key;
        Check(!manager.TryGetAction(dormant,out _) && manager.TryGetAction(shotId,out _),"failed rollback candidate never triggers while old ID still works");
        registry.FailUnregister = false; failSave = false; manager.Apply(changed); Check(manager.TryGetAction(dormant,out action) && action == "shot","later save reuses retained reservation");
        var disabled = changed.Snapshot(); disabled.Bindings["gif"] = null; manager.Apply(disabled); Check(manager.Current.Bindings["gif"] == null && registry.Live.Count == 3,"disable unregisters retired combo");
        manager.Apply(defaults); Check(manager.Current.Bindings.SequenceEqual(defaults.Bindings) && registry.Live.Count == 4,"restore defaults succeeds transactionally");
        var startupConflict = new FakeRegistration(); startupConflict.Denied.Add(defaults.Bindings["gif"]!);
        using (var startup = new ShortcutCoordinator(startupConflict,_=>throw new Exception("unexpected startup write"))) { Check(startup.Initialize(defaults).Count == 1,"startup conflict warning"); Check(startup.Current.Bindings["gif"] == null && startup.Current.Bindings["shot"] != null,"startup conflict disables only failed action"); }
        Check(startupConflict.Live.Count == 0,"dispose releases registered shortcuts");
        string temp = Path.Combine(AppContext.BaseDirectory,"shortcut-tests-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
        try
        {
            string path = Path.Combine(temp,"shortcuts.json"); var store = new ShortcutFileStore(path);
            Check(store.Load() == null,"missing file uses caller defaults"); store.Save(defaults); Check(store.Load()!.Bindings.SequenceEqual(defaults.Bindings),"JSON roundtrip preserves defaults");
            store.Save(disabled); Check(store.Load()!.Bindings["gif"] == null,"JSON preserves disabled shortcut");
            byte[] prior = File.ReadAllBytes(path); Reject(()=>store.Save(duplicate),"invalid JSON saved"); Check(File.ReadAllBytes(path).SequenceEqual(prior),"invalid config does not overwrite file");
            File.WriteAllText(path,"{broken"); Reject(()=>store.Load(),"corrupt config accepted"); Check(File.ReadAllText(path)=="{broken","loading error leaves file untouched");
            File.WriteAllText(path,new string(' ',16385)); Reject(()=>store.Load(),"oversize config accepted");
            string directory = Path.Combine(temp,"directory.json"); Directory.CreateDirectory(directory); var failedStore = new ShortcutFileStore(directory);
            var fileRegistry = new FakeRegistration(); using var fileManager = new ShortcutCoordinator(fileRegistry,failedStore.Save); fileManager.Initialize(defaults);
            Reject(()=>fileManager.Apply(changed),"real atomic save failure accepted"); Check(fileRegistry.Live.Count==4 && fileManager.Current.Bindings["shot"]==defaults.Bindings["shot"],"real filesystem failure retains registrations"); Check(!Directory.EnumerateFiles(temp,".framelet-*.tmp").Any(),"config failure cleans staging");
        }
        finally { Directory.Delete(temp,true); }
        manager.Dispose(); Check(registry.Live.Count == 0,"all owned IDs released");
        return n;
    }
    sealed class FakeRegistration : IShortcutRegistration
    {
        internal Dictionary<int,ShortcutBinding> Live = new(); internal HashSet<ShortcutBinding> Denied = new(); internal bool FailUnregister; internal int Registrations,Unregistrations;
        public bool Register(int id,ShortcutBinding binding) { Registrations++; if(Denied.Contains(binding)||Live.Values.Contains(binding))return false;Live.Add(id,binding);return true; }
        public bool Unregister(int id) { Unregistrations++;return !FailUnregister && Live.Remove(id); }
    }
}
