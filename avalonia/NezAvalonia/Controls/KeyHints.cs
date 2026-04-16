using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using NezAvalonia.Core;
using System;

namespace NezAvalonia.Controls;

/// <summary>
/// Single keyboard shortcut badge. Mirrors Flutter KeyBadge.
/// Renders as a small keycap with 3D border effect.
/// </summary>
public class KeyBadge : Border
{
    public static readonly StyledProperty<string> LabelProperty =
        AvaloniaProperty.Register<KeyBadge, string>(nameof(Label), "");

    public string Label
    {
        get => GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public KeyBadge()
    {
        CornerRadius = new CornerRadius(3);
        Padding = new Thickness(5, 2);
        MinWidth = 20;
        Background = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255));
        BorderBrush = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255));
        BorderThickness = new Thickness(1, 1, 1, 2); // 3D bottom border
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;

        UpdateContent();
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == LabelProperty)
            UpdateContent();
    }

    private void UpdateContent()
    {
        Child = new TextBlock
        {
            Text = Label.ToUpperInvariant(),
            FontSize = 10,
            FontWeight = FontWeight.SemiBold,
            FontFamily = new FontFamily("Courier New"),
            Foreground = NezTheme.TextDimBrush,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            LineHeight = 12,
        };
    }
}

/// <summary>
/// Keybind row: [Key Badge] [Key Badge] ... | Label
/// Mirrors Flutter KeybindItem.
/// </summary>
public class KeybindItem : StackPanel
{
    public static readonly StyledProperty<string> KeysProperty =
        AvaloniaProperty.Register<KeybindItem, string>(nameof(Keys), "");

    public static readonly StyledProperty<string> LabelProperty =
        AvaloniaProperty.Register<KeybindItem, string>(nameof(Label), "");

    public string Keys
    {
        get => GetValue(KeysProperty);
        set => SetValue(KeysProperty, value);
    }

    public string Label
    {
        get => GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public KeybindItem()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 3;
        VerticalAlignment = VerticalAlignment.Center;

        UpdateContent();
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == KeysProperty || change.Property == LabelProperty)
            UpdateContent();
    }

    private void UpdateContent()
    {
        Children.Clear();

        if (!string.IsNullOrEmpty(Keys))
        {
            var keys = Keys.Split(',', StringSplitOptions.RemoveEmptyEntries);
            foreach (var key in keys)
            {
                Children.Add(new KeyBadge { Label = key.Trim() });
            }
        }

        Children.Add(new TextBlock
        {
            Text = Label,
            FontSize = 11,
            Foreground = NezTheme.TextDimBrush,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(3, 0, 0, 0),
        });
    }
}
