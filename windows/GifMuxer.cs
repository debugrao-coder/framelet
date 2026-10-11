using System.IO;
namespace Framelet;
/// <summary>Streams opaque full-frame GIFs, preserving each frame's palette. No accumulated frame list.</summary>
internal sealed class GifMuxer : IDisposable
{
    readonly Stream output;
    bool header, disposed;
    ushort width, height;
    public GifMuxer(Stream output) { this.output = output; }
    public void Add(byte[] data, int delay)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (delay is < 1 or > 65535) throw new ArgumentOutOfRangeException(nameof(delay));
        Require(data, 0, 13);
        if (!data.AsSpan(0, 6).SequenceEqual("GIF89a"u8) && !data.AsSpan(0, 6).SequenceEqual("GIF87a"u8)) throw new InvalidDataException("Not a GIF frame");
        ushort w = Read16(data, 6), h = Read16(data, 8);
        if (w == 0 || h == 0 || (header && (w != width || h != height))) throw new InvalidDataException("GIF dimensions must be nonzero and consistent");
        int packed = data[10], globalLength = (packed & 128) != 0 ? 3 * (1 << ((packed & 7) + 1)) : 0;
        Require(data, 13, globalLength); int p = 13 + globalLength;
        while (p < data.Length && data[p] == 0x21) { Require(data, p, 2); p = SkipBlocks(data, p + 2); }
        Require(data, p, 10);
        if (data[p] != 0x2C || Read16(data, p + 1) != 0 || Read16(data, p + 3) != 0 || Read16(data, p + 5) != w || Read16(data, p + 7) != h) throw new InvalidDataException("Only full GIF image frames are supported");
        int localPacked = data[p + 9], localLength = (localPacked & 128) != 0 ? 3 * (1 << ((localPacked & 7) + 1)) : 0;
        int paletteStart = localLength > 0 ? p + 10 : 13, paletteLength = localLength > 0 ? localLength : globalLength;
        if (paletteLength == 0) throw new InvalidDataException("Missing GIF palette");
        Require(data, paletteStart, paletteLength);
        int begin = p + 10 + localLength; Require(data, begin, 2);
        if (data[begin] is < 2 or > 8) throw new InvalidDataException("Invalid GIF LZW code size");
        int end = SkipBlocks(data, begin + 1); // Validate before writing anything.
        if (!header)
        {
            output.Write("GIF89a"u8); output.Write(data, 6, 4); output.Write(new byte[] { 0x70, 0, 0 });
            output.Write(new byte[] { 0x21, 0xFF, 0x0B }); output.Write("NETSCAPE2.0"u8); output.Write(new byte[] { 3, 1, 0, 0, 0 });
            width = w; height = h; header = true;
        }
        output.Write(new byte[] { 0x21, 0xF9, 4, 4, (byte)delay, (byte)(delay >> 8), 0, 0 });
        output.Write(data, p, 9); output.WriteByte((byte)((localPacked & 0x40) | 0x80 | ((localLength > 0 ? localPacked : packed) & 7)));
        output.Write(data, paletteStart, paletteLength); output.Write(data, begin, end - begin);
    }
    static ushort Read16(byte[] data, int offset) => (ushort)(data[offset] | (data[offset + 1] << 8));
    static void Require(byte[] data, int offset, int length) { if (offset < 0 || length < 0 || offset > data.Length - length) throw new InvalidDataException("Truncated GIF frame"); }
    static int SkipBlocks(byte[] data, int offset)
    {
        while (true) { Require(data, offset, 1); int length = data[offset++]; if (length == 0) return offset; Require(data, offset, length); offset += length; }
    }
    public void Dispose() { if (disposed) return; disposed = true; try { if (header) output.WriteByte(0x3B); } finally { output.Dispose(); } }
}
