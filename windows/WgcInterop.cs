using System.Runtime.InteropServices;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
namespace Framelet;
internal static class WgcInterop
{
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] internal struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] static extern IntPtr MonitorFromRect(ref Rect rect, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("d3d11.dll")]
    static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags,
        IntPtr featureLevels, uint featureLevelCount, uint sdkVersion, out IntPtr device, out uint featureLevel, out IntPtr context);
    [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);
    [DllImport("combase.dll", CharSet = CharSet.Unicode)] static extern int WindowsCreateString(string text, uint length, out IntPtr hstring);
    [DllImport("combase.dll")] static extern int WindowsDeleteString(IntPtr hstring);
    [DllImport("combase.dll")] static extern int RoGetActivationFactory(IntPtr className, ref Guid iid, out IntPtr factory);
    [ComImport, Guid("3628e81b-3cac-4c60-b7f4-23ce0e0c3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IGraphicsCaptureItemInterop
    {
        [PreserveSig] int CreateForWindow(IntPtr window, ref Guid iid, out IntPtr result);
        [PreserveSig] int CreateForMonitor(IntPtr monitor, ref Guid iid, out IntPtr result);
    }
    public static (IntPtr Handle, Region Bounds) MonitorFor(Region region)
    {
        if (region.Width < 1 || region.Height < 1 || (long)region.Width * region.Height > 64_000_000) throw new ArgumentException("选区无效或超过像素上限。");
        var rect = new Rect { Left = region.X, Top = region.Y, Right = checked(region.X + region.Width), Bottom = checked(region.Y + region.Height) };
        var handle = MonitorFromRect(ref rect, 0); var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (handle == IntPtr.Zero || !GetMonitorInfo(handle, ref info)) throw new NotSupportedException("选区不在可捕获显示器内。");
        if (rect.Left < info.Monitor.Left || rect.Top < info.Monitor.Top || rect.Right > info.Monitor.Right || rect.Bottom > info.Monitor.Bottom)
            throw new NotSupportedException("跨显示器选区暂不支持单个 WGC session。");
        return (handle, new Region(info.Monitor.Left, info.Monitor.Top, info.Monitor.Right - info.Monitor.Left, info.Monitor.Bottom - info.Monitor.Top));
    }
    public static IDirect3DDevice CreateDevice()
    {
        IntPtr device = IntPtr.Zero, context = IntPtr.Zero, dxgi = IntPtr.Zero, inspectable = IntPtr.Zero;
        try
        {
            // Hardware adapter, BGRA support, D3D11_SDK_VERSION=7. No WARP silently masquerading as hardware.
            Marshal.ThrowExceptionForHR(D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out device, out _, out context));
            var iid = new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c"); // IDXGIDevice
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, ref iid, out dxgi));
            Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out inspectable));
            return WinRT.MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
        }
        finally { Release(inspectable); Release(dxgi); Release(context); Release(device); }
    }
    public static GraphicsCaptureItem CreateItem(IntPtr monitor)
    {
        const string name = "Windows.Graphics.Capture.GraphicsCaptureItem";
        IntPtr text = IntPtr.Zero, factory = IntPtr.Zero, item = IntPtr.Zero; object? interopObject = null;
        try
        {
            Marshal.ThrowExceptionForHR(WindowsCreateString(name, (uint)name.Length, out text));
            var iid = typeof(IGraphicsCaptureItemInterop).GUID;
            Marshal.ThrowExceptionForHR(RoGetActivationFactory(text, ref iid, out factory));
            interopObject = Marshal.GetObjectForIUnknown(factory);
            var itemIid = new Guid("79c3f95b-31f7-4ec2-a464-632ef5d30760"); // IGraphicsCaptureItem
            Marshal.ThrowExceptionForHR(((IGraphicsCaptureItemInterop)interopObject).CreateForMonitor(monitor, ref itemIid, out item));
            return WinRT.MarshalInterface<GraphicsCaptureItem>.FromAbi(item);
        }
        finally
        {
            Release(item);
            if (interopObject != null && Marshal.IsComObject(interopObject)) Marshal.ReleaseComObject(interopObject);
            Release(factory); if (text != IntPtr.Zero) WindowsDeleteString(text);
        }
    }
    static void Release(IntPtr pointer) { if (pointer != IntPtr.Zero) Marshal.Release(pointer); }
}
