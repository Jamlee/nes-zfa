using Avalonia;
using SixLabors.ImageSharp;
using System;
using System.Runtime;

namespace NezAvalonia;

class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Aggressive memory optimization
        GCSettings.LatencyMode = GCLatencyMode.Batch;
        AppContext.SetSwitch("System.Runtime.TieredCompilation.QuickJit", true);

        // Compact heap on startup
        GC.Collect(2, GCCollectionMode.Aggressive, true, true);
        GC.WaitForPendingFinalizers();

        // Limit ImageSharp memory
        Configuration.Default.MemoryAllocator = new SixLabors.ImageSharp.Memory.SimpleGcMemoryAllocator();

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .LogToTrace();
}
