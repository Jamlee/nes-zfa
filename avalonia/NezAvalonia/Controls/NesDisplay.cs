using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using NezAvalonia.Core;

namespace NezAvalonia.Controls;

/// <summary>
/// Custom control that renders the NES framebuffer via WriteableBitmap.
/// Mirrors the Flutter NesDisplay widget: nearest-neighbor scaling, FPS overlay.
/// </summary>
public class NesDisplay : Control
{
    private WriteableBitmap? _bitmap;
    private int _fps;
    private bool _showFps = true;

    public NesDisplay()
    {
        // Set once in constructor — NOT in Render(), which triggers InvalidateVisual and crashes
        RenderOptions.SetBitmapInterpolationMode(this, BitmapInterpolationMode.None);
    }

    public void SetBitmap(WriteableBitmap? bitmap)
    {
        _bitmap = bitmap;
    }

    public void SetFps(int fps)
    {
        _fps = fps;
    }

    public void SetShowFps(bool show)
    {
        _showFps = show;
    }

    public override void Render(DrawingContext context)
    {
        base.Render(context);

        var bounds = new Rect(0, 0, Bounds.Width, Bounds.Height);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;

        // Black background
        context.DrawRectangle(Brushes.Black, null, bounds);

        if (_bitmap != null)
        {
            // Calculate aspect-fit rect (4:3 for NES 256x240)
            double srcW = _bitmap.PixelSize.Width;
            double srcH = _bitmap.PixelSize.Height;
            double srcAspect = srcW / srcH;
            double dstAspect = bounds.Width / bounds.Height;

            double drawW, drawH;
            if (dstAspect > srcAspect)
            {
                drawH = bounds.Height;
                drawW = drawH * srcAspect;
            }
            else
            {
                drawW = bounds.Width;
                drawH = drawW / srcAspect;
            }

            double x = (bounds.Width - drawW) / 2;
            double y = 0; // Top-aligned, no gap above game

            var sourceRect = new Rect(0, 0, srcW, srcH);
            var destRect = new Rect(x, y, drawW, drawH);

            // Nearest-neighbor already set in constructor
            context.DrawImage(_bitmap, sourceRect, destRect);
        }
        else
        {
            // Placeholder text
            var text = new FormattedText(
                "NES 256 x 240",
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Courier New"),
                14,
                NezTheme.TextDimBrush);

            context.DrawText(text,
                new Point((bounds.Width - text.Width) / 2,
                           (bounds.Height - text.Height) / 2));
        }

        // FPS overlay (top-right)
        if (_showFps && _fps > 0)
        {
            var fpsText = new FormattedText(
                $"{_fps} FPS",
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Courier New", FontStyle.Normal, FontWeight.Bold),
                12,
                NezTheme.AccentGreenBrush);

            double fx = bounds.Width - fpsText.Width - 12;
            double fy = 8;

            // Semi-transparent background
            context.DrawRectangle(
                new SolidColorBrush(Color.FromArgb(128, 0, 0, 0)),
                null,
                new Rect(fx - 4, fy - 2, fpsText.Width + 8, fpsText.Height + 4),
                4, 4);

            context.DrawText(fpsText, new Point(fx, fy));
        }
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        const double aspect = 256.0 / 240.0;

        if (double.IsInfinity(availableSize.Width) && double.IsInfinity(availableSize.Height))
            return new Size(512, 480);
        if (double.IsInfinity(availableSize.Width))
            return new Size(availableSize.Height * aspect, availableSize.Height);
        if (double.IsInfinity(availableSize.Height))
            return new Size(availableSize.Width, availableSize.Width / aspect);

        // Both constrained: fit within bounds preserving aspect ratio
        double fitW = availableSize.Width;
        double fitH = fitW / aspect;
        if (fitH > availableSize.Height)
        {
            fitH = availableSize.Height;
            fitW = fitH * aspect;
        }
        return new Size(fitW, fitH);
    }
}
