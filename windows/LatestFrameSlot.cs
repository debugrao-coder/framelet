namespace Framelet;
/// <summary>A single owned native frame. Producer never waits for the CPU encoder and replaced frames are released.</summary>
internal sealed class LatestFrameSlot<T> : IDisposable where T : class, IDisposable
{
    readonly object gate = new();
    T? value;
    bool closed;
    public void Publish(T next)
    {
        T? replaced;
        lock (gate)
        {
            if (closed) replaced = next;
            else { replaced = value; value = next; }
        }
        replaced?.Dispose();
    }
    public T? Take()
    {
        lock (gate) { var result = value; value = null; return result; }
    }
    public void Dispose()
    {
        T? last;
        lock (gate) { if (closed) return; closed = true; last = value; value = null; }
        last?.Dispose();
    }
}
