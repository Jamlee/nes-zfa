using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

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
    public SettingsViewModel SettingsVm { get; } = new();

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
        GameplayVm = new GameplayViewModel(romPath, romName);
        IsInGameplay = true;
    }

    public void ExitGameplay()
    {
        GameplayVm?.Dispose();
        GameplayVm = null;
        IsInGameplay = false;
    }
}
