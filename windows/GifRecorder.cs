using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Framelet;
/// <summary>Bounded-memory GIF89a writer. WIC quantizes one frame at a time; each local palette stays with its frame.</summary>
internal sealed class GifStream : IDisposable
{
    readonly GifMuxer mux;
    public GifStream(Stream output) { mux = new GifMuxer(output); }
    public void Add(BitmapSource bitmap, int delayCentiseconds)
    {
        var encoder = new GifBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var memory = new MemoryStream(); encoder.Save(memory); mux.Add(memory.ToArray(), delayCentiseconds);
    }
    public void Dispose() => mux.Dispose();
}
internal readonly record struct RecordingResult(int Frames, string? CleanupWarning);
internal sealed class GifRecorder
{
    public const int Fps = 10, MaxSeconds = 60;
    public const long MaxPixels = 2_073_600;
    public async Task<RecordingResult> Record(Region region, string target, CancellationToken cancellation, IProgress<string> progress)
    {
        if (region.Width < 1 || region.Height < 1 || (long)region.Width * region.Height > MaxPixels)
            throw new InvalidOperationException("GIF 选区最多 207 万像素。请缩小区域；当前版本不声称支持高帧率视频录制。");
        return await Task.Run(async () =>
        {
            var capture = await CaptureSource.OpenAsync(region, cancellation);
            string? cleanupWarning = null; int frames = 0;
            try
            {
                progress.Report(capture.Description);
                using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                using var writer = new GifStream(output);
                var watch = System.Diagnostics.Stopwatch.StartNew();
                BitmapSource? previous = null; long previousAt = 0;
                while (!cancellation.IsCancellationRequested && watch.Elapsed.TotalSeconds < MaxSeconds)
                {
                    long tick = watch.ElapsedMilliseconds; BitmapSource current;
                    try { current = await capture.CaptureAsync(cancellation); }
                    catch (OperationCanceledException) when (previous != null && cancellation.IsCancellationRequested) { break; }
                    // Stopping during readback still finalizes all previously captured frames.
                    if (previous != null) writer.Add(previous, (int)Math.Clamp((tick - previousAt + 5) / 10, 1, 65535));
                    previous = current; previousAt = tick; frames++;
                    progress.Report($"● 录制 {watch.Elapsed:mm\\:ss} · {frames} 帧 · {capture.Description} · 点击停止（最多 60 秒）");
                    int delay = (int)Math.Max(0, 1000 / Fps - (watch.ElapsedMilliseconds - tick));
                    if (delay > 0) await Task.Delay(delay); // Codec work is not interruptible; polling delay is bounded.
                }
                if (previous == null) throw new OperationCanceledException();
                writer.Add(previous, (int)Math.Clamp((watch.ElapsedMilliseconds - previousAt + 5) / 10, 1, 65535));
            }
            finally
            {
                try { capture.Dispose(); }
                catch (Exception ex) { cleanupWarning = "释放捕获资源失败：" + ex.Message; }
            }
            // A capture-resource cleanup error must not delete a successfully encoded GIF.
            return new RecordingResult(frames, cleanupWarning);
        });
    }
}
