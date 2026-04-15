using CommunityToolkit.Mvvm.ComponentModel;

namespace NezAvalonia.ViewModels;

/// <summary>
/// Settings state. Mirrors Flutter SettingsScreen state exactly.
/// Currently UI-only (not persisted).
/// </summary>
public partial class SettingsViewModel : ObservableObject
{
    // Display
    [ObservableProperty] private bool _showFps = true;
    [ObservableProperty] private string _aspectRatio = "4:3 Original";
    [ObservableProperty] private string _pixelFilter = "None";

    // Audio
    [ObservableProperty] private bool _soundEnabled = true;
    [ObservableProperty] private double _volume = 0.8;

    // Controls
    [ObservableProperty] private bool _vibration = true;
    [ObservableProperty] private string _buttonSize = "Medium";
    [ObservableProperty] private double _buttonOpacity = 0.7;

    // Advanced
    [ObservableProperty] private bool _debugMode;

    // Dropdown options
    public static string[] AspectRatioOptions => ["4:3 Original", "16:9 Stretch", "Pixel Perfect"];
    public static string[] PixelFilterOptions => ["None", "CRT Scanline", "LCD Grid"];
    public static string[] ButtonSizeOptions => ["Small", "Medium", "Large"];
}
