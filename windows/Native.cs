using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Framelet;
public readonly record struct Region(int X, int Y, int Width, int Height);
internal static class Native
{
    [DllImport("user32.dll")] internal static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int w, int h);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
    [DllImport("user32.dll")] internal static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [StructLayout(LayoutKind.Sequential)] internal struct POINT { public int X, Y; }
    [DllImport("framelet_core", CallingConvention = CallingConvention.Cdecl)] internal static extern int framelet_overlap(byte[] previous, byte[] next, int width, int height, int stride);
    public static Region Desktop => new(GetSystemMetrics(76), GetSystemMetrics(77), GetSystemMetrics(78), GetSystemMetrics(79));
    public static BitmapSource Capture(Region region)
    {
        if (region.Width < 1 || region.Height < 1 || (long)region.Width * region.Height > 64_000_000) throw new InvalidOperationException("选区过大或无效，请重新框选。");
        var dc = GetDC(IntPtr.Zero); var target = CreateCompatibleDC(dc); var bmp = CreateCompatibleBitmap(dc, region.Width, region.Height);
        if (dc == IntPtr.Zero || target == IntPtr.Zero || bmp == IntPtr.Zero) { if (bmp != IntPtr.Zero) DeleteObject(bmp); if (target != IntPtr.Zero) DeleteDC(target); if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc); throw new InvalidOperationException("无法分配截图缓冲区。"); }
        var old = SelectObject(target, bmp);
        try { if (old == IntPtr.Zero || old == new IntPtr(-1)) throw new InvalidOperationException("截图位图无法绑定到设备上下文。"); if (!BitBlt(target, 0, 0, region.Width, region.Height, dc, region.X, region.Y, 0x40CC0020)) throw new InvalidOperationException("屏幕捕获失败；受保护内容不可捕获。"); var image = Imaging.CreateBitmapSourceFromHBitmap(bmp, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); image.Freeze(); return image; }
        finally { if (old != IntPtr.Zero && old != new IntPtr(-1)) SelectObject(target, old); DeleteObject(bmp); DeleteDC(target); ReleaseDC(IntPtr.Zero, dc); }
    }
    public static byte[] Rgba(BitmapSource bitmap)
    {
        var source = new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0); var bytes = new byte[checked(bitmap.PixelWidth * bitmap.PixelHeight * 4)]; source.CopyPixels(bytes, bitmap.PixelWidth * 4, 0);
        for (int i = 0; i < bytes.Length; i += 4) { (bytes[i], bytes[i + 2]) = (bytes[i + 2], bytes[i]); bytes[i + 3] = 255; }
        return bytes;
    }
    public static BitmapSource Join(BitmapSource image, BitmapSource next, int append)
    {
        if (image.PixelWidth != next.PixelWidth || append < 1 || append >= next.PixelHeight || image.PixelHeight < next.PixelHeight)
            throw new ArgumentException("Invalid append geometry");
        int w = image.PixelWidth, h = checked(image.PixelHeight + append);
        if ((long)w * h > 64_000_000) throw new InvalidOperationException("长截图达到 6400 万像素上限。请先保存，再开始下一段。");
        var bytes = new byte[checked(w * h * 4)]; var a = new FormatConvertedBitmap(image, PixelFormats.Bgra32, null, 0); var b = new FormatConvertedBitmap(next, PixelFormats.Bgra32, null, 0);
        a.CopyPixels(bytes, w * 4, 0); b.CopyPixels(new Int32Rect(0, next.PixelHeight - append, w, append), bytes, w * 4, image.PixelHeight * w * 4);
        var result = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, bytes, w * 4); result.Freeze(); return result;
    }
}
