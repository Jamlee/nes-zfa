using Avalonia.Media;

namespace NezAvalonia.Core;

/// <summary>
/// Centralized color palette matching the Flutter version exactly.
/// </summary>
public static class NezTheme
{
    // Backgrounds
    public static readonly Color BgDark     = Color.Parse("#0A0A0F");
    public static readonly Color BgCard     = Color.Parse("#12121A");
    public static readonly Color BgSurface  = Color.Parse("#1A1A2E");
    public static readonly Color BgElevated = Color.Parse("#222240");

    // Accents
    public static readonly Color AccentPrimary   = Color.Parse("#6C5CE7");
    public static readonly Color AccentSecondary = Color.Parse("#A29BFE");
    public static readonly Color AccentRed       = Color.Parse("#FF6B6B");
    public static readonly Color AccentGreen     = Color.Parse("#51CF66");
    public static readonly Color AccentOrange    = Color.Parse("#FFA94D");
    public static readonly Color AccentCyan      = Color.Parse("#22D3EE");

    // Text
    public static readonly Color TextPrimary   = Color.Parse("#F0F0F5");
    public static readonly Color TextSecondary = Color.Parse("#8888AA");
    public static readonly Color TextDim       = Color.Parse("#555577");

    // Borders
    public static readonly Color Border = Color.Parse("#2A2A44");

    // Brush helpers
    public static readonly IBrush BgDarkBrush     = new SolidColorBrush(BgDark);
    public static readonly IBrush BgCardBrush     = new SolidColorBrush(BgCard);
    public static readonly IBrush BgSurfaceBrush  = new SolidColorBrush(BgSurface);
    public static readonly IBrush BgElevatedBrush = new SolidColorBrush(BgElevated);

    public static readonly IBrush AccentPrimaryBrush   = new SolidColorBrush(AccentPrimary);
    public static readonly IBrush AccentSecondaryBrush = new SolidColorBrush(AccentSecondary);
    public static readonly IBrush AccentRedBrush       = new SolidColorBrush(AccentRed);
    public static readonly IBrush AccentGreenBrush     = new SolidColorBrush(AccentGreen);
    public static readonly IBrush AccentOrangeBrush    = new SolidColorBrush(AccentOrange);
    public static readonly IBrush AccentCyanBrush      = new SolidColorBrush(AccentCyan);

    public static readonly IBrush TextPrimaryBrush   = new SolidColorBrush(TextPrimary);
    public static readonly IBrush TextSecondaryBrush = new SolidColorBrush(TextSecondary);
    public static readonly IBrush TextDimBrush       = new SolidColorBrush(TextDim);

    public static readonly IBrush BorderBrush = new SolidColorBrush(Border);

    // Gradient used for "Nez" logo
    public static readonly LinearGradientBrush PrimaryGradient = new()
    {
        StartPoint = new Avalonia.RelativePoint(0, 0, Avalonia.RelativeUnit.Relative),
        EndPoint   = new Avalonia.RelativePoint(1, 1, Avalonia.RelativeUnit.Relative),
        GradientStops =
        {
            new GradientStop(AccentPrimary, 0),
            new GradientStop(AccentSecondary, 1)
        }
    };

    // Card colors for ROM library (cycle by index)
    public static readonly Color[] CardColors =
    [
        Color.Parse("#E74C3C"), // Red
        Color.Parse("#F39C12"), // Orange
        Color.Parse("#3498DB"), // Blue
        Color.Parse("#2ECC71"), // Green
        Color.Parse("#9B59B6"), // Purple
        Color.Parse("#1ABC9C"), // Teal
        Color.Parse("#E91E63"), // Pink
        Color.Parse("#607D8B"), // Gray
    ];
}
