using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NezAvalonia.Core;

namespace NezAvalonia.ViewModels;

public partial class LibraryViewModel : ObservableObject
{
    private static string GetSavePath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Path.GetTempPath();
        return Path.Combine(appData, "NezAvalonia", "rom_library.json");
    }

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    public ObservableCollection<RomEntry> Roms { get; } = new();
    public ObservableCollection<RomEntry> FilteredRoms { get; } = new();

    public LibraryViewModel()
    {
        LoadSavedRoms();
        _ = LoadBundledRoms();
    }

    partial void OnSearchQueryChanged(string value)
    {
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        FilteredRoms.Clear();
        var query = SearchQuery.Trim().ToLowerInvariant();
        foreach (var rom in Roms)
        {
            if (string.IsNullOrEmpty(query) || rom.Name.Contains(query, StringComparison.OrdinalIgnoreCase))
            {
                FilteredRoms.Add(rom);
            }
        }
    }

    public void AddRom(string filePath)
    {
        if (!filePath.EndsWith(".nes", StringComparison.OrdinalIgnoreCase))
            return;

        // Check for duplicate
        if (Roms.Any(r => r.Path == filePath))
            return;

        var fi = new FileInfo(filePath);
        var entry = new RomEntry
        {
            Name = Path.GetFileNameWithoutExtension(filePath),
            Path = filePath,
            SizeKB = (int)(fi.Length / 1024),
            Mapper = "Unknown",
            ColorIndex = Roms.Count % NezTheme.CardColors.Length,
            LastPlayed = DateTime.MinValue,
            Exists = fi.Exists
        };

        Roms.Add(entry);
        ApplyFilter();
        SaveRoms();
    }

    [RelayCommand]
    private void RemoveRom(RomEntry rom)
    {
        Roms.Remove(rom);
        FilteredRoms.Remove(rom);
        SaveRoms();
    }

    public void UpdateLastPlayed(RomEntry rom)
    {
        rom.LastPlayed = DateTime.Now;
        SaveRoms();
    }

    private void LoadSavedRoms()
    {
        try
        {
            if (!File.Exists(GetSavePath())) return;
            var json = File.ReadAllText(GetSavePath());
            var entries = JsonSerializer.Deserialize(json, RomJsonContext.Default.RomEntryArray);
            if (entries == null) return;

            foreach (var entry in entries)
            {
                entry.Exists = File.Exists(entry.Path);
                Roms.Add(entry);
            }
            ApplyFilter();
        }
        catch
        {
            // Ignore corrupted save
        }
    }

    private async Task LoadBundledRoms()
    {
        // Only auto-add bundled ROMs if library is empty (first launch)
        if (Roms.Count > 0) return;

        try
        {
            var paths = await Core.BundledRomManager.EnsureBundledRoms();
            var added = false;
            foreach (var path in paths)
            {
                if (Roms.Any(r => r.Path == path)) continue;
                AddRom(path);
                added = true;
            }
            if (added) SaveRoms();
        }
        catch
        {
            // Ignore bundled ROM errors
        }
    }

    private void SaveRoms()
    {
        try
        {
            var dir = Path.GetDirectoryName(GetSavePath())!;
            if (!Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            var json = JsonSerializer.Serialize(Roms.ToArray(), RomJsonContext.Default.RomEntryArray);
            File.WriteAllText(GetSavePath(), json);
        }
        catch
        {
            // Ignore save errors
        }
    }
}

public class RomEntry : ObservableObject
{
    public string Name { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public int SizeKB { get; set; }
    public string Mapper { get; set; } = "Unknown";
    public int ColorIndex { get; set; }
    public DateTime LastPlayed { get; set; }

    [JsonIgnore]
    public bool Exists { get; set; } = true;

    [JsonIgnore]
    public Color CardColor => NezTheme.CardColors[ColorIndex % NezTheme.CardColors.Length];

    [JsonIgnore]
    public string SizeText => Exists ? $"{SizeKB} KB" : "File missing";
}

// NativeAOT-compatible JSON source generator
[JsonSerializable(typeof(RomEntry[]))]
[JsonSourceGenerationOptions(WriteIndented = true)]
internal partial class RomJsonContext : JsonSerializerContext { }
