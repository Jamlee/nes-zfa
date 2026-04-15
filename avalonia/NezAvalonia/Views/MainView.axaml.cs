using Avalonia.Controls;
using Avalonia.Interactivity;
using NezAvalonia.ViewModels;

namespace NezAvalonia.Views;

public partial class MainView : UserControl
{
    private MainViewModel Vm => (MainViewModel)DataContext!;

    public MainView()
    {
        InitializeComponent();
    }

    private void OnNavLibrary(object? sender, RoutedEventArgs e)
    {
        Vm.SelectedIndex = 0;
        LibraryPage!.IsVisible = true;
        SettingsPage!.IsVisible = false;
        UpdateSidebarHighlight();
    }

    private void OnNavSettings(object? sender, RoutedEventArgs e)
    {
        Vm.SelectedIndex = 1;
        LibraryPage!.IsVisible = false;
        SettingsPage!.IsVisible = true;
        UpdateSidebarHighlight();
    }

    private void UpdateSidebarHighlight()
    {
        NavLibrary!.Background = Vm.SelectedIndex == 0
            ? Core.NezTheme.BgElevatedBrush
            : Avalonia.Media.Brushes.Transparent;
        NavSettings!.Background = Vm.SelectedIndex == 1
            ? Core.NezTheme.BgElevatedBrush
            : Avalonia.Media.Brushes.Transparent;
    }

    protected override void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        UpdateSidebarHighlight();
    }

    public void LaunchGame(string romPath, string romName)
    {
        Vm.LaunchGame(romPath, romName);
        Vm.GameplayVm?.Initialize();
    }

    public void ExitGameplay()
    {
        Vm.ExitGameplay();
    }
}
