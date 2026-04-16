using System;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NezAvalonia.Core;

namespace NezAvalonia.ViewModels;

/// <summary>
/// Shell navigation state. Manages sidebar/bottom nav selection
/// and which view is currently active.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private int _selectedIndex;

    [ObservableProperty]
    private object? _currentView;

    [ObservableProperty]
    private bool _isDesktop = true;

    // View instances (lazy created by the MainWindow)
    public LibraryViewModel LibraryVm { get; } = new();
    public RecordingsViewModel RecordingsVm { get; } = new();
    public SettingsViewModel SettingsVm { get; } = new();

#if !BROWSER
    // Global gamepad server — lives for the entire app lifetime
    public GamepadServer? GamepadServerInstance { get; set; }
#endif

    // Navigation to gameplay
    [ObservableProperty]
    private bool _isInGameplay;

    [ObservableProperty]
    private GameplayViewModel? _gameplayVm;

    [RelayCommand]
    private void Navigate(int index)
    {
        SelectedIndex = index;
    }

    public void LaunchGame(string romPath, string romName)
    {
        GameplayVm = new GameplayViewModel(romPath, romName, SettingsVm) { IsDesktop = IsDesktop };
        IsInGameplay = true;
    }

    public void ExitGameplay()
    {
        // Unset engine from gamepad server (server keeps running)
#if !BROWSER
        GamepadServerInstance?.SetEngine(null);
#endif
        GameplayVm?.Dispose();
        GameplayVm = null;
        IsInGameplay = false;
    }
}
