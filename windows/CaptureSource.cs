using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
namespace Framelet;
internal interface ICaptureSource : IDisposable
{
    string Description { get; }
    Task<BitmapSource> CaptureAsync(CancellationToken cancellation);
}
internal static class CaptureSource
{
    public static async Task<ICaptureSource> OpenAsync(Region region, CancellationToken cancellation = default)
    {
        WgcCaptureSource? source = null;
        try
        {
            source = new WgcCaptureSource(region);
            await source.CaptureAsync(cancellation); // Validate a real first frame before exposing the backend.
            return source;
        }
        catch (Exception ex) when (CapturePolicy.CanUseGdiFallback(ex))
        {
            source?.Dispose();
            return new GdiCaptureSource(region, $"GDI 回退：{ex.Message}");
        }
        catch { source?.Dispose(); throw; }
    }
    sealed class GdiCaptureSource(Region region, string description) : ICaptureSource
    {
        public string Description => description;
        public Task<BitmapSource> CaptureAsync(CancellationToken cancellation)
        {
            cancellation.ThrowIfCancellationRequested();
            return Task.FromResult(Native.Capture(region));
        }
        public void Dispose() { }
    }
}
