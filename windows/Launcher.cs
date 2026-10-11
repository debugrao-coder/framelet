using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
namespace Framelet;
internal sealed class Launcher : Window
{
    readonly TextBlock status = new() { Text = "本地优先 · 正在加载快捷键", Margin = new Thickness(12, 6, 12, 0), TextWrapping = TextWrapping.Wrap };
    readonly StackPanel actions = new() { Orientation = Orientation.Horizontal }; readonly Button stop = new() { Content = "■ 停止并保存", Visibility = Visibility.Collapsed }; readonly Button next = new() { Content = "＋ 添加下一段", Visibility = Visibility.Collapsed }; readonly Button finish = new() { Content = "完成长截图", Visibility = Visibility.Collapsed }; readonly Button undoScroll = new() { Content = "↶ 撤回一段", Visibility = Visibility.Collapsed, IsEnabled = false }; readonly Image scrollPreview = new() { MaxHeight = 130, MaxWidth = 630, Stretch = Stretch.Uniform, Margin = new Thickness(12, 8, 12, 0), Visibility = Visibility.Collapsed };
    ICaptureSource? scrollingSource;
    ShortcutCoordinator? shortcuts; ShortcutWindow? shortcutWindow; bool shortcutSettingsOpen;
    readonly TextBlock shortcutSummary = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 10, 12, 0), FontSize = 12 };
    Region region; BitmapSource? stitched, previous; readonly List<(BitmapSource Image, BitmapSource Previous)> undo = new(); CancellationTokenSource? recording; bool busy; IntPtr handle;
    public Launcher()
    {
        Title = "Framelet · 瞬帧"; Width = 690; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize; WindowStyle = WindowStyle.ToolWindow; Topmost = true;
        ((App)Application.Current).Appearance?.Attach(this);
        Theme.Bind(status, TextBlock.ForegroundProperty, "SecondaryLabel");
        stop.Style = (Style)FindResource("PrimaryButton");
        var body = new StackPanel { Margin = new Thickness(16) }; Content = body;
        var title = new DockPanel { Margin = new Thickness(8, 0, 8, 14) }; title.Children.Add(new TextBlock { Text = "瞬帧", FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 18, 0) }); var caption = new TextBlock { Text = "截图 · 长截图 · 录屏 · 文字", FontSize = 12, VerticalAlignment = VerticalAlignment.Center }; Theme.Bind(caption, TextBlock.ForegroundProperty, "SecondaryLabel"); title.Children.Add(caption); var settings = new Button { Content = "快捷键设置", HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(10, 0, 0, 0) }; settings.Click += (_, _) => ShowShortcuts(); title.Children.Add(settings); body.Children.Add(title); body.Children.Add(Theme.Group(actions));
        Add("⌖  截图", () => Capture("shot")); Add("↧  长截图", () => Capture("scroll")); Add("●  GIF 录屏", () => Capture("gif")); Add("文  提取文字", () => Capture("ocr")); Add("打开图片", Open);
        var controls = new StackPanel { Orientation = Orientation.Horizontal }; controls.Children.Add(next); controls.Children.Add(undoScroll); controls.Children.Add(finish); controls.Children.Add(stop); body.Children.Add(controls); body.Children.Add(scrollPreview); body.Children.Add(shortcutSummary); body.Children.Add(status);
        next.Click += async (_, _) => await AddScroll(); finish.Click += (_, _) => FinishScroll(); undoScroll.Click += (_, _) => { if (busy || undo.Count == 0) return; var last = undo[0]; stitched = last.Image; previous = last.Previous; undo.Clear(); undoScroll.IsEnabled = false; scrollPreview.Source = stitched; status.Text = "已撤回一段。请先将目标内容滚回上一帧，再继续。"; }; stop.Click += (_, _) => { stop.IsEnabled = false; recording?.Cancel(); };
        Closed += (_, _) => Application.Current.Shutdown();
        SourceInitialized += (_, _) => { handle = new WindowInteropHelper(this).Handle; HwndSource.FromHwnd(handle)?.AddHook(Hotkey); InitializeShortcuts(); if (!Native.SetWindowDisplayAffinity(handle, 0x11)) status.Text += "；无法排除工具条，请将它移出录制选区。"; };
        Closing += (_, e) => { if (recording != null) { e.Cancel = true; recording.Cancel(); status.Text = "正在停止并保存 GIF，请稍候再关闭。"; } else if (busy) { e.Cancel = true; status.Text = "正在完成本地操作，请稍候再关闭。"; } else if (stitched != null) { e.Cancel = true; FinishScroll(); } else { foreach (var editor in Application.Current.Windows.OfType<Editor>().ToArray()) { editor.Close(); if (editor.IsVisible) { e.Cancel = true; return; } } shortcuts?.Dispose(); } };
    }
    void Add(string title, Action action) { var button = new Button { Content = title }; button.Click += (_, _) => action(); actions.Children.Add(button); }
    sealed class WindowRegistration(IntPtr handle) : IShortcutRegistration
    {
        public bool Register(int id, ShortcutBinding binding) => Native.RegisterHotKey(handle, id, binding.Modifiers | 0x4000, binding.Key);
        public bool Unregister(int id) => Native.UnregisterHotKey(handle, id);
    }
    void InitializeShortcuts()
    {
        var store = new ShortcutFileStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Framelet", "shortcuts.json"));
        var requested = ShortcutConfig.Defaults(); string warning = "";
        try { requested = store.Load() ?? requested; } catch (Exception ex) { warning = "配置读取失败，暂用默认值（未覆盖原配置）：" + ex.Message + "；"; }
        shortcuts = new ShortcutCoordinator(new WindowRegistration(handle), store.Save);
        var conflicts = shortcuts.Initialize(requested);
        status.Text = warning + (conflicts.Count == 0 ? "本地快捷键已启用。" : string.Join("；", conflicts) + "；仍可点击操作按钮。");
        RefreshShortcuts();
    }
    void RefreshShortcuts()
    {
        if (shortcuts == null) return;
        var current = shortcuts.Current;
        shortcutSummary.Text = string.Join("  ·  ", ShortcutConfig.Actions.Select(a => ShortcutConfig.Label(a) + " " + (current.Bindings[a]?.Display ?? "未启用")));
    }
    void ShowShortcuts()
    {
        if (shortcuts == null || shortcutSettingsOpen || busy || recording != null || stitched != null) { status.Text = "请先完成当前操作，再设置快捷键。"; return; }
        shortcutSettingsOpen = true;
        try { shortcutWindow = new ShortcutWindow(shortcuts) { Owner = this }; shortcutWindow.ShowDialog(); }
        finally { shortcutWindow = null; shortcutSettingsOpen = false; RefreshShortcuts(); }
    }
    IntPtr Hotkey(IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled)
    {
        if (msg == 0x312 && shortcuts != null && shortcuts.TryGetAction(w.ToInt32(), out string action))
        {
            handled = true;
            if (shortcutSettingsOpen) { if (shortcuts.Current.Bindings[action] is { } binding) shortcutWindow?.RecordRegisteredBinding(binding); }
            else if (!busy && recording == null && stitched == null) Capture(action);
        }
        return IntPtr.Zero;
    }
    void Open()
    {
        var dialog = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp" };
        if (dialog.ShowDialog() != true) return;
        try
        {
            using (var stream = File.OpenRead(dialog.FileName))
            {
                if (stream.Length > 256_000_000) throw new InvalidOperationException("图片文件超过 256MB，请选择较小文件。");
                var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.OnDemand);
                var frame = decoder.Frames[0];
                if ((long)frame.PixelWidth * frame.PixelHeight > 64_000_000) throw new InvalidOperationException("图片超过 6400 万像素上限。");
            }
            var image = new BitmapImage(); image.BeginInit(); image.UriSource = new Uri(dialog.FileName); image.CacheOption = BitmapCacheOption.OnLoad; image.EndInit(); image.Freeze(); new Editor(image).Show();
        }
        catch (Exception ex) { status.Text = ex.Message; }
    }
    async void Capture(string mode)
    {
        if (busy || recording != null || stitched != null) return; busy = true; actions.IsEnabled = false;
        ICaptureSource? source = null;
        try
        {
            Hide(); await Task.Delay(120); var picker = new RegionPicker(); if (picker.ShowDialog() != true || picker.Selection is not Region selected) return; region = selected; await Task.Delay(100);
            if (mode == "gif") { await Record(); return; }
            source = await Task.Run(() => CaptureSource.OpenAsync(region));
            var image = await Task.Run(() => source.CaptureAsync(CancellationToken.None));
            if (mode == "scroll") { scrollingSource = source; source = null; stitched = image; previous = image; next.Visibility = finish.Visibility = undoScroll.Visibility = scrollPreview.Visibility = Visibility.Visible; scrollPreview.Source = image; status.Text = "手动向下滚动约半屏，再点「添加下一段」。只框选纯滚动内容，固定页眉/页脚或变化边缘会被拒绝。 " + scrollingSource.Description; }
            else { var editor = new Editor(image, source.Description); editor.Show(); if (mode == "ocr") await editor.Extract(); }
        }
        catch (Exception ex) { status.Text = $"未完成：{ex.Message}"; }
        finally { try { source?.Dispose(); } catch (Exception ex) { status.Text += "；释放捕获资源失败：" + ex.Message; } finally { Show(); busy = false; actions.IsEnabled = stitched == null && recording == null; } }
    }
    async Task AddScroll()
    {
        if (busy || stitched == null || previous == null) return; busy = true; next.IsEnabled = false;
        try
        {
            Hide(); await Task.Delay(180); var frame = await Task.Run(() => scrollingSource!.CaptureAsync(CancellationToken.None)); var before = previous;
            int count = await Task.Run(() =>
            {
                var a = Native.Rgba(before); var b = Native.Rgba(frame);
                int delta = Native.framelet_overlap(a, b, region.Width, region.Height, checked(region.Width * 4));
                if (delta > 0) ScrollGuard.RequireExactOverlap(a, b, region.Width, region.Height, checked(region.Width * 4), delta);
                return delta;
            });
            if (count == 0) { status.Text = "画面未变化，未添加。请继续向下滚动。"; return; }
            if (count < 0) { status.Text = "接缝不可靠，未添加。请回退并减少滚动距离，避开动画/固定栏。已成功片段仍可完成保存。"; return; }
            // Only the latest undo snapshot is retained; total image pixels are bounded by Native.Join.
            var priorStitched = stitched; var priorFrame = previous;
            var joined = await Task.Run(() => Native.Join(priorStitched, frame, count));
            // Commit only after validation AND allocation succeed; failures preserve the existing undo state.
            undo.Clear(); undo.Add((priorStitched, priorFrame)); stitched = joined; previous = frame; undoScroll.IsEnabled = true; scrollPreview.Source = stitched; status.Text = $"已拼接 {stitched.PixelWidth} × {stitched.PixelHeight}px；继续向下滚动，或完成。";
        }
        catch (DllNotFoundException) { status.Text = "缺少 framelet_core.dll。请使用 build.ps1 完整构建。已有首帧可完成保存。"; }
        catch (Exception ex) { status.Text = $"未添加：{ex.Message}"; }
        finally { Show(); busy = false; next.IsEnabled = true; }
    }
    void FinishScroll()
    {
        if (busy || stitched == null) return;
        new Editor(stitched, scrollingSource?.Description).Show();
        string cleanup = "";
        try { scrollingSource?.Dispose(); } catch (Exception ex) { cleanup = "；释放捕获资源失败：" + ex.Message; }
        scrollingSource = null; stitched = previous = null; undo.Clear();
        next.Visibility = finish.Visibility = undoScroll.Visibility = scrollPreview.Visibility = Visibility.Collapsed;
        scrollPreview.Source = null; actions.IsEnabled = true; status.Text = "长截图已进入编辑器；尚未保存。" + cleanup;
    }
    async Task Record()
    {
        if ((long)region.Width * region.Height > GifRecorder.MaxPixels) throw new InvalidOperationException("GIF 选区超过 207 万像素，请重新框选较小区域。");
        Show(); var dialog = new SaveFileDialog { Filter = "GIF 动图|*.gif", FileName = $"Framelet-{DateTime.Now:yyyyMMdd-HHmmss}.gif" }; if (dialog.ShowDialog() != true) return;
        var output = new RecordingFile(dialog.FileName);
        using var cancellation = new CancellationTokenSource();
        recording = cancellation; stop.IsEnabled = true; stop.Visibility = Visibility.Visible;
        status.Text = "3 秒后开始，请将工具条移出选区。无音频 · 目标 10 fps · 最长 60 秒";
        // Capture() holds the operation guard until this entire try/finally completes.
        try
        {
            await Task.Delay(3000, cancellation.Token);
            var progress = new Progress<string>(s => { if (ReferenceEquals(recording, cancellation)) status.Text = s; });
            var result = await new GifRecorder().Record(region, output.Temporary, cancellation.Token, progress);
            output.MarkComplete();
            try { output.Commit(); status.Text = $"已保存 {result.Frames} 帧：{output.Target}" + (result.CleanupWarning == null ? "" : "；" + result.CleanupWarning); }
            catch (Exception ex) { status.Text = $"录制已完成，但保存失败：{ex.Message}。完整 GIF 保留在 {output.Temporary}，可手动改名为 .gif 恢复。"; }
        }
        catch (OperationCanceledException) { status.Text = "录制已取消。"; }
        catch (Exception ex) { status.Text = $"录制未完成：{ex.Message}"; }
        finally
        {
            recording = null; stop.Visibility = Visibility.Collapsed;
            try { output.CleanupIncomplete(); }
            catch (Exception ex) { status.Text += $"；临时文件清理失败：{ex.Message}。请检查 {output.Temporary}"; }
        }
    }
}
