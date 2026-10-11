using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Windows.UI.ViewManagement;

namespace Framelet;

// Windows-owned appearance, not an imitation of Apple's materials or fonts.
// These resources style chrome only. Canvas pixels/annotations never bind to them.
internal sealed class Theme : IDisposable
{
    readonly Application app;
    readonly UISettings? settings;
    volatile bool disposed;
    bool dark;
    internal Theme(Application app)
    {
        this.app = app;
        try { settings = new UISettings(); settings.ColorValuesChanged += ColorsChanged; }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("System theme unavailable: " + ex.Message); }
        SystemParameters.StaticPropertyChanged += ParametersChanged;
        Apply();
    }
    void ColorsChanged(UISettings sender, object args) => Schedule();
    void ParametersChanged(object? sender, PropertyChangedEventArgs args) => Schedule();
    void Schedule()
    {
        if (!disposed && !app.Dispatcher.HasShutdownStarted)
            app.Dispatcher.BeginInvoke(new Action(() => { if (!disposed) Apply(); }));
    }
    void Apply()
    {
        bool highContrast = SystemParameters.HighContrast;
        try
        {
            var foreground = settings?.GetColorValue(UIColorType.Foreground);
            dark = foreground is { } color && 5 * color.G + 2 * color.R + color.B > 8 * 128;
        }
        catch (Exception ex) { dark = false; System.Diagnostics.Debug.WriteLine(ex.Message); }
        if (highContrast || settings == null)
        {
            Set("WindowSurface", SystemColors.WindowBrush); Set("GroupSurface", SystemColors.WindowBrush);
            Set("ContentSurface", SystemColors.WindowBrush); Set("ViewportSurface", SystemColors.WindowBrush);
            Set("Label", SystemColors.WindowTextBrush); Set("SecondaryLabel", SystemColors.WindowTextBrush);
            Set("ControlSurface", SystemColors.ControlBrush); Set("ControlLabel", SystemColors.ControlTextBrush);
            Set("HoverSurface", SystemColors.HighlightBrush); Set("HoverLabel", SystemColors.HighlightTextBrush);
            Set("PrimarySurface", SystemColors.HighlightBrush); Set("OnPrimary", SystemColors.HighlightTextBrush);
            Set("Separator", SystemColors.WindowTextBrush); Set("DisabledLabel", SystemColors.GrayTextBrush);
            Set("Focus", SystemColors.HighlightBrush);
        }
        else
        {
            Set("WindowSurface", dark ? "#202020" : "#F5F5F5");
            Set("GroupSurface", dark ? "#2A2A2A" : "#FFFFFF");
            Set("ContentSurface", dark ? "#242424" : "#FFFFFF");
            Set("ViewportSurface", dark ? "#181818" : "#EAEAEA");
            Set("Label", dark ? "#F4F4F4" : "#202020");
            Set("SecondaryLabel", dark ? "#C5C5C5" : "#595959");
            Set("ControlSurface", dark ? "#323232" : "#F4F4F4");
            Set("ControlLabel", dark ? "#F4F4F4" : "#202020");
            Set("HoverSurface", dark ? "#454545" : "#E5E5E5");
            Set("HoverLabel", dark ? "#FFFFFF" : "#202020");
            Set("PrimarySurface", dark ? "#F4F4F4" : "#242424");
            Set("OnPrimary", dark ? "#202020" : "#FFFFFF");
            Set("Separator", dark ? "#777777" : "#888888");
            Set("DisabledLabel", dark ? "#A7A7A7" : "#666666");
            Set("Focus", dark ? "#FFFFFF" : "#202020");
        }
        foreach (Window window in app.Windows) ApplyTitleBar(window);
    }
    void Set(string name, string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color)); brush.Freeze(); Set(name, brush);
    }
    void Set(string name, Brush brush) => app.Resources[name] = brush;
    internal void Attach(Window window) => window.SourceInitialized += (_, _) => ApplyTitleBar(window);
    void ApplyTitleBar(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        int enabled = dark && !SystemParameters.HighContrast ? 1 : 0;
        // Optional OS chrome hint. Older Windows may reject it; never alter capture paths.
        int result = DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int));
        if (result < 0) System.Diagnostics.Debug.WriteLine("Dark title bar not supported: " + result);
    }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    internal static void Bind(FrameworkElement element, DependencyProperty property, string key) => element.SetResourceReference(property, key);
    internal static Border Group(UIElement child) => new() { Child = child, Style = (Style)Application.Current.FindResource("ControlGroup") };
    public void Dispose()
    {
        disposed = true;
        if (settings != null) settings.ColorValuesChanged -= ColorsChanged;
        SystemParameters.StaticPropertyChanged -= ParametersChanged;
    }
}
