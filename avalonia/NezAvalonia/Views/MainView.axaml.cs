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
        UpdatePageVisibility();
    }

    private void OnNavRecordings(object? sender, RoutedEventArgs e)
    {
        Vm.SelectedIndex = 1;
        UpdatePageVisibility();
        Vm.RecordingsVm.LoadRecordingsCommand.Execute(null);
    }

    private void OnNavSettings(object? sender, RoutedEventArgs e)
    {
        Vm.SelectedIndex = 2;
        UpdatePageVisibility();
    }

    private void UpdatePageVisibility()
    {
        bool lib = Vm.SelectedIndex == 0;
        bool rec = Vm.SelectedIndex == 1;
        bool set = Vm.SelectedIndex == 2;

        // Desktop layout pages
        if (LibraryPage != null) LibraryPage.IsVisible = lib;
        if (RecordingsPage != null) RecordingsPage.IsVisible = rec;
        if (SettingsPage != null) SettingsPage.IsVisible = set;

        // Mobile layout pages
        if (MobileLibraryPage != null) MobileLibraryPage.IsVisible = lib;
        if (MobileRecordingsPage != null) MobileRecordingsPage.IsVisible = rec;
        if (MobileSettingsPage != null) MobileSettingsPage.IsVisible = set;

        UpdateNavHighlight();
    }

    private void UpdateNavHighlight()
    {
        // Desktop sidebar
        if (NavLibrary != null) SetSidebarActive(NavLibrary, Vm.SelectedIndex == 0);
        if (NavRecordings != null) SetSidebarActive(NavRecordings, Vm.SelectedIndex == 1);
        if (NavSettings != null) SetSidebarActive(NavSettings, Vm.SelectedIndex == 2);

        // Mobile bottom nav
        if (MobileNavLibrary != null) SetMobileNavActive(MobileNavLibrary, Vm.SelectedIndex == 0);
        if (MobileNavRecordings != null) SetMobileNavActive(MobileNavRecordings, Vm.SelectedIndex == 1);
        if (MobileNavSettings != null) SetMobileNavActive(MobileNavSettings, Vm.SelectedIndex == 2);
    }

    private static void SetSidebarActive(Button btn, bool active)
    {
        if (active)
        {
            btn.Classes.Remove("sidebar-item");
            if (!btn.Classes.Contains("sidebar-item-active"))
                btn.Classes.Add("sidebar-item-active");
        }
        else
        {
            btn.Classes.Remove("sidebar-item-active");
            if (!btn.Classes.Contains("sidebar-item"))
                btn.Classes.Add("sidebar-item");
        }
    }

    private static void SetMobileNavActive(Button btn, bool active)
    {
        if (active)
        {
            btn.Classes.Remove("mobile-nav");
            if (!btn.Classes.Contains("mobile-nav-active"))
                btn.Classes.Add("mobile-nav-active");
        }
        else
        {
            btn.Classes.Remove("mobile-nav-active");
            if (!btn.Classes.Contains("mobile-nav"))
                btn.Classes.Add("mobile-nav");
        }
    }

    protected override void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        UpdatePageVisibility();
    }

    public void LaunchGame(string romPath, string romName)
    {
        Vm.LaunchGame(romPath, romName);
        Vm.GameplayVm?.Initialize();
    }

    public void ExitGameplay()
    {
        Vm.ExitGameplay();
        // Navigate back to Library page
        Vm.SelectedIndex = 0;
        UpdatePageVisibility();
    }
}
