using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using NezAvalonia.Core;
using System;

namespace NezAvalonia.Controls;

/// <summary>
/// Virtual gamepad for touch/mobile input.
/// Mirrors the Flutter VirtualGamepad: D-Pad (joystick) + A/B + Turbo + Select/Start.
/// </summary>
public class VirtualGamepad : UserControl
{
    public event Action<int, bool>? ButtonChanged;
    public event Action<bool>? TurboAChanged;
    public event Action<bool>? TurboBChanged;

    public VirtualGamepad()
    {
        var root = new Grid
        {
            RowDefinitions = RowDefinitions.Parse("3*,*"),
        };

        // Row 0: D-Pad (left) + Action buttons (right)
        var mainRow = new Grid
        {
            ColumnDefinitions = ColumnDefinitions.Parse("*,*"),
        };

        var joystick = new JoystickControl();
        joystick.DirectionChanged += (up, down, left, right) =>
        {
            ButtonChanged?.Invoke(NezBindings.ButtonUp, up);
            ButtonChanged?.Invoke(NezBindings.ButtonDown, down);
            ButtonChanged?.Invoke(NezBindings.ButtonLeft, left);
            ButtonChanged?.Invoke(NezBindings.ButtonRight, right);
        };
        mainRow.Children.Add(joystick);
        Grid.SetColumn(joystick, 0);

        var actionPanel = CreateActionButtons();
        mainRow.Children.Add(actionPanel);
        Grid.SetColumn(actionPanel, 1);

        root.Children.Add(mainRow);
        Grid.SetRow(mainRow, 0);

        // Row 1: System buttons (Select, Start)
        var systemRow = new StackPanel
        {
            Orientation = Avalonia.Layout.Orientation.Horizontal,
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Spacing = 24,
        };

        systemRow.Children.Add(CreateSystemButton("SELECT", NezBindings.ButtonSelect));
        systemRow.Children.Add(CreateSystemButton("START", NezBindings.ButtonStart));

        root.Children.Add(systemRow);
        Grid.SetRow(systemRow, 1);

        Content = root;
    }

    private Panel CreateActionButtons()
    {
        var grid = new Grid
        {
            RowDefinitions = RowDefinitions.Parse("*,*"),
            ColumnDefinitions = ColumnDefinitions.Parse("*,*"),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Width = 140,
            Height = 120,
        };

        // Turbo B (row 0, col 0)
        var turboB = CreateTurboButton("B", NezTheme.AccentRed, false);
        grid.Children.Add(turboB);
        Grid.SetRow(turboB, 0);
        Grid.SetColumn(turboB, 0);

        // Turbo A (row 0, col 1)
        var turboA = CreateTurboButton("A", NezTheme.AccentPrimary, true);
        grid.Children.Add(turboA);
        Grid.SetRow(turboA, 0);
        Grid.SetColumn(turboA, 1);

        // B button (row 1, col 0)
        var btnB = CreateActionButton("B", NezTheme.AccentRed, NezBindings.ButtonB);
        grid.Children.Add(btnB);
        Grid.SetRow(btnB, 1);
        Grid.SetColumn(btnB, 0);

        // A button (row 1, col 1)
        var btnA = CreateActionButton("A", NezTheme.AccentPrimary, NezBindings.ButtonA);
        grid.Children.Add(btnA);
        Grid.SetRow(btnA, 1);
        Grid.SetColumn(btnA, 1);

        return grid;
    }

    private Control CreateActionButton(string label, Color color, int buttonIndex)
    {
        var border = new Border
        {
            Width = 56,
            Height = 56,
            CornerRadius = new CornerRadius(28),
            Background = new SolidColorBrush(color),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = label,
                FontSize = 18,
                FontWeight = FontWeight.Bold,
                Foreground = Brushes.White,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            },
            BoxShadow = new BoxShadows(new BoxShadow
            {
                Color = Color.FromArgb(100, color.R, color.G, color.B),
                Blur = 12,
            }),
        };

        border.PointerPressed += (_, _) => ButtonChanged?.Invoke(buttonIndex, true);
        border.PointerReleased += (_, _) => ButtonChanged?.Invoke(buttonIndex, false);
        border.PointerCaptureLost += (_, _) => ButtonChanged?.Invoke(buttonIndex, false);

