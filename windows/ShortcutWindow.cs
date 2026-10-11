using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
namespace Framelet;
internal sealed class ShortcutWindow : Window
{
    readonly ShortcutCoordinator coordinator;
    readonly TextBlock message = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 14, 0, 12) };
    readonly Dictionary<string, TextBox> fields = new();
    ShortcutConfig draft;
    internal ShortcutWindow(ShortcutCoordinator coordinator)
    {
        this.coordinator = coordinator; draft = coordinator.Current;
        Title = "快捷键设置 · 瞬帧"; Width = 560; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ((App)Application.Current).Appearance?.Attach(this);
        var body = new StackPanel { Margin = new Thickness(24) }; Content = body;
        body.Children.Add(new TextBlock { Text = "全局快捷键", FontSize = 22, FontWeight = FontWeights.SemiBold });
        body.Children.Add(new TextBlock { Text = "点击输入框后按组合键。需至少两个修饰键（含 Ctrl 或 Alt）；支持字母、数字、F1–F11。设置仅保存在当前用户的本机。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 16) });
        foreach (string action in ShortcutConfig.Actions)
        {
            var row = new Grid { Margin = new Thickness(0, 4, 0, 4) }; row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
            row.Children.Add(new TextBlock { Text = ShortcutConfig.Label(action), VerticalAlignment = VerticalAlignment.Center });
            var field = new TextBox { IsReadOnly = true, Padding = new Thickness(10), VerticalContentAlignment = VerticalAlignment.Center };
            System.Windows.Automation.AutomationProperties.SetName(field, ShortcutConfig.Label(action) + "快捷键，按组合键修改");
            fields[action] = field; Grid.SetColumn(field, 1); row.Children.Add(field);
            field.PreviewKeyDown += (_, e) =>
            {
                if (e.Key is Key.Tab or Key.Escape) return;
                e.Handled = true; var key = e.Key == Key.System ? e.SystemKey : e.Key;
                if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift) return;
                uint mods = ((Keyboard.Modifiers & ModifierKeys.Control) != 0 ? 2u : 0) | ((Keyboard.Modifiers & ModifierKeys.Alt) != 0 ? 1u : 0) | ((Keyboard.Modifiers & ModifierKeys.Shift) != 0 ? 4u : 0) | ((Keyboard.Modifiers & ModifierKeys.Windows) != 0 ? 8u : 0);
                try { var binding = new ShortcutBinding(mods, (uint)KeyInterop.VirtualKeyFromKey(key)); binding.Validate(); draft.Bindings[action] = binding; Refresh(); message.Text = "尚未应用；保存时会检查重复和系统占用。"; }
                catch (Exception ex) { message.Text = ex.Message; }
            };
            var disable = new Button { Content = "停用" }; disable.Click += (_, _) => { draft.Bindings[action] = null; Refresh(); message.Text = "尚未应用。"; }; Grid.SetColumn(disable, 2); row.Children.Add(disable); body.Children.Add(row);
        }
        body.Children.Add(new TextBlock { Text = "文字识别由 Windows 系统 OCR 在本机完成，无需第三方 AI 账号或 API Key。系统接口需要 MSIX 包身份和已安装的识别语言。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), FontSize = 12 });
        body.Children.Add(message);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var defaults = new Button { Content = "恢复默认" }; defaults.Click += (_, _) => { draft = ShortcutConfig.Defaults(); Refresh(); message.Text = "默认组合已填入，点击应用后生效；系统冲突时不会替换现有组合。"; };
        var cancel = new Button { Content = "取消", IsCancel = true }; var apply = new Button { Content = "应用", Style = (Style)FindResource("PrimaryButton") };
        apply.Click += (_, _) => { try { var warnings = coordinator.Apply(draft); Refresh(); message.Text = warnings.Count == 0 ? "已保存并生效。" : "已保存并生效；" + string.Join("；", warnings); } catch (Exception ex) { message.Text = "未应用，原快捷键保留：" + ex.Message; } };
        footer.Children.Add(defaults); footer.Children.Add(cancel); footer.Children.Add(apply); body.Children.Add(footer); Refresh();
    }
    // RegisterHotKey can consume combinations before a TextBox receives KeyDown.
    // The owner routes its existing registrations here while the modal settings is open.
    internal void RecordRegisteredBinding(ShortcutBinding binding)
    {
        foreach (var pair in fields)
            if (pair.Value.IsKeyboardFocusWithin) { draft.Bindings[pair.Key] = binding; Refresh(); message.Text = "尚未应用；保存时检查重复和系统占用。"; return; }
    }
    void Refresh() { foreach (string action in ShortcutConfig.Actions) fields[action].Text = draft.Bindings[action]?.Display ?? "未启用"; }
}
