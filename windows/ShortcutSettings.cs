using System.IO;
using System.Text.Json;
namespace Framelet;

internal sealed record ShortcutBinding(uint Modifiers, uint Key)
{
    internal string Display => ((Modifiers & 2) != 0 ? "Ctrl + " : "") + ((Modifiers & 1) != 0 ? "Alt + " : "") + ((Modifiers & 4) != 0 ? "Shift + " : "") + (Key >= 112 ? "F" + (Key - 111) : ((char)Key).ToString());
    internal void Validate()
    {
        if ((Modifiers & ~7u) != 0 || (Modifiers & 3) == 0 || Modifiers is 1 or 2 || !(Key is >= 48 and <= 57 or >= 65 and <= 90 or >= 112 and <= 122))
            throw new ArgumentException("快捷键须至少包含两个修饰键（含 Ctrl 或 Alt），搭配字母、数字或 F1–F11；不使用 Windows 键或保留的 F12。");
    }
}
internal sealed record ShortcutConfig(int Version, Dictionary<string, ShortcutBinding?> Bindings)
{
    internal static readonly string[] Actions = ["shot", "scroll", "gif", "ocr"];
    internal static string Label(string action) => action switch { "shot" => "截图", "scroll" => "长截图", "gif" => "GIF 录屏", "ocr" => "提取文字", _ => action };
    internal static ShortcutConfig Defaults() => new(1, new() { ["shot"] = new(6, 0x32), ["scroll"] = new(6, 0x33), ["gif"] = new(6, 0x34), ["ocr"] = new(6, 0x35) });
    internal ShortcutConfig Snapshot() => new(Version, new(Bindings));
    internal void Validate()
    {
        if (Version != 1 || Bindings == null || Bindings.Count != Actions.Length || Actions.Any(a => !Bindings.ContainsKey(a))) throw new ArgumentException("快捷键配置版本或动作无效。");
        var used = new HashSet<ShortcutBinding>();
        foreach (var value in Bindings.Values)
        {
            if (value == null) continue;
            value.Validate();
            if (!used.Add(value)) throw new ArgumentException("快捷键重复：" + value.Display + "。每个组合只能分配给一个动作。");
        }
    }
}
internal sealed class ShortcutFileStore(string path)
{
    internal ShortcutConfig? Load()
    {
        if (!File.Exists(path)) return null;
        using var stream = File.OpenRead(path);
        if (stream.Length > 16384) throw new InvalidDataException("快捷键配置超过 16 KB 上限。");
        var config = JsonSerializer.Deserialize<ShortcutConfig>(stream) ?? throw new InvalidDataException("快捷键配置为空。");
        config.Validate(); return config;
    }
    internal void Save(ShortcutConfig config)
    {
        config.Validate(); Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        AtomicFileSave.Save(path, stream => JsonSerializer.Serialize(stream, config));
    }
}
internal interface IShortcutRegistration
{
    bool Register(int id, ShortcutBinding binding);
    bool Unregister(int id);
}
internal sealed class ShortcutCoordinator(IShortcutRegistration registry, Action<ShortcutConfig> persist) : IDisposable
{
    readonly Dictionary<ShortcutBinding, int> reservations = new();
    Dictionary<int, string> active = new();
    ShortcutConfig current = new(1, ShortcutConfig.Actions.ToDictionary(a => a, _ => (ShortcutBinding?)null));
    int nextId = 100;
    internal ShortcutConfig Current => current.Snapshot();
    int Reserve(ShortcutBinding binding)
    {
        if (reservations.TryGetValue(binding, out int existing)) return existing;
        if (nextId > 0xBFFF) throw new InvalidOperationException("快捷键注册次数达到本次运行上限，请重启应用。");
        int id = nextId++;
        if (!registry.Register(id, binding)) throw new InvalidOperationException("系统无法注册 " + binding.Display + "（可能被其他应用占用）。");
        reservations.Add(binding, id); return id;
    }
    internal List<string> Initialize(ShortcutConfig requested)
    {
        requested.Validate(); if (reservations.Count != 0) throw new InvalidOperationException("快捷键已经初始化。");
        var warnings = new List<string>();
        foreach (string action in ShortcutConfig.Actions)
        {
            if (requested.Bindings[action] is not { } binding) continue;
            try { int id = Reserve(binding); current.Bindings[action] = binding; active[id] = action; }
            catch (Exception ex) { warnings.Add(ShortcutConfig.Label(action) + "未启用：" + ex.Message); }
        }
        return warnings;
    }
    internal List<string> Apply(ShortcutConfig candidate)
    {
        candidate.Validate(); var next = candidate.Snapshot();
        var wanted = new Dictionary<int, string>(); var added = new List<ShortcutBinding>();
        try
        {
            foreach (string action in ShortcutConfig.Actions)
            {
                if (next.Bindings[action] is not { } binding) continue;
                bool existed = reservations.ContainsKey(binding);
                int id = Reserve(binding); if (!existed) added.Add(binding); wanted.Add(id, action);
            }
            // Existing registrations remain live throughout validation and persistence.
            // Swaps reuse their registrations; no unregister/re-register race is required.
            persist(next.Snapshot());
        }
        catch (Exception failure)
        {
            var errors = new List<Exception> { failure };
            foreach (var binding in added)
            {
                if (registry.Unregister(reservations[binding])) reservations.Remove(binding);
                else errors.Add(new IOException("候选快捷键释放失败（不会触发动作）：" + binding.Display));
            }
            if (errors.Count > 1) throw new AggregateException("快捷键未更改；候选清理存在错误。", errors);
            throw;
        }
        current = next; active = wanted;
        var warnings = new List<string>();
        foreach (var pair in reservations.ToArray())
        {
            if (wanted.ContainsKey(pair.Value)) continue;
            if (registry.Unregister(pair.Value)) reservations.Remove(pair.Key);
            else warnings.Add("旧组合释放失败，已停用动作并将在退出时释放：" + pair.Key.Display);
        }
        return warnings;
    }
    internal bool TryGetAction(int id, out string action) => active.TryGetValue(id, out action!);
    public void Dispose() { foreach (int id in reservations.Values) registry.Unregister(id); reservations.Clear(); active.Clear(); }
}
