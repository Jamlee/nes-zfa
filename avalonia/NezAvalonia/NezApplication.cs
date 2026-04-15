using System;
using Android.App;
using Android.Runtime;
using Avalonia;
using Avalonia.Android;

namespace NezAvalonia;

[Application]
public class NezApplication : AvaloniaAndroidApplication<App>
{
    public NezApplication(IntPtr handle, JniHandleOwnership ownership)
        : base(handle, ownership)
    {
    }

    protected override AppBuilder CreateAppBuilder()
    {
        return AppBuilder.Configure<App>()
            .UseAndroid()
            .LogToTrace();
    }
}