        return border;
    }

    private Control CreateTurboButton(string label, Color color, bool isA)
    {
        var border = new Border
        {
            Width = 44,
            Height = 44,
            CornerRadius = new CornerRadius(22),
            Background = Brushes.Transparent,
            BorderBrush = new SolidColorBrush(color),
            BorderThickness = new Thickness(2),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Child = new StackPanel
            {
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                Children =
                {
                    new TextBlock
                    {
                        Text = "TURBO",
                        FontSize = 6,
                        Foreground = new SolidColorBrush(color),
                        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                    },
                    new TextBlock
                    {
                        Text = label,
                        FontSize = 14,
                        FontWeight = FontWeight.Bold,
                        Foreground = new SolidColorBrush(color),
                        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
                    }
                }
            }
        };

        border.PointerPressed += (_, _) =>
        {
            if (isA) TurboAChanged?.Invoke(true);
            else TurboBChanged?.Invoke(true);
            border.Background = new SolidColorBrush(Color.FromArgb(50, color.R, color.G, color.B));
        };
        border.PointerReleased += (_, _) =>
        {
            if (isA) TurboAChanged?.Invoke(false);
            else TurboBChanged?.Invoke(false);
            border.Background = Brushes.Transparent;
        };

        return border;
    }

    private Control CreateSystemButton(string label, int buttonIndex)
    {
        var border = new Border
        {
            Padding = new Thickness(20, 8),
            CornerRadius = new CornerRadius(20),
            Background = NezTheme.BgSurfaceBrush,
            BorderBrush = NezTheme.BorderBrush,
            BorderThickness = new Thickness(1),
            Child = new TextBlock
            {
                Text = label,
                FontSize = 11,
                Foreground = NezTheme.TextDimBrush,
                LetterSpacing = 2,
                FontWeight = FontWeight.SemiBold,
            }
        };

        border.PointerPressed += (_, _) => ButtonChanged?.Invoke(buttonIndex, true);
        border.PointerReleased += (_, _) => ButtonChanged?.Invoke(buttonIndex, false);

        return border;
    }
}

/// <summary>
/// Virtual joystick D-Pad with angle-based direction detection.
/// Mirrors Flutter _Joystick widget.
/// </summary>
public class JoystickControl : Control
{
    private Point _thumbOffset;
    private bool _isDragging;
    private const double Size = 120;
    private const double ThumbRadius = 25;
    private const double DeadZone = 0.25;

    public event Action<bool, bool, bool, bool>? DirectionChanged; // up, down, left, right

    public JoystickControl()
    {
        Width = Size;
        Height = Size;
        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center;
        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center;
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        _isDragging = true;
        e.Pointer.Capture(this);
        UpdateThumb(e.GetPosition(this));
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_isDragging)
        {
            UpdateThumb(e.GetPosition(this));
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        _isDragging = false;
        _thumbOffset = new Point(0, 0);
        DirectionChanged?.Invoke(false, false, false, false);
        InvalidateVisual();
    }

    private void UpdateThumb(Point pos)
    {
        double cx = Size / 2;
        double cy = Size / 2;
        double dx = pos.X - cx;
        double dy = pos.Y - cy;
        double maxDist = Size / 2 - ThumbRadius;

        double dist = Math.Sqrt(dx * dx + dy * dy);
        if (dist > maxDist)
        {
            dx = dx / dist * maxDist;
            dy = dy / dist * maxDist;
            dist = maxDist;
        }

        _thumbOffset = new Point(dx, dy);
        InvalidateVisual();

        // Direction detection (angle-based, matching Flutter)
        double normalized = dist / maxDist;
        if (normalized < DeadZone)
        {
            DirectionChanged?.Invoke(false, false, false, false);
            return;
        }

        double angle = Math.Atan2(dy, dx) * 180.0 / Math.PI;
        bool up = angle < -30 && angle > -150;
        bool down = angle > 30 && angle < 150;
        bool left = angle > 120 || angle < -120;
        bool right = angle > -60 && angle < 60;

        DirectionChanged?.Invoke(up, down, left, right);
    }

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        double cx = Size / 2;
        double cy = Size / 2;
        double baseRadius = Size / 2 - 4;

        // Base circle
        context.DrawEllipse(null, new Pen(NezTheme.BorderBrush, 2),
            new Point(cx, cy), baseRadius, baseRadius);

        // Direction indicators (4 dots)
        var dotBrush = NezTheme.TextDimBrush;
        double dotR = 3;
        double offset = baseRadius - 10;
        context.DrawEllipse(dotBrush, null, new Point(cx, cy - offset), dotR, dotR); // N
        context.DrawEllipse(dotBrush, null, new Point(cx, cy + offset), dotR, dotR); // S
        context.DrawEllipse(dotBrush, null, new Point(cx - offset, cy), dotR, dotR); // W
        context.DrawEllipse(dotBrush, null, new Point(cx + offset, cy), dotR, dotR); // E

        // Thumb
        var thumbColor = _isDragging ? NezTheme.AccentPrimary : NezTheme.BgElevated;
        var thumbBrush = new SolidColorBrush(thumbColor);
        var thumbCenter = new Point(cx + _thumbOffset.X, cy + _thumbOffset.Y);

        context.DrawEllipse(thumbBrush, new Pen(Brushes.White, 1.5),
            thumbCenter, ThumbRadius, ThumbRadius);
    }
}
