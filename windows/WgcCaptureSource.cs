using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
namespace Framelet;
/// <summary>One hardware device, capture session and two-surface pool per selected monitor.
/// CPU readback occurs only when the consumer asks for a new frame (GIF still uses CPU WIC encoding).</summary>
internal sealed class WgcCaptureSource : ICaptureSource
{
    readonly Region region, monitor;
    IDirect3DDevice? device;
    GraphicsCaptureItem? item;
    Direct3D11CaptureFramePool? pool;
    GraphicsCaptureSession? session;
    BitmapSource? latest;
    byte[]? monitorPixels;
    bool disposed;
    int sourceClosed;
    readonly LatestFrameSlot<Direct3D11CaptureFrame> frames = new();
    Exception? frameError;
    readonly SemaphoreSlim reader = new(1, 1);
    public string Description => "WGC / D3D11 · CPU 读回";
    public WgcCaptureSource(Region region)
    {
        this.region = region;
        if (!GraphicsCaptureSession.IsSupported()) throw new NotSupportedException("当前系统或图形驱动不支持 WGC。");
        var selected = WgcInterop.MonitorFor(region); monitor = selected.Bounds;
        if ((long)monitor.Width * monitor.Height > 64_000_000) throw new NotSupportedException("显示器超过 WGC 读回内存上限。");
        try
        {
            device = WgcInterop.CreateDevice(); item = WgcInterop.CreateItem(selected.Handle);
            if (item.Size.Width != monitor.Width || item.Size.Height != monitor.Height) throw new InvalidOperationException("WGC 显示器尺寸与物理像素不一致，请重新框选。");
            pool = Direct3D11CaptureFramePool.CreateFreeThreaded(device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size);
            pool.FrameArrived += FrameArrived;
            session = pool.CreateCaptureSession(item);
            session.IsCursorCaptureEnabled = false;
            item.Closed += ItemClosed;
            // Keep Windows' visible capture border. Do not request GraphicsCaptureAccess or borderless permissions.
            session.StartCapture();
        }
        catch { Dispose(); throw; }
    }
    void FrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        // Free-threaded callback only transfers ownership; GPU readback/encoding happens at consumer rate.
        // Keeping the pool drained avoids old frames when manual scroll capture waits between requests.
        try
        {
            var frame = sender.TryGetNextFrame();
            if (frame != null) frames.Publish(frame);
        }
        catch (Exception ex) { Interlocked.CompareExchange(ref frameError, ex, null); }
    }
    void ItemClosed(GraphicsCaptureItem sender, object args) => Interlocked.Exchange(ref sourceClosed, 1);
    public async Task<BitmapSource> CaptureAsync(CancellationToken cancellation)
    {
        await reader.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (Volatile.Read(ref sourceClosed) != 0) throw new InvalidOperationException("WGC 捕获源已关闭，请重新框选。");
            using var frame = await TakeLatestAsync(cancellation).ConfigureAwait(false);
            if (frame == null) return latest!; // Static content: reuse the already copied immutable image.
            if (frame.ContentSize.Width != monitor.Width || frame.ContentSize.Height != monitor.Height)
                throw new InvalidOperationException("录制期间显示器尺寸改变，已停止以避免错误裁剪。请重新框选。");
            using var software = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface, BitmapAlphaMode.Ignore).AsTask(cancellation).ConfigureAwait(false);
            cancellation.ThrowIfCancellationRequested();
            if (software.BitmapPixelFormat != BitmapPixelFormat.Bgra8 || software.PixelWidth != monitor.Width || software.PixelHeight != monitor.Height)
                throw new InvalidOperationException("WGC 返回了不支持的像素格式或尺寸。");
            // Buffer is reused for the session; no frame history is retained. Only the final crop enters GIF.
            monitorPixels ??= new byte[checked(monitor.Width * monitor.Height * 4)];
            software.CopyToBuffer(monitorPixels.AsBuffer());
            byte[] crop = CapturePixels.CropBgra(monitorPixels, monitor.Width, monitor.Height,
                region.X - monitor.X, region.Y - monitor.Y, region.Width, region.Height);
            var image = BitmapSource.Create(region.Width, region.Height, 96, 96, PixelFormats.Bgra32, null, crop, checked(region.Width * 4));
            image.Freeze(); latest = image; return image;
        }
        finally { reader.Release(); }
    }
    async Task<Direct3D11CaptureFrame?> TakeLatestAsync(CancellationToken cancellation)
    {
        var start = System.Diagnostics.Stopwatch.StartNew();
        while (true)
        {
            cancellation.ThrowIfCancellationRequested();
            if (Volatile.Read(ref sourceClosed) != 0) throw new InvalidOperationException("WGC 捕获源已关闭。");
            if (Volatile.Read(ref frameError) is Exception error) throw new InvalidOperationException("WGC 帧接收失败。", error);
            var newest = frames.Take();
            if (newest != null || latest != null) return newest;
            if (start.Elapsed > TimeSpan.FromSeconds(3)) throw new TimeoutException("WGC 首帧等待超过 3 秒；未自动切换 API 绕过捕获限制。");
            await Task.Delay(10, cancellation).ConfigureAwait(false);
        }
    }
    public void Dispose()
    {
        // Caller owns the operation lifetime and never disposes during CaptureAsync; UI busy gate enforces that.
        if (disposed) return; disposed = true;
        try { if (item != null) item.Closed -= ItemClosed; }
        finally
        {
            try { session?.Dispose(); }
            finally
            {
                try { if (pool != null) pool.FrameArrived -= FrameArrived; }
                finally
                {
                    try { frames.Dispose(); }
                    finally { try { pool?.Dispose(); } finally { try { device?.Dispose(); } finally { monitorPixels = null; latest = null; } } }
                }
            }
        }
    }
}
