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
using Avalonia.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace NezAvalonia.ViewModels;

public partial class RecordingsViewModel : ObservableObject
{
    private static string GetRecordingsDir()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home))
            home = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(home))
            home = Path.GetTempPath();
        return Path.Combine(home, ".nes-zfa", "recordings");
    }

    public ObservableCollection<RecordingEntry> Recordings { get; } = new();

    [ObservableProperty]
    private RecordingEntry? _selectedRecording;

    [ObservableProperty]
    private bool _isPreviewOpen;

    public RecordingsViewModel()
    {
        LoadRecordings();
    }

    [RelayCommand]
    public void LoadRecordings()
    {
        Recordings.Clear();
        var dir = GetRecordingsDir();
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;

        var files = Directory.GetFiles(dir, "*.gif")
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
            if (SelectedRecording == entry)
            {
                SelectedRecording = null;
                IsPreviewOpen = false;
            }
        }
        catch
        {
            // Ignore delete errors
        }
    }

    [RelayCommand]
    private void OpenFolder(RecordingEntry entry)
    {
        var dir = Path.GetDirectoryName(entry.FilePath) ?? GetRecordingsDir();
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

    [RelayCommand]
    private void Preview(RecordingEntry entry)
    {
        SelectedRecording = entry;
        IsPreviewOpen = true;
    }

    [RelayCommand]
    private void ClosePreview()
    {
        IsPreviewOpen = false;
    }
}

public class RecordingEntry : ObservableObject
{
    public string FilePath { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public long SizeBytes { get; set; }

    /// <summary>
    /// Game name extracted from the file name.
    /// File naming convention: nez_{gameName}_{timestamp}.gif
    /// Falls back to file name if pattern doesn't match (old format: nez_{timestamp}.gif).
    /// </summary>
    public string GameName
    {
        get
        {
            var name = Path.GetFileNameWithoutExtension(FileName);
            if (name.StartsWith("nez_"))
            {
                var rest = name.Substring(4);
                int lastUnderscore = rest.LastIndexOf('_');
                if (lastUnderscore > 0)
                {
                    var afterUnderscore = rest.Substring(lastUnderscore + 1);
                    if (afterUnderscore.Length >= 13 && long.TryParse(afterUnderscore, out _))
                    {
                        var gamePart = rest.Substring(0, lastUnderscore);
                        if (!string.IsNullOrEmpty(gamePart))
                            return gamePart.Replace('_', ' ');
                    }
                }
            }
            return Path.GetFileNameWithoutExtension(FileName);
        }
    }

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

    private Bitmap? _thumbnail;
    public Bitmap? Thumbnail
    {
        get
        {
            if (_thumbnail != null) return _thumbnail;
            try
            {
                if (File.Exists(FilePath))
                    _thumbnail = new Bitmap(FilePath);
            }
            catch { }
            return _thumbnail;
        }
    }
}
