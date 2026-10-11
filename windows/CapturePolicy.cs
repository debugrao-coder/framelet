using System.Runtime.InteropServices;
namespace Framelet;
internal static class CapturePolicy
{
    // Access/policy denial, cancellation, timeout, closed source and device loss are
    // not permissions to bypass WGC. Cross-monitor/unsupported cases are explicit.
    public static bool CanUseGdiFallback(Exception ex) =>
        ex is NotSupportedException or DllNotFoundException or EntryPointNotFoundException ||
        ex is COMException com && com.HResult is unchecked((int)0x887A0004);
}
