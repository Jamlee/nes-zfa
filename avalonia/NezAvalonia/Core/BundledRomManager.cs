using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

namespace NezAvalonia.Core;

/// <summary>
/// Extracts bundled ROM files from embedded resources on first launch.
/// </summary>
public static class BundledRomManager
{
    /// <summary>
    /// Extract all embedded .nes resources to local storage.
    /// Returns list of extracted file paths.
    /// </summary>
    public static async Task<string[]> EnsureBundledRoms()
    {
        var destDir = GetRomsDir();
        Directory.CreateDirectory(destDir);

        var assembly = Assembly.GetExecutingAssembly();
        var resourceNames = assembly.GetManifestResourceNames()
            .Where(n => n.EndsWith(".nes", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        var paths = new System.Collections.Generic.List<string>();

        foreach (var resName in resourceNames)
        {
            // Resource name: NezAvalonia.roms.jackal.nes → jackal.nes
            var fileName = resName;
            var romsIdx = fileName.IndexOf(".roms.", StringComparison.Ordinal);
            if (romsIdx >= 0)
                fileName = fileName[(romsIdx + 6)..]; // skip "NezAvalonia.roms."

            var destPath = Path.Combine(destDir, fileName);

            if (!File.Exists(destPath))
            {
                try
                {
                    await using var stream = assembly.GetManifestResourceStream(resName);
                    if (stream == null) continue;

                    await using var fileStream = File.Create(destPath);
                    await stream.CopyToAsync(fileStream);
                }
                catch
                {
                    continue;
                }
            }

            if (File.Exists(destPath))
                paths.Add(destPath);
        }

        return paths.ToArray();
    }

    private static string GetRomsDir()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(appData))
            appData = Path.GetTempPath();

        return Path.Combine(appData, "NezAvalonia", "bundled_roms");
    }
}
