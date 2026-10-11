using System.IO;
namespace Framelet;
/// <summary>Never delete a fully encoded recording when the final rename fails.</summary>
internal sealed class RecordingFile
{
    public string Target { get; }
    public string Temporary { get; }
    public bool IsComplete { get; private set; }
    public RecordingFile(string target)
    {
        Target = target;
        Temporary = target + "." + Guid.NewGuid().ToString("N") + ".partial";
    }
    public void MarkComplete() => IsComplete = true;
    public void Commit()
    {
        if (!IsComplete) throw new InvalidOperationException("Recording has not completed encoding");
        File.Move(Temporary, Target, true);
    }
    public void CleanupIncomplete()
    {
        if (!IsComplete && File.Exists(Temporary)) File.Delete(Temporary);
    }
}
