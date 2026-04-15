using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace NezAvalonia.ViewModels;

public partial class RecordingsViewModel : ObservableObject
{
    private static readonly string RecordingsDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".nes-zfa", "recordings");

    public ObservableCollection<RecordingEntry> Recordings { get; } = new();

    public RecordingsViewModel()
    {
        LoadRecordings();
    }

    [RelayCommand]
    public void LoadRecordings()
    {
        Recordings.Clear();
        if (!Directory.Exists(RecordingsDir)) return;

        var files = Directory.GetFiles(RecordingsDir, "*.gif")
            .Select(p => new FileInfo(p))
            .OrderByDescending(f => f.LastWriteTime);

        foreach (var fi in files)
        {
            Recordings.Add(new RecordingEntry
            {
                FilePath = fi.FullName,
                FileName = fi.Name,
                Date = fi.LastWriteTime,
                SizeBytes = fi.Length,
            });
        }
    }

    [RelayCommand]
    private void Delete(RecordingEntry entry)
    {
        try
        {
            File.Delete(entry.FilePath);
            Recordings.Remove(entry);
        }
        catch
        {
            // Ignore delete errors
        }
    }

    [RelayCommand]
    private void OpenFolder(RecordingEntry entry)
    {
        var dir = Path.GetDirectoryName(entry.FilePath) ?? RecordingsDir;
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                Process.Start("open", dir);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                Process.Start("explorer", dir);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                Process.Start("xdg-open", dir);
        }
        catch
        {
            // Ignore
        }
    }

    [RelayCommand]
    private async Task CopyPath(RecordingEntry entry)
    {
        try
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop
                && desktop.MainWindow is { } window)
            {
                var clipboard = TopLevel.GetTopLevel(window)?.Clipboard;
                if (clipboard != null)
                {
                    await clipboard.SetValueAsync(DataFormat.Text, entry.FilePath);
                }
            }
        }
        catch
        {
            // Ignore
        }
    }
}

public class RecordingEntry : ObservableObject
{
    public string FilePath { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public long SizeBytes { get; set; }

    public string SizeText
    {
        get
        {
            if (SizeBytes < 1024) return $"{SizeBytes} B";
            if (SizeBytes < 1024 * 1024) return $"{SizeBytes / 1024.0:F1} KB";
            return $"{SizeBytes / (1024.0 * 1024.0):F1} MB";
        }
    }

    public string DateText => Date.ToString("yyyy-MM-dd HH:mm");
}
