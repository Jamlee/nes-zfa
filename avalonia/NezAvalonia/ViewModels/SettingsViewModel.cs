using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace NezAvalonia.ViewModels;

/// <summary>
/// Settings state with JSON file persistence.
/// Mirrors Flutter SettingsScreen state.
/// </summary>
public partial class SettingsViewModel : ObservableObject
{
    private static string GetSettingsPath()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home))
            home = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(home))
            home = Path.GetTempPath();
        var dir = Path.Combine(home, ".nes-zfa");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "settings.json");
    }

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

    public SettingsViewModel()
    {
        LoadSettings();
    }

    partial void OnShowFpsChanged(bool value) => SaveSettings();
    partial void OnAspectRatioChanged(string value) => SaveSettings();
    partial void OnPixelFilterChanged(string value) => SaveSettings();
    partial void OnSoundEnabledChanged(bool value) => SaveSettings();
    partial void OnVolumeChanged(double value) => SaveSettings();
    partial void OnVibrationChanged(bool value) => SaveSettings();
    partial void OnButtonSizeChanged(string value) => SaveSettings();
    partial void OnButtonOpacityChanged(double value) => SaveSettings();
    partial void OnDebugModeChanged(bool value) => SaveSettings();

    private void LoadSettings()
    {
        try
        {
            var path = GetSettingsPath();
            if (!File.Exists(path)) return;
            var json = File.ReadAllText(path);
            var data = JsonSerializer.Deserialize(json, SettingsJsonContext.Default.SettingsData);
            if (data == null) return;

            _showFps = data.ShowFps ?? true;
            _aspectRatio = data.AspectRatio ?? "4:3 Original";
            _pixelFilter = data.PixelFilter ?? "None";
            _soundEnabled = data.SoundEnabled ?? true;
            _volume = data.Volume ?? 0.8;
            _vibration = data.Vibration ?? true;
            _buttonSize = data.ButtonSize ?? "Medium";
            _buttonOpacity = data.ButtonOpacity ?? 0.7;
            _debugMode = data.DebugMode ?? false;
        }
        catch
        {
            // Ignore corrupted settings
        }
    }

    private void SaveSettings()
    {
        try
        {
            var data = new SettingsData
            {
                ShowFps = _showFps,
                AspectRatio = _aspectRatio,
                PixelFilter = _pixelFilter,
                SoundEnabled = _soundEnabled,
                Volume = _volume,
                Vibration = _vibration,
                ButtonSize = _buttonSize,
                ButtonOpacity = _buttonOpacity,
                DebugMode = _debugMode,
            };
            var json = JsonSerializer.Serialize(data, SettingsJsonContext.Default.SettingsData);
            File.WriteAllText(GetSettingsPath(), json);
        }
        catch
        {
            // Ignore save errors
        }
    }
}

internal class SettingsData
{
    public bool? ShowFps { get; set; }
    public string? AspectRatio { get; set; }
    public string? PixelFilter { get; set; }
    public bool? SoundEnabled { get; set; }
    public double? Volume { get; set; }
    public bool? Vibration { get; set; }
    public string? ButtonSize { get; set; }
    public double? ButtonOpacity { get; set; }
    public bool? DebugMode { get; set; }
}

[JsonSerializable(typeof(SettingsData))]
[JsonSourceGenerationOptions(WriteIndented = true)]
internal partial class SettingsJsonContext : JsonSerializerContext { }
