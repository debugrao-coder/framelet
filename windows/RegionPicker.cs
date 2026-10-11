using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
namespace Framelet;
internal sealed class RegionPicker : Window
{
    readonly Canvas canvas = new(); readonly Rectangle outline = new() { Stroke = Brushes.YellowGreen, StrokeThickness = 2, Fill = new SolidColorBrush(Color.FromArgb(12, 255, 255, 255)) }; Native.POINT start; Point local;
    public Region? Selection { get; private set; }
    public RegionPicker()
    {
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; AllowsTransparency = true; Background = new SolidColorBrush(Color.FromArgb(65, 12, 18, 18)); Topmost = true; ShowInTaskbar = false; Cursor = Cursors.Cross; Content = canvas;
        canvas.Children.Add(new TextBlock { Text = "拖动框选区域 · Esc 取消", Foreground = Brushes.White, Background = Brushes.Black, Padding = new Thickness(14), Margin = new Thickness(24) }); canvas.Children.Add(outline);
        SourceInitialized += (_, _) => { var d = Native.Desktop; Native.SetWindowPos(new WindowInteropHelper(this).Handle, new IntPtr(-1), d.X, d.Y, d.Width, d.Height, 0x0040); };
        MouseLeftButtonDown += (_, e) => { Native.GetCursorPos(out start); local = e.GetPosition(canvas); CaptureMouse(); };
        MouseMove += (_, e) => { if (e.LeftButton != MouseButtonState.Pressed) return; var p = e.GetPosition(canvas); Canvas.SetLeft(outline, Math.Min(local.X, p.X)); Canvas.SetTop(outline, Math.Min(local.Y, p.Y)); outline.Width = Math.Abs(p.X - local.X); outline.Height = Math.Abs(p.Y - local.Y); };
        MouseLeftButtonUp += (_, _) => { ReleaseMouseCapture(); Native.GetCursorPos(out var end); int w = Math.Abs(end.X - start.X), h = Math.Abs(end.Y - start.Y); if (w >= 8 && h >= 8) { Selection = new(Math.Min(start.X, end.X), Math.Min(start.Y, end.Y), w, h); DialogResult = true; } else DialogResult = false; };
        KeyDown += (_, e) => { if (e.Key == Key.Escape) DialogResult = false; };
    }
}
