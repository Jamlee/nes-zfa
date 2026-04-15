using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using NezAvalonia.Core;
using System;

namespace NezAvalonia.Controls;

public enum GamepadMode { Full, JoystickOnly, ButtonsOnly }

/// <summary>
/// Virtual gamepad for touch/mobile input.
/// Landscape layout: Left joystick | Center SELECT/START | Right A/B/TA/TB diamond.
/// Matches Flutter VirtualGamepad layout.
/// </summary>
public class VirtualGamepad : UserControl
{
    public event Action<int, bool>? ButtonChanged;
    public event Action<bool>? TurboAChanged;
    public event Action<bool>? TurboBChanged;

    public static readonly StyledProperty<GamepadMode> ModeProperty =
        AvaloniaProperty.Register<VirtualGamepad, GamepadMode>(nameof(Mode), GamepadMode.Full);

    public GamepadMode Mode
    {
        get => GetValue(ModeProperty);
        set => SetValue(ModeProperty, value);
    }

    public VirtualGamepad()
    {
        // Build UI on loaded to respect Mode property
    }

    protected override void OnLoaded(Avalonia.Interactivity.RoutedEventArgs e)
    {
        base.OnLoaded(e);
        BuildUI();
    }

    private void BuildUI()
    {
        var mode = Mode;

        if (mode == GamepadMode.JoystickOnly)
        {
            var joystick = new JoystickControl { Width = 150, Height = 150 };
            joystick.DirectionChanged += (up, down, left, right) =>
            {
                ButtonChanged?.Invoke(NezBindings.ButtonUp, up);
                ButtonChanged?.Invoke(NezBindings.ButtonDown, down);
                ButtonChanged?.Invoke(NezBindings.ButtonLeft, left);
                ButtonChanged?.Invoke(NezBindings.ButtonRight, right);
            };
            Content = new Panel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Children = { joystick },
            };
            return;
        }

        if (mode == GamepadMode.ButtonsOnly)
        {
            Content = new Panel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Children = { CreateDiamondButtons() },
            };
            return;
        }

        // Full mode: joystick left, buttons right
        var root = new Grid
        {
            ColumnDefinitions = ColumnDefinitions.Parse("*,*"),
        };

        var joy = new JoystickControl { Width = 150, Height = 150 };
        joy.DirectionChanged += (up, down, left, right) =>
        {
            ButtonChanged?.Invoke(NezBindings.ButtonUp, up);
            ButtonChanged?.Invoke(NezBindings.ButtonDown, down);
            ButtonChanged?.Invoke(NezBindings.ButtonLeft, left);
            ButtonChanged?.Invoke(NezBindings.ButtonRight, right);
        };
        var leftPanel = new Panel
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(16, 0, 0, 0),
            Children = { joy },
        };
        root.Children.Add(leftPanel);
        Grid.SetColumn(leftPanel, 0);

        var actionPanel = CreateDiamondButtons();
        var rightPanel = new Panel
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 16, 0),
            Children = { actionPanel },
        };
        root.Children.Add(rightPanel);
        Grid.SetColumn(rightPanel, 1);

        Content = root;
    }

    /// <summary>
    /// Diamond layout: TA top, TB left, A right, B bottom.
    /// Matches Flutter _ActionButtons with offset=52, btnSize=56.
    /// </summary>
    private Panel CreateDiamondButtons()
    {
        const double btnSize = 56;
        const double offset = 52;
        const double areaSize = btnSize + offset * 2; // 160
        double center = areaSize / 2;
        double half = btnSize / 2;

        var canvas = new Canvas
        {
            Width = areaSize,
            Height = areaSize,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };

        // TA - top
        var ta = CreateRoundButton("TA", btnSize, Color.Parse("#FF8A80"), true);
        Canvas.SetLeft(ta, center - half);
        Canvas.SetTop(ta, center - offset - half);
        ta.PointerPressed += (_, _) => TurboAChanged?.Invoke(true);
        ta.PointerReleased += (_, _) => TurboAChanged?.Invoke(false);
        ta.PointerCaptureLost += (_, _) => TurboAChanged?.Invoke(false);
        canvas.Children.Add(ta);

        // B - bottom
        var b = CreateRoundButton("B", btnSize, Color.Parse("#FFA726"), false);
        Canvas.SetLeft(b, center - half);
        Canvas.SetTop(b, center + offset - half);
        b.PointerPressed += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonB, true);
        b.PointerReleased += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonB, false);
        b.PointerCaptureLost += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonB, false);
        canvas.Children.Add(b);

        // TB - left
        var tb = CreateRoundButton("TB", btnSize, Color.Parse("#FFCC80"), true);
        Canvas.SetLeft(tb, center - offset - half);
        Canvas.SetTop(tb, center - half);
        tb.PointerPressed += (_, _) => TurboBChanged?.Invoke(true);
        tb.PointerReleased += (_, _) => TurboBChanged?.Invoke(false);
        tb.PointerCaptureLost += (_, _) => TurboBChanged?.Invoke(false);
        canvas.Children.Add(tb);

        // A - right
        var a = CreateRoundButton("A", btnSize, Color.Parse("#EF5350"), false);
        Canvas.SetLeft(a, center + offset - half);
        Canvas.SetTop(a, center - half);
        a.PointerPressed += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonA, true);
        a.PointerReleased += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonA, false);
        a.PointerCaptureLost += (_, _) => ButtonChanged?.Invoke(NezBindings.ButtonA, false);
        canvas.Children.Add(a);

        return canvas;
    }

    private static Border CreateRoundButton(string label, double size, Color color, bool outline)
    {
        var border = new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size / 2),
            Background = outline
                ? Brushes.Transparent
                : new SolidColorBrush(color),
            BorderBrush = new SolidColorBrush(color),
            BorderThickness = new Thickness(outline ? 2.5 : 0),
            Child = new TextBlock
            {
                Text = label,
                FontSize = label.Length > 1 ? 14 : 18,
                FontWeight = FontWeight.Bold,
                Foreground = outline ? new SolidColorBrush(color) : Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
            BoxShadow = new BoxShadows(new BoxShadow
            {
                Color = Color.FromArgb(80, color.R, color.G, color.B),
                Blur = 10,
            }),
        };
        return border;
    }

}

