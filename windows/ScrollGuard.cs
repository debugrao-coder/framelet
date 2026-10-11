using System.IO;
namespace Framelet;
/// <summary>
/// The Rust detector deliberately ignores fixed edge bands. A positive translation
/// is not permission to append the next bottom rows: every retained overlap pixel
/// must agree, including the old footer/new header. Reject rather than lose lines.
/// </summary>
internal static class ScrollGuard
{
    public static void RequireExactOverlap(ReadOnlySpan<byte> previous, ReadOnlySpan<byte> next,
        int width, int height, int stride, int delta)
    {
        if (width < 1 || height < 2 || stride < (long)width * 4 || delta < 1 || delta >= height)
            throw new ArgumentException("Invalid scroll frame geometry");
        long required = (long)(height - 1) * stride + (long)width * 4;
        if (required > previous.Length || required > next.Length)
            throw new ArgumentException("Short scroll frame buffer");
        int visibleBytes = checked(width * 4);
        for (int y = 0; y < height - delta; y++)
        {
            if (!previous.Slice(checked((y + delta) * stride), visibleBytes)
                .SequenceEqual(next.Slice(checked(y * stride), visibleBytes)))
                throw new InvalidDataException("重叠区域或边缘不一致，未拼接。可能包含固定页眉/页脚、滚动条或动画；请重新框选纯滚动内容，已有片段仍可保存。");
        }
    }
}
