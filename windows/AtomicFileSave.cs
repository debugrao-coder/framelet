using System.IO;
using System.Runtime.ExceptionServices;

namespace Framelet;

// All writes happen to an exclusively owned sibling file. Never truncate, delete,
// or copy over the destination. No non-atomic fallback if the filesystem refuses.
internal static class AtomicFileSave
{
    internal static void Save(string destination, Action<Stream> encode, IAtomicFileOperations? operations = null)
    {
        ArgumentNullException.ThrowIfNull(encode);
        operations ??= PhysicalAtomicFileOperations.Instance;
        string target = Path.GetFullPath(destination);
        string staging = Path.Combine(Path.GetDirectoryName(target)!, ".framelet-" + Guid.NewGuid().ToString("N") + ".tmp");
        bool replaceExisting = File.Exists(target);
        Stream? stream = null;
        bool owned = false, committed = false;
        var errors = new List<Exception>();
        try
        {
            stream = operations.CreateExclusive(staging);
            owned = true;
            encode(stream);
            operations.FlushToDisk(stream);
        }
        catch (Exception ex) { errors.Add(ex); }
        finally
        {
            if (stream != null)
                try { stream.Dispose(); } catch (Exception ex) { errors.Add(ex); }
        }
        if (errors.Count == 0)
        {
            try { operations.Commit(staging, target, replaceExisting); committed = true; }
            catch (Exception ex) { errors.Add(ex); }
        }
        if (owned && !committed)
        {
            try { operations.Delete(staging); }
            catch (Exception ex)
            {
                errors.Add(new IOException("临时文件清理失败，请手动检查：" + staging, ex));
            }
        }
        if (errors.Count == 1) ExceptionDispatchInfo.Capture(errors[0]).Throw();
        if (errors.Count > 1) throw new AggregateException("保存失败；编码、关闭或清理错误均已保留。", errors);
    }
}

// Injection boundary for deterministic failures without WPF or private images.
internal interface IAtomicFileOperations
{
    Stream CreateExclusive(string path);
    void FlushToDisk(Stream stream);
    void Commit(string staging, string target, bool replaceExisting);
    void Delete(string path);
}
internal sealed class PhysicalAtomicFileOperations : IAtomicFileOperations
{
    internal static readonly PhysicalAtomicFileOperations Instance = new();
    public Stream CreateExclusive(string path) => new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
    public void FlushToDisk(Stream stream) => ((FileStream)stream).Flush(flushToDisk: true);
    public void Commit(string staging, string target, bool replaceExisting)
    {
        if (replaceExisting) File.Replace(staging, target, null);
        else File.Move(staging, target); // A newly appeared target must not be overwritten.
    }
    public void Delete(string path) => File.Delete(path);
}
