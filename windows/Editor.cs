using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Microsoft.Win32;
namespace Framelet;
internal sealed class Editor : Window
{
    readonly BitmapSource source; readonly Canvas canvas = new(); readonly TextBlock status = new() { Margin = new Thickness(16, 8, 16, 12) };
    readonly TextBox ocr = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, BorderThickness = new Thickness(0), Padding = new Thickness(14), MinHeight = 230 };
    readonly Border ocrPane = new() { Width = 310, Visibility = Visibility.Collapsed, Padding = new Thickness(16) };
    readonly TextBox annotation = new() { Text = "标注文字", Width = 160, Padding = new Thickness(8), Margin = new Thickness(8) }; readonly ComboBox languages = new() { Width = 145, Margin = new Thickness(3), Padding = new Thickness(6) };
    Point start; string tool = "arrow"; UIElement? preview; bool dirty, recognizing, saving; readonly Stack<UIElement> marks = new(); readonly Button recognize;
    readonly OcrDocument ocrDocument = new();
    CancellationTokenSource? ocrCancellation;
    Task<string>? ocrWorker;
    bool applyingOcrText, closed;
    public Editor(BitmapSource bitmap, string? captureDetails = null)
    {
        source = bitmap; Title = "瞬帧 · 编辑"; Width = 1120; Height = 760; MinWidth = 780; MinHeight = 520; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ((App)Application.Current).Appearance?.Attach(this);
        Theme.Bind(status, TextBlock.ForegroundProperty, "SecondaryLabel");
        Theme.Bind(ocrPane, Border.BackgroundProperty, "GroupSurface");
        Theme.Bind(ocrPane, Border.BorderBrushProperty, "Separator");
        ocrPane.BorderThickness = new Thickness(1, 0, 0, 0);
        System.Windows.Automation.AutomationProperties.SetName(ocr, "识别文字结果，可编辑");
        System.Windows.Automation.AutomationProperties.SetName(languages, "识别语言");
        System.Windows.Automation.AutomationProperties.SetName(annotation, "标注文字");
        var root = new DockPanel(); Content = root; var bar = new DockPanel { Margin = new Thickness(18, 14, 18, 10) }; DockPanel.SetDock(bar, Dock.Top); root.Children.Add(bar);
        bar.Children.Add(new TextBlock { Text = "编辑截图", FontSize = 20, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 24, 0) });
        var commands = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; bar.Children.Add(Theme.Group(commands));
        recognize = Button("提取文字", async () => await Extract()); commands.Children.Add(recognize); commands.Children.Add(Button("复制图片", Copy)); var save = Button("保存 PNG", Save); save.Style = (Style)FindResource("PrimaryButton"); commands.Children.Add(save);
        DockPanel.SetDock(status, Dock.Bottom); root.Children.Add(status); status.Text = $"{source.PixelWidth} × {source.PixelHeight}px  ·  本地处理，未保存  ·  Ctrl+S 保存 / Ctrl+Z 撤销" + (captureDetails == null ? "" : " · " + captureDetails);
        DockPanel.SetDock(ocrPane, Dock.Right); root.Children.Add(ocrPane); var panel = new DockPanel(); ocrPane.Child = panel;
        var heading = new StackPanel(); heading.Children.Add(new TextBlock { Text = "识别文字", FontSize = 22, Margin = new Thickness(0, 0, 0, 12) }); languages.Items.Add("zh-Hans-CN"); languages.Items.Add("en-US"); languages.SelectedIndex = 0; heading.Children.Add(languages); DockPanel.SetDock(heading, Dock.Top); panel.Children.Add(heading);
        var bottom = new StackPanel(); bottom.Children.Add(Button("复制文字", CopyOcr)); bottom.Children.Add(Button("关闭文字面板", () => ocrPane.Visibility = Visibility.Collapsed)); DockPanel.SetDock(bottom, Dock.Bottom); panel.Children.Add(bottom); panel.Children.Add(ocr);
        ocr.TextChanged += (_, _) => { if (!applyingOcrText && !closed) ocrDocument.Edit(ocr.Text); };
        var left = new StackPanel { Width = 178, Margin = new Thickness(2, 10, 2, 14) }; var tools = Theme.Group(left); tools.Margin = new Thickness(12, 6, 12, 12); DockPanel.SetDock(tools, Dock.Left); root.Children.Add(tools);
        left.Children.Add(new TextBlock { Text = "标注", Margin = new Thickness(12, 0, 0, 14) });
        left.Children.Add(Button("↗  箭头", () => Select("arrow"))); left.Children.Add(Button("▭  矩形", () => Select("rect"))); left.Children.Add(Button("■  实色遮盖", () => Select("redact"))); left.Children.Add(Button("T  文字", () => Select("text"))); left.Children.Add(annotation); left.Children.Add(Button("↶  撤销", Undo)); left.Children.Add(new TextBlock { Text = "遮盖使用不透明色块，导出时扁平化。原图不会被自动覆盖。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 22, 12, 0), FontSize = 12 });
        canvas.Width = source.PixelWidth; canvas.Height = source.PixelHeight; canvas.Background = Brushes.White; canvas.ClipToBounds = true; canvas.Children.Add(new Image { Source = source, Width = source.PixelWidth, Height = source.PixelHeight, IsHitTestVisible = false });
        var viewport = new Border { CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 6, 18, 12), Padding = new Thickness(24) }; Theme.Bind(viewport, Border.BackgroundProperty, "ViewportSurface"); viewport.Child = new Viewbox { Stretch = Stretch.Uniform, Child = canvas }; root.Children.Add(viewport);
        canvas.MouseLeftButtonDown += (_, e) => { start = e.GetPosition(canvas); if (tool == "text") { var text = new TextBlock { Text = annotation.Text, FontSize = Math.Max(18, source.PixelWidth / 45d), Foreground = Brushes.OrangeRed, FontWeight = FontWeights.Bold, IsHitTestVisible = false }; Canvas.SetLeft(text, start.X); Canvas.SetTop(text, start.Y); canvas.Children.Add(text); marks.Push(text); dirty = true; } else canvas.CaptureMouse(); };
        canvas.MouseMove += (_, e) => { if (!canvas.IsMouseCaptured) return; if (preview != null) canvas.Children.Remove(preview); preview = Shape(start, e.GetPosition(canvas)); canvas.Children.Add(preview); };
        canvas.MouseLeftButtonUp += (_, _) => { canvas.ReleaseMouseCapture(); if (preview != null) { marks.Push(preview); preview = null; dirty = true; } };
        PreviewKeyDown += (_, e) => { if (Keyboard.Modifiers == ModifierKeys.Control) { if (e.Key == Key.S) { Save(); e.Handled = true; } if (e.Key == Key.Z && !ocr.IsKeyboardFocusWithin && !annotation.IsKeyboardFocusWithin) { Undo(); e.Handled = true; } if (e.Key == Key.C && ocr.IsKeyboardFocusWithin && ocr.SelectionLength == ocr.Text.Length && ocr.Text.Length > 0) { CopyOcr(); e.Handled = true; } else if (e.Key == Key.C && !ocr.IsKeyboardFocusWithin && !annotation.IsKeyboardFocusWithin) { Copy(); e.Handled = true; } } };
        Closing += (_, e) =>
        {
            if (saving) { e.Cancel = true; status.Text = "正在保存，请完成后再关闭。"; return; }
            if (dirty || ocrDocument.HasUncopiedText || recognizing || ocrWorker is { IsCompleted: false })
            {
                string reason = (dirty ? "尚有未保存的标注。\n" : "") + (ocrDocument.HasUncopiedText ? "尚有未复制的识别文字（保存 PNG 不会保存文字）。\n" : "") + (recognizing || ocrWorker is { IsCompleted: false } ? "文字识别仍在处理，关闭将取消等待。\n" : "");
                if (MessageBox.Show(this, reason + "是否丢弃并关闭？", "保留当前内容", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) { e.Cancel = true; return; }
            }
            closed = true; ocrDocument.Close(); ocrCancellation?.Cancel();
        };
    }
    static Button Button(string text, Action action) { var b = new Button { Content = text }; b.Click += (_, _) => action(); return b; }
    void Select(string value) { tool = value; status.Text = "当前工具：" + value + " · 在图片上拖动标注，文字工具点击放置。"; }
    UIElement Shape(Point a, Point b)
    {
        double stroke = Math.Max(3, source.PixelWidth / 400d);
        if (tool == "arrow") { var group = new Canvas { IsHitTestVisible = false }; group.Children.Add(new Line { X1 = a.X, Y1 = a.Y, X2 = b.X, Y2 = b.Y, Stroke = Brushes.OrangeRed, StrokeThickness = stroke }); double angle = Math.Atan2(b.Y - a.Y, b.X - a.X), head = stroke * 5; group.Children.Add(new Polygon { Fill = Brushes.OrangeRed, Points = new PointCollection { b, new(b.X - head * Math.Cos(angle - .45), b.Y - head * Math.Sin(angle - .45)), new(b.X - head * Math.Cos(angle + .45), b.Y - head * Math.Sin(angle + .45)) } }); return group; }
        var shape = new Rectangle { Width = Math.Abs(a.X - b.X), Height = Math.Abs(a.Y - b.Y), Stroke = tool == "redact" ? Brushes.Black : Brushes.OrangeRed, StrokeThickness = tool == "redact" ? 0 : stroke, Fill = tool == "redact" ? Brushes.Black : Brushes.Transparent, IsHitTestVisible = false }; Canvas.SetLeft(shape, Math.Min(a.X, b.X)); Canvas.SetTop(shape, Math.Min(a.Y, b.Y)); return shape;
    }
    void Undo() { if (saving) return; if (marks.Count > 0) { canvas.Children.Remove(marks.Pop()); dirty = true; status.Text = "已撤销上一处标注。"; } }
    BitmapSource Flatten() { canvas.Measure(new Size(source.PixelWidth, source.PixelHeight)); canvas.Arrange(new Rect(0, 0, source.PixelWidth, source.PixelHeight)); canvas.UpdateLayout(); var result = new RenderTargetBitmap(source.PixelWidth, source.PixelHeight, 96, 96, PixelFormats.Pbgra32); result.Render(canvas); result.Freeze(); return result; }
    async void Save()
    {
        // Guard before the modal dialog: its nested message loop can re-enter commands.
        if (saving || recognizing || canvas.IsMouseCaptured) return;
        saving = true;
        var content = (UIElement)Content;
        try
        {
            var dialog = new SaveFileDialog { Filter = "PNG 图片|*.png", FileName = $"Framelet-{DateTime.Now:yyyyMMdd-HHmmss}.png" };
            if (dialog.ShowDialog(this) != true) return;
            content.IsEnabled = false;
            // Render on the owning Dispatcher; only this immutable Freezable crosses threads.
            BitmapSource snapshot = Flatten();
            if (!snapshot.IsFrozen) throw new InvalidOperationException("无法创建不可变的保存快照。");
            string target = dialog.FileName;
            status.Text = "正在编码并安全保存…";
            await Task.Run(() => AtomicFileSave.Save(target, stream =>
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(snapshot));
                encoder.Save(stream);
            }));
            dirty = false;
            status.Text = "已保存：" + target;
        }
        catch (Exception ex)
        {
            // A secondary cleanup error must not hide the encoding/commit failure.
            string detail = ex is AggregateException aggregate
                ? string.Join("；", aggregate.Flatten().InnerExceptions.Select(error => error.Message))
                : ex.Message;
            status.Text = "保存失败：" + detail;
        }
        finally { saving = false; content.IsEnabled = true; }
    }
    void Copy() { if (saving) return; try { Clipboard.SetImage(Flatten()); status.Text = "已复制扁平化图片。"; } catch (Exception ex) { status.Text = "复制失败：" + ex.Message; } }
    void CopyOcr()
    {
        if (closed || saving || ocr.Text.Length == 0) return;
        string fullText = ocr.Text;
        try
        {
            Clipboard.SetText(fullText);
            ocrDocument.ConfirmCopied(fullText);
            status.Text = "已复制全部识别文字。";
        }
        catch (Exception ex) { status.Text = "复制失败：" + ex.Message; }
    }
    async Task ObserveOcrWorker(Task<string> worker, CancellationTokenSource cancellation)
    {
        try { await worker; }
        catch { /* Extract reports failure; always observe late faults. */ }
        finally
        {
            if (ReferenceEquals(ocrCancellation, cancellation)) ocrCancellation = null;
            cancellation.Dispose();
            if (!closed && ReferenceEquals(ocrWorker, worker)) recognize.IsEnabled = !recognizing;
        }
    }
    public async Task Extract()
    {
        if (recognizing || saving || closed || ocrWorker is { IsCompleted: false }) return;
        recognizing = true; recognize.IsEnabled = false;
        OcrDocument.Request? request = null;
        CancellationTokenSource? requestCancellation = null;
        Task<string>? requestWorker = null;
        try
        {
            bool approved = !ocrDocument.HasManualEdits || MessageBox.Show(this, "重新识别会替换你修改过的文字。是否继续？", "保留修改的文字", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes;
            if (!approved || closed) return;
            request = ocrDocument.Begin(approved);
            if (request == null) return;
            ocrPane.Visibility = Visibility.Visible;
            status.Text = "正在本地识别…已有文字保持不变；最长等待 30 秒。";
            var snapshot = Flatten();
            string language = languages.SelectedItem?.ToString() ?? "zh-Hans-CN";
            var cancellation = new CancellationTokenSource(); requestCancellation = ocrCancellation = cancellation;
            var worker = Task.Run(() => OcrService.Read(snapshot, language, cancellation.Token)); requestWorker = ocrWorker = worker;
            string text = await OcrDeadline.Await(worker, cancellation, TimeSpan.FromSeconds(30));
            if (closed) return;
            var result = ocrDocument.Complete(request.Value, text);
            if (result == OcrDocument.Completion.Applied)
            {
                applyingOcrText = true;
                try { ocr.Text = ocrDocument.Text; } finally { applyingOcrText = false; }
                status.Text = "识别完成；请核对后复制全部文字。";
            }
            else status.Text = result == OcrDocument.Completion.Stale ? "识别期间文字已修改，新结果未覆盖当前文字。" : "未识别到文字，已保留当前文字。";
        }
        catch (TimeoutException) { if (!closed) status.Text = "识别超时，已保留当前文字并请求取消；系统任务结束前不能再次识别。"; }
        catch (OperationCanceledException) { if (!closed) status.Text = "识别已取消，当前文字保留。"; }
        catch (Exception ex) { if (!closed) status.Text = "识别失败，当前文字保留：" + ex.Message; }
        finally
        {
            if (request is { } token) ocrDocument.Fail(token);
            recognizing = false;
            if (!closed) recognize.IsEnabled = ocrWorker is not { IsCompleted: false };
            if (requestWorker != null && requestCancellation != null) _ = ObserveOcrWorker(requestWorker, requestCancellation);
            else requestCancellation?.Dispose();
        }
    }
}
