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
    private static readonly string SavePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "NezAvalonia", "rom_library.json");

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    public ObservableCollection<RomEntry> Roms { get; } = new();
    public ObservableCollection<RomEntry> FilteredRoms { get; } = new();

    public LibraryViewModel()
    {
        LoadSavedRoms();
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
            if (!File.Exists(SavePath)) return;
            var json = File.ReadAllText(SavePath);
            var entries = JsonSerializer.Deserialize<RomEntry[]>(json);
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

    private void SaveRoms()
    {
        try
        {
            var dir = Path.GetDirectoryName(SavePath)!;
            if (!Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            var json = JsonSerializer.Serialize(Roms.ToArray(), new JsonSerializerOptions
            {
                WriteIndented = true
            });
            File.WriteAllText(SavePath, json);
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
