using System;
using System.Threading.Tasks;
using Avalonia.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NezAvalonia.Core;

namespace NezAvalonia.ViewModels;

/// <summary>
/// Gameplay state: manages NezEngine, keyboard input, debug panel.
/// Mirrors the Flutter GameplayScreen state exactly.
/// Consumes SettingsViewModel to apply user preferences in real-time.
/// </summary>
public partial class GameplayViewModel : ObservableObject, IDisposable
{
    private readonly INezEngine _engine;
    private readonly SettingsViewModel _settings;

    public INezEngine Engine => _engine;
    public SettingsViewModel Settings => _settings;
    public string RomName { get; }
    public string RomPath { get; }

    [ObservableProperty]
    private bool _showDebugPanel;

    [ObservableProperty]
    private bool _isDesktop = true;

    [ObservableProperty]
    private bool _hasError;

    [ObservableProperty]
    private string _errorMessage = string.Empty;

    public GameplayViewModel(string romPath, string romName, SettingsViewModel settings)
    {
        RomPath = romPath;
        RomName = romName;
        _settings = settings;
        _engine = NezEngineFactory.Create();

        _engine.FrameReady += () =>
        {
            OnPropertyChanged(nameof(Engine));
        };

        // Apply current settings to engine
        ApplySettingsToEngine();

        // Subscribe to settings changes
        _settings.PropertyChanged += OnSettingsPropertyChanged;

        // Initialize debug panel from settings
        ShowDebugPanel = _settings.DebugMode;
    }

    private void OnSettingsPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(Settings.SoundEnabled):
            case nameof(Settings.Volume):
                ApplyAudioSettings();
                break;
            case nameof(Settings.DebugMode):
                ShowDebugPanel = Settings.DebugMode;
                break;
        }
    }

    /// <summary>
    /// Apply all settings to the engine. Called once at init.
    /// </summary>
    private void ApplySettingsToEngine()
    {
        ApplyAudioSettings();
    }

    private void ApplyAudioSettings()
    {
        _engine.SetSoundEnabled(_settings.SoundEnabled);
        _engine.SetVolume(_settings.Volume);
    }

    public void Initialize()
    {
#if BROWSER
        // On browser, ROM must be loaded from bytes (not file path)
        // The LoadRom method with file path won't work on WASM.
        // Use LoadRomFromBytes instead, called from the browser host.
        if (_engine is NezWasmEngine wasmEngine)
        {
            // Browser loading is handled by the UI layer
            return;
        }
#else
        if (!_engine.LoadRom(RomPath))
        {
            HasError = true;
            ErrorMessage = _engine.LoadError ?? "Unknown error loading ROM";
            return;
        }
#endif
        _engine.StartLoop();
        // Apply audio settings after loop starts (player is created in StartLoop)
        ApplyAudioSettings();
    }

    /// <summary>
    /// Handle keyboard input. Returns true if the key was consumed.
    /// Maps exactly match Flutter version:
    ///   W/A/S/D = movement, J/K = A/B, U/I = turbo A/B
    ///   Space = pause, Esc = back, X = select, Enter = start
    ///   Cmd+D / Ctrl+D = debug panel
    /// </summary>
    public bool HandleKeyDown(Key key, KeyModifiers modifiers)
    {
        // Debug toggle: Cmd+D (macOS) or Ctrl+D
        if (key == Key.D && (modifiers.HasFlag(KeyModifiers.Meta) || modifiers.HasFlag(KeyModifiers.Control)))
        {
            ShowDebugPanel = !ShowDebugPanel;
            return true;
        }

        switch (key)
        {
            case Key.W:     _engine.SetButton(NezBindings.ButtonUp, true); return true;
            case Key.S:     _engine.SetButton(NezBindings.ButtonDown, true); return true;
            case Key.A:     _engine.SetButton(NezBindings.ButtonLeft, true); return true;
            case Key.D:     _engine.SetButton(NezBindings.ButtonRight, true); return true;
            case Key.J:     _engine.SetButton(NezBindings.ButtonA, true); return true;
            case Key.K:     _engine.SetButton(NezBindings.ButtonB, true); return true;
            case Key.U:     _engine.SetTurboA(true); return true;
            case Key.I:     _engine.SetTurboB(true); return true;
            case Key.Return: _engine.SetButton(NezBindings.ButtonStart, true); return true;
            case Key.X:     _engine.SetButton(NezBindings.ButtonSelect, true); return true;
            case Key.Space:  _engine.TogglePause(); return true;
        }
        return false;
    }

    public bool HandleKeyUp(Key key)
    {
        switch (key)
        {
            case Key.W:     _engine.SetButton(NezBindings.ButtonUp, false); return true;
            case Key.S:     _engine.SetButton(NezBindings.ButtonDown, false); return true;
            case Key.A:     _engine.SetButton(NezBindings.ButtonLeft, false); return true;
            case Key.D:     _engine.SetButton(NezBindings.ButtonRight, false); return true;
            case Key.J:     _engine.SetButton(NezBindings.ButtonA, false); return true;
            case Key.K:     _engine.SetButton(NezBindings.ButtonB, false); return true;
            case Key.U:     _engine.SetTurboA(false); return true;
            case Key.I:     _engine.SetTurboB(false); return true;
            case Key.Return: _engine.SetButton(NezBindings.ButtonStart, false); return true;
            case Key.X:     _engine.SetButton(NezBindings.ButtonSelect, false); return true;
        }
        return false;
    }

    [ObservableProperty]
    private bool _isRecording;

    [RelayCommand]
    private void TogglePause() => _engine.TogglePause();

    [RelayCommand]
    private void ToggleDebug() => ShowDebugPanel = !ShowDebugPanel;

    [ObservableProperty]
    private string? _statusMessage;

    [RelayCommand]
    private async Task ToggleRecord()
    {
        if (_engine.IsRecording)
        {
            IsRecording = false;
            var path = await _engine.StopRecording();
            System.Diagnostics.Debug.WriteLine($"NEZ: GIF saved: {path}");
        }
        else
        {
            _engine.StartRecording(RomName);
            IsRecording = true;
        }
    }

    public void Dispose()
    {
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        _engine.Dispose();
    }
}