/// <summary>
/// Virtual joystick with angle-based direction detection.
/// </summary>
public class JoystickControl : Control
{
    private Point _thumbOffset;
    private bool _isDragging;
    private const double ThumbRadius = 28;
    private const double DeadZone = 0.25;

    public event Action<bool, bool, bool, bool>? DirectionChanged;

    public JoystickControl()
    {
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
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
            UpdateThumb(e.GetPosition(this));
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
        double cx = Bounds.Width / 2;
        double cy = Bounds.Height / 2;
        double dx = pos.X - cx;
        double dy = pos.Y - cy;
        double maxDist = Math.Min(cx, cy) - ThumbRadius;

        double dist = Math.Sqrt(dx * dx + dy * dy);
        if (dist > maxDist)
        {
            dx = dx / dist * maxDist;
            dy = dy / dist * maxDist;
            dist = maxDist;
        }

        _thumbOffset = new Point(dx, dy);
        InvalidateVisual();

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
        double cx = Bounds.Width / 2;
        double cy = Bounds.Height / 2;
        double baseRadius = Math.Min(cx, cy) - 4;

        // Base ring
        var ringBrush = new SolidColorBrush(Color.Parse("#2A2A44"));
        context.DrawEllipse(null, new Pen(ringBrush, 2.5),
            new Point(cx, cy), baseRadius, baseRadius);

        // Inner subtle fill
        var fillBrush = new SolidColorBrush(Color.FromArgb(15, 255, 255, 255));
        context.DrawEllipse(fillBrush, null,
            new Point(cx, cy), baseRadius, baseRadius);

        // Direction dots
        var dotBrush = new SolidColorBrush(Color.Parse("#444466"));
        double dotR = 3;
        double off = baseRadius - 12;
        context.DrawEllipse(dotBrush, null, new Point(cx, cy - off), dotR, dotR);
        context.DrawEllipse(dotBrush, null, new Point(cx, cy + off), dotR, dotR);
        context.DrawEllipse(dotBrush, null, new Point(cx - off, cy), dotR, dotR);
        context.DrawEllipse(dotBrush, null, new Point(cx + off, cy), dotR, dotR);

        // Thumb
        var thumbColor = _isDragging ? Color.Parse("#6C5CE7") : Color.Parse("#333355");
        var thumbBrush = new SolidColorBrush(thumbColor);
        var thumbCenter = new Point(cx + _thumbOffset.X, cy + _thumbOffset.Y);
        context.DrawEllipse(thumbBrush, new Pen(Brushes.White, 1.5),
            thumbCenter, ThumbRadius, ThumbRadius);
    }
}
