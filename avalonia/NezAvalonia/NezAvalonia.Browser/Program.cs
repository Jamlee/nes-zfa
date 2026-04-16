using System;
using System.Threading.Tasks;
using System.Runtime.Versioning;
using Avalonia;
using Avalonia.Browser;

[assembly: SupportedOSPlatform("browser")]

namespace NezAvalonia.Browser;

internal class Program
{
    static async Task Main(string[] args)
    {
        await BuildAvaloniaApp()
            .StartBrowserAppAsync("out");
    }

    static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>();
}
