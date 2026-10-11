using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
namespace Framelet;
internal static class OcrService
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetCurrentPackageFullName(ref uint length, System.Text.StringBuilder? name);
    public static async Task<string> Read(BitmapSource source, string language, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        uint length = 0; if (GetCurrentPackageFullName(ref length, null) == 15700) throw new InvalidOperationException("Windows OCR 需要 MSIX 包身份。请安装 build.ps1 -Package 生成的签名 MSIX；便携 EXE 不支持此系统接口。");
        if (source.PixelWidth > OcrEngine.MaxImageDimension || source.PixelHeight > OcrEngine.MaxImageDimension) throw new InvalidOperationException($"OCR 单边上限 {OcrEngine.MaxImageDimension}px；请先框选较小区域，避免静默缩小导致识别丢字。");
        var engine = OcrEngine.TryCreateFromLanguage(new Language(language)); if (engine == null) throw new InvalidOperationException($"系统缺少 {language} OCR 语言包。请在 Windows 设置 → 时间和语言 → 语言和区域中安装对应语言的基本键入/OCR 功能。");
        var bytes = Native.Rgba(source); for (int i = 0; i < bytes.Length; i += 4) (bytes[i], bytes[i + 2]) = (bytes[i + 2], bytes[i]);
        using var writer = new DataWriter(); writer.WriteBytes(bytes); using var bitmap = SoftwareBitmap.CreateCopyFromBuffer(writer.DetachBuffer(), BitmapPixelFormat.Bgra8, source.PixelWidth, source.PixelHeight, BitmapAlphaMode.Ignore);
        cancellation.ThrowIfCancellationRequested();
        var operation = engine.RecognizeAsync(bitmap);
        using var registration = cancellation.Register(() =>
        {
            try { operation.Cancel(); }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine("OCR cancellation: " + ex.Message); }
        });
        // Do not cancel this await: bitmap ownership lasts until the OS operation ends.
        var result = await operation.AsTask();
        cancellation.ThrowIfCancellationRequested();
        return string.Join(Environment.NewLine, result.Lines.Select(line => line.Text));
    }
}
