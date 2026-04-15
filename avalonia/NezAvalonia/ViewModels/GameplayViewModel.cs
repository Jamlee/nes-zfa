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
/// </summary>
public partial class GameplayViewModel : ObservableObject, IDisposable
{
    private readonly NezEngine _engine = new();

    public NezEngine Engine => _engine;
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

    public GameplayViewModel(string romPath, string romName)
    {
        RomPath = romPath;
        RomName = romName;

        _engine.FrameReady += () =>
        {
            OnPropertyChanged(nameof(Engine));
        };
    }

    public void Initialize()
    {
        if (!_engine.LoadRom(RomPath))
        {
            HasError = true;
            ErrorMessage = _engine.LoadError ?? "Unknown error loading ROM";
            return;
        }
        _engine.StartLoop();
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
            _engine.StartRecording();
            IsRecording = true;
        }
    }

    public void Dispose()
    {
        _engine.Dispose();
    }
}
