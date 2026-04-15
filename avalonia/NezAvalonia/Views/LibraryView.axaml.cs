using System;
using System.Collections.Specialized;
using System.IO;
using System.Runtime.InteropServices;
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

        // Search box focus → change outer border color
        if (SearchBox != null && SearchBorder != null)
        {
            SearchBox.GotFocus += (_, _) =>
                SearchBorder.BorderBrush = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#6C5CE7"));
            SearchBox.LostFocus += (_, _) =>
                SearchBorder.BorderBrush = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#2A2A44"));
        }
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
            Title = "Select NES ROM(s)",
            AllowMultiple = true,
            FileTypeFilter =
            [
                new FilePickerFileType("NES ROMs") { Patterns = ["*.nes"] },
                new FilePickerFileType("All files") { Patterns = ["*"] }
            ]
        });

        foreach (var file in files)
        {
            try
            {
                var localPath = await CopyToLocalStorageIfNeeded(file);
                if (localPath != null && localPath.EndsWith(".nes", StringComparison.OrdinalIgnoreCase))
                {
                    Vm?.AddRom(localPath);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to import ROM: {ex}");
            }
        }
    }

    /// <summary>
    /// On Android, StorageProvider returns content:// URIs which can't be used as
    /// file paths. We copy the file to local app storage via streams.
    /// On desktop, we just return the local path directly.
    /// </summary>
    private static async System.Threading.Tasks.Task<string?> CopyToLocalStorageIfNeeded(IStorageFile file)
    {
        // On desktop (Windows/macOS/Linux), LocalPath works fine
        if (!IsAndroidRuntime())
        {
            return file.Path.LocalPath;
        }

        // On Android: copy the content:// stream to local app storage
        var fileName = file.Name;
        if (string.IsNullOrEmpty(fileName))
            fileName = $"rom_{Guid.NewGuid():N}.nes";

        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Path.GetTempPath();

        var romsDir = Path.Combine(appData, "NezAvalonia", "roms");
        if (!Directory.Exists(romsDir))
            Directory.CreateDirectory(romsDir);

        var destPath = Path.Combine(romsDir, fileName);

        // If file already exists with the same name, generate unique name
        if (File.Exists(destPath))
        {
            var baseName = Path.GetFileNameWithoutExtension(fileName);
            var ext = Path.GetExtension(fileName);
            destPath = Path.Combine(romsDir, $"{baseName}_{Guid.NewGuid():N}{ext}");
        }

        await using var sourceStream = await file.OpenReadAsync();
        await using var destStream = File.Create(destPath);
        await sourceStream.CopyToAsync(destStream);

        return destPath;
    }

    private static bool IsAndroidRuntime()
    {
#if ANDROID
        return true;
#else
        // Fallback detection: check if we're running on Android via OS description
        return RuntimeInformation.IsOSPlatform(OSPlatform.Create("ANDROID"));
#endif
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
