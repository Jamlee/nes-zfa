using System.Collections.Specialized;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.VisualTree;
using NezAvalonia.ViewModels;

namespace NezAvalonia.Views;

public partial class LibraryView : UserControl
{
    public LibraryView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private LibraryViewModel? Vm => DataContext as LibraryViewModel;

    private void OnDataContextChanged(object? sender, System.EventArgs e)
    {
        if (Vm == null) return;

        // Wire up button click events in code (more reliable than AXAML Click)
        AddRomBtn!.Click += OnAddRom;
        AddRomEmptyBtn!.Click += OnAddRom;

        // Listen for collection changes to toggle empty/grid visibility
        Vm.FilteredRoms.CollectionChanged += OnFilteredRomsChanged;
        UpdateVisibility();
    }

    private void OnFilteredRomsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        UpdateVisibility();
    }

    private void UpdateVisibility()
    {
        bool hasRoms = Vm?.FilteredRoms.Count > 0;
        EmptyState!.IsVisible = !hasRoms;
        RomGrid!.IsVisible = hasRoms;
    }

    private async void OnAddRom(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel == null) return;

        var files = await topLevel.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select NES ROM",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("NES ROMs") { Patterns = ["*.nes"] },
                new FilePickerFileType("All files") { Patterns = ["*"] }
            ]
        });

        if (files.Count > 0)
        {
            var path = files[0].Path.LocalPath;
            Vm?.AddRom(path);
        }
    }

    // Handle clicks on ROM cards in the ItemsControl
    protected override void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        // Add a handler that catches Button clicks bubbling up from the DataTemplate
        AddHandler(Button.ClickEvent, OnButtonClick, RoutingStrategies.Bubble);
    }

    private void OnButtonClick(object? sender, RoutedEventArgs e)
    {
        if (e.Source is Button btn && btn.Tag is RomEntry rom && rom.Exists)
        {
            Vm?.UpdateLastPlayed(rom);
            FindMainView()?.LaunchGame(rom.Path, rom.Name);
        }
    }

    private MainView? FindMainView()
    {
        Avalonia.Visual? v = this;
        while (v != null)
        {
            if (v is MainView mv) return mv;
            v = v.GetVisualParent();
        }
        return null;
    }
}
