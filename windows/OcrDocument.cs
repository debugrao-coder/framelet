namespace Framelet;

// UI-independent state, owned by the editor's Dispatcher. No clipboard/UI side effects.
internal sealed class OcrDocument
{
    internal readonly record struct Request(long Id, long Revision);
    internal enum Completion { Applied, Empty, Stale, Inactive }
    long revision, sequence;
    Request? active;
    string copiedText = "";
    internal string Text { get; private set; } = "";
    internal bool Closed { get; private set; }
    internal bool HasManualEdits { get; private set; }
    internal bool HasUncopiedText => Text.Length > 0 && Text != copiedText;
    internal bool Busy => active.HasValue;
    internal void Edit(string text)
    {
        if (Closed || text == Text) return;
        Text = text; revision++; HasManualEdits = true;
    }
    internal Request? Begin(bool approveReplacement = false)
    {
        if (Closed || Busy || (HasManualEdits && !approveReplacement)) return null;
        active = new Request(++sequence, revision); return active;
    }
    internal Completion Complete(Request request, string result)
    {
        if (Closed || active != request) return Completion.Inactive;
        active = null;
        if (request.Revision != revision) return Completion.Stale;
        if (string.IsNullOrWhiteSpace(result)) return Completion.Empty;
        Text = result; revision++; HasManualEdits = false;
        return Completion.Applied;
    }
    internal void Fail(Request request) { if (active == request) active = null; }
    internal bool ConfirmCopied(string fullText)
    {
        if (Closed || fullText != Text || fullText.Length == 0) return false;
        copiedText = fullText; return true;
    }
    internal void Close() { Closed = true; active = null; }
}

internal static class OcrDeadline
{
    // UI stops waiting promptly; native work keeps ownership of its bitmap until
    // it actually ends. Cancellation is best effort, never a promise of OS abort.
    internal static async Task<T> Await<T>(Task<T> worker, CancellationTokenSource cancellation, TimeSpan timeout)
    {
        try { return await worker.WaitAsync(timeout, cancellation.Token); }
        catch (TimeoutException) { cancellation.Cancel(); throw; }
        catch (OperationCanceledException) { cancellation.Cancel(); throw; }
    }
}
