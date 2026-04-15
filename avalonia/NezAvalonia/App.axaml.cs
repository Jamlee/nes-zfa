using System;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using NezAvalonia.Views;

namespace NezAvalonia;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        // Prevent crash from unhandled exceptions
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            Console.Error.WriteLine($"NEZ FATAL: {args.ExceptionObject}");
        };

        try
        {
            if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            {
                desktop.MainWindow = new MainWindow();
            }
            else if (ApplicationLifetime is ISingleViewApplicationLifetime singleView)
            {
                var view = new MainView();
                singleView.MainView = view;
                // On Android (SingleView lifetime), switch to mobile layout
                if (view.DataContext is ViewModels.MainViewModel vm)
                    vm.IsDesktop = false;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"NEZ INIT ERROR: {ex}");
        }

        base.OnFrameworkInitializationCompleted();
    }
}
