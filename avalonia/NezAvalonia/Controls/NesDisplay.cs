using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using NezAvalonia.Core;

namespace NezAvalonia.Controls;

/// <summary>
/// Custom control that renders the NES framebuffer via WriteableBitmap.
/// Mirrors the Flutter NesDisplay widget: nearest-neighbor scaling, FPS overlay.
/// Supports AspectRatio and PixelFilter settings.
/// </summary>
public class NesDisplay : Control
{
    private WriteableBitmap? _bitmap;
    private int _fps;
    private bool _showFps = true;
    private string _aspectRatio = "4:3 Original";
    private string _pixelFilter = "None";

    // CRT scanline effect: pre-built semi-transparent brush for even rows
    private static readonly IBrush ScanlineBrush = new SolidColorBrush(Color.FromArgb(40, 0, 0, 0));
    // LCD grid effect: thin dark lines every 3rd pixel
    private static readonly IBrush LcdGridBrush = new SolidColorBrush(Color.FromArgb(25, 0, 0, 0));

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

    public void SetAspectRatio(string aspectRatio)
    {
        _aspectRatio = aspectRatio;
        InvalidateVisual();
    }

    public void SetPixelFilter(string pixelFilter)
    {
        _pixelFilter = pixelFilter;
        // Use linear interpolation for filter effects, nearest-neighbor for "None"
        RenderOptions.SetBitmapInterpolationMode(this,
            _pixelFilter == "None" ? BitmapInterpolationMode.None : BitmapInterpolationMode.HighQuality);
        InvalidateVisual();
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
            // Calculate draw rect based on aspect ratio setting
            double srcW = _bitmap.PixelSize.Width;
            double srcH = _bitmap.PixelSize.Height;
            double nesAspect = srcW / srcH; // 256/240 ≈ 1.0667

            double drawW, drawH;

            switch (_aspectRatio)
            {
                case "16:9 Stretch":
                    // Fill the entire bounds, ignoring original aspect
                    drawW = bounds.Width;
                    drawH = bounds.Height;
                    break;

                case "Pixel Perfect":
                    // Integer scaling: find the largest integer scale that fits
                    int scaleX = Math.Max(1, (int)(bounds.Width / srcW));
                    int scaleY = Math.Max(1, (int)(bounds.Height / srcH));
                    int scale = Math.Min(scaleX, scaleY);
                    drawW = srcW * scale;
                    drawH = srcH * scale;
                    break;

                default: // "4:3 Original"
                    // Fit preserving NES aspect ratio
                    double dstAspect = bounds.Width / bounds.Height;
                    if (dstAspect > nesAspect)
                    {
                        drawH = bounds.Height;
                        drawW = drawH * nesAspect;
                    }
                    else
                    {
                        drawW = bounds.Width;
                        drawH = drawW / nesAspect;
                    }
                    break;
            }

            double x = (bounds.Width - drawW) / 2;
            double y = (bounds.Height - drawH) / 2;

            var sourceRect = new Rect(0, 0, srcW, srcH);
            var destRect = new Rect(x, y, drawW, drawH);

            // Interpolation mode is already set via RenderOptions
            context.DrawImage(_bitmap, sourceRect, destRect);

            // Apply pixel filter overlay
            ApplyPixelFilter(context, destRect, drawW, drawH);
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

    /// <summary>
    /// Apply CRT scanline or LCD grid overlay effect after drawing the bitmap.
    /// </summary>
    private void ApplyPixelFilter(DrawingContext context, Rect destRect, double drawW, double drawH)
    {
        if (_pixelFilter == "CRT Scanline")
        {
            // Draw semi-transparent dark lines every 2 pixels (simulating scanlines)
            double step = Math.Max(2, drawH / 120); // Scale step with display size
            using var clip = context.PushClip(destRect);
            for (double y = destRect.Top; y < destRect.Bottom; y += step)
            {
                context.DrawRectangle(ScanlineBrush, null,
                    new Rect(destRect.Left, y, drawW, step * 0.5));
            }
        }
        else if (_pixelFilter == "LCD Grid")
        {
            // Draw a subtle grid pattern
            double step = Math.Max(3, drawH / 80);
            using var clip = context.PushClip(destRect);
            for (double y = destRect.Top; y < destRect.Bottom; y += step)
            {
                context.DrawRectangle(LcdGridBrush, null,
                    new Rect(destRect.Left, y, drawW, 1));
            }
            for (double x = destRect.Left; x < destRect.Right; x += step)
            {
                context.DrawRectangle(LcdGridBrush, null,
                    new Rect(x, destRect.Top, 1, drawH));
            }
        }
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        double aspect = GetTargetAspect();

        if (double.IsInfinity(availableSize.Width) && double.IsInfinity(availableSize.Height))
            return new Size(512, 512 / aspect);
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

    private double GetTargetAspect()
    {
        return _aspectRatio switch
        {
            "16:9 Stretch" => 16.0 / 9.0,
            "Pixel Perfect" => 256.0 / 240.0,
            _ => 256.0 / 240.0 // "4:3 Original"
        };
    }
}
