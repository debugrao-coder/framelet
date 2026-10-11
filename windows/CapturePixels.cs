namespace Framelet;
internal static class CapturePixels
{
    public static byte[] CropBgra(ReadOnlySpan<byte> pixels, int sourceWidth, int sourceHeight,
        int x, int y, int width, int height)
    {
        if (sourceWidth < 1 || sourceHeight < 1 || width < 1 || height < 1 || x < 0 || y < 0 ||
            (long)x + width > sourceWidth || (long)y + height > sourceHeight ||
            (long)sourceWidth * sourceHeight > 64_000_000 || (long)sourceWidth * sourceHeight * 4 > pixels.Length)
            throw new ArgumentException("Invalid physical-pixel crop geometry");
        var result = new byte[checked(width * height * 4)];
        for (int row = 0; row < height; row++)
            pixels.Slice(checked(((y + row) * sourceWidth + x) * 4), checked(width * 4))
                .CopyTo(result.AsSpan(checked(row * width * 4), checked(width * 4)));
        return result;
    }
}
