using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Framelet;
internal static class SelfTest
{
    public static void Run()
    {
        const int w = 64, h = 64; byte[] a = new byte[w * h * 4]; for (int i = 0; i < a.Length; i += 4) { a[i] = (byte)(i % 251); a[i + 1] = (byte)(i / 4 % 251); a[i + 2] = 210; a[i + 3] = 255; }
        var first = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, a, w * 4); first.Freeze();
        byte[] b = (byte[])a.Clone(); b[0] = 255; var second = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, b, w * 4); second.Freeze();
        var path = Path.Combine(AppContext.BaseDirectory, "self-test.gif"); using (var stream = new GifStream(File.Create(path))) { stream.Add(first, 10); stream.Add(second, 25); }
        var gif = new GifBitmapDecoder(new Uri(path), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (gif.Frames.Count != 2) throw new Exception("GIF frame count mismatch");
        if ((ushort)((BitmapMetadata)gif.Frames[1].Metadata).GetQuery("/grctlext/Delay") != 25) throw new Exception("GIF delay mismatch");
        var joined = Native.Join(first, second, 16); if (joined.PixelHeight != 80) throw new Exception("Join dimensions mismatch");
        if (Native.framelet_overlap(Native.Rgba(first), Native.Rgba(first), w, h, w * 4) != 0) throw new Exception("Core ABI unchanged frame mismatch");
        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test.json"), System.Text.Json.JsonSerializer.Serialize(new { status = "PASS_SCOPED", scope = "synthetic GIF frame metadata, join, core ABI only", frames = gif.Frames.Count, screenCapture = "NOT_TESTED", ocr = "NOT_TESTED", timestamp = DateTimeOffset.UtcNow }));
    }
}
