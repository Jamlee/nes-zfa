using Android.App;
using Android.Content.PM;
using Avalonia.Android;

namespace NezAvalonia;

[Activity(
    Label = "NEZ-ZFA",
    Theme = "@style/MyTheme.NoActionBar",
    Icon = "@drawable/icon",
    MainLauncher = true,
    ConfigurationChanges = ConfigChanges.Orientation | ConfigChanges.ScreenSize | ConfigChanges.UiMode)]
public class MainActivity : AvaloniaMainActivity
{
    public override void OnBackPressed()
    {
        // If in gameplay, go back to library instead of exiting app
        if (Avalonia.Application.Current?.ApplicationLifetime is
            Avalonia.Controls.ApplicationLifetimes.ISingleViewApplicationLifetime singleView
            && singleView.MainView is Views.MainView mainView
            && mainView.DataContext is ViewModels.MainViewModel vm
            && vm.IsInGameplay)
        {
            mainView.ExitGameplay();
            return;
        }

        base.OnBackPressed();
    }
}
