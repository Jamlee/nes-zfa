using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Avalonia.VisualTree;
using NezAvalonia.Controls;
using NezAvalonia.Core;
using NezAvalonia.ViewModels;
#if !BROWSER
using QRCoder;
#endif
using System;
using System.IO;

namespace NezAvalonia.Views;

public partial class GameplayView : UserControl
{
    private bool _displayInitialized;
    private bool _invalidatePending;
    private bool _isLandscape;

    public GameplayView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        SizeChanged += OnSizeChanged;
    }

    private GameplayViewModel? Vm => DataContext as GameplayViewModel;

    private void OnDataContextChanged(object? sender, System.EventArgs e)
    {
        _displayInitialized = false;
        _invalidatePending = false;

        if (Vm == null) return;

        // Wire engine to the global gamepad server
#if !BROWSER
        var main = FindMainView();
        if (main?.DataContext is MainViewModel mvm && mvm.GamepadServerInstance != null)
            mvm.GamepadServerInstance.SetEngine(Vm.Engine);
#endif

        Vm.Engine.FrameReady += OnFrameReady;

        // Set landscape gamepad modes
        if (LandscapeGamepad != null) LandscapeGamepad.Mode = GamepadMode.JoystickOnly;
        if (LandscapeButtons != null) LandscapeButtons.Mode = GamepadMode.ButtonsOnly;

        // Wire all gamepads
        WireGamepad(MobileGamepad);
        WireGamepad(LandscapeGamepad);
        WireGamepad(LandscapeButtons);

        // Wire SEL/START buttons (portrait + landscape)
        WireSelStart(MobileSel, MobileStart);
        WireSelStart(LandscapeSel, LandscapeStart);

        // Apply display settings
        ApplyDisplaySettings();
        ApplyControlSettings();

        // Subscribe to settings changes for live updates
        Vm.Settings.PropertyChanged += OnSettingsChanged;

        // Initial layout
        UpdateMobileLayout();

        Focus();
    }

    private void OnSettingsChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(Vm.Settings.AspectRatio):
            case nameof(Vm.Settings.PixelFilter):
            case nameof(Vm.Settings.ShowFps):
                ApplyDisplaySettings();
                break;
            case nameof(Vm.Settings.ButtonSize):
            case nameof(Vm.Settings.ButtonOpacity):
                ApplyControlSettings();
                break;
        }
    }

    private void ApplyDisplaySettings()
    {
        if (Vm == null) return;
        var settings = Vm.Settings;

        // Apply to all display instances
        Display?.SetShowFps(settings.ShowFps);
        Display?.SetAspectRatio(settings.AspectRatio);
        Display?.SetPixelFilter(settings.PixelFilter);

        MobileDisplay?.SetShowFps(settings.ShowFps);
        MobileDisplay?.SetAspectRatio(settings.AspectRatio);
        MobileDisplay?.SetPixelFilter(settings.PixelFilter);

        LandscapeDisplay?.SetShowFps(settings.ShowFps);
        LandscapeDisplay?.SetAspectRatio(settings.AspectRatio);
        LandscapeDisplay?.SetPixelFilter(settings.PixelFilter);
    }

    private void ApplyControlSettings()
    {
        if (Vm == null) return;
        var settings = Vm.Settings;

        MobileGamepad?.SetButtonSize(settings.ButtonSize);
        MobileGamepad?.SetButtonOpacity(settings.ButtonOpacity);

        LandscapeGamepad?.SetButtonSize(settings.ButtonSize);
        LandscapeGamepad?.SetButtonOpacity(settings.ButtonOpacity);

        LandscapeButtons?.SetButtonSize(settings.ButtonSize);
        LandscapeButtons?.SetButtonOpacity(settings.ButtonOpacity);
    }

    private void WireGamepad(VirtualGamepad? gp)
    {
        if (gp == null || Vm == null) return;
        gp.ButtonChanged += (btn, pressed) => Vm.Engine.SetButton(btn, pressed);
        gp.TurboAChanged += (active) => Vm.Engine.SetTurboA(active);
        gp.TurboBChanged += (active) => Vm.Engine.SetTurboB(active);
    }

    private void WireSelStart(Button? sel, Button? start)
    {
        if (Vm == null) return;
        if (sel != null)
        {
            sel.AddHandler(InputElement.PointerPressedEvent,
                (object? s, PointerPressedEventArgs a) => { Vm.Engine.SetButton(NezBindings.ButtonSelect, true); a.Handled = true; },
                RoutingStrategies.Tunnel);
            sel.AddHandler(InputElement.PointerReleasedEvent,
                (object? s, PointerReleasedEventArgs a) => { Vm.Engine.SetButton(NezBindings.ButtonSelect, false); },
                RoutingStrategies.Tunnel);
        }
        if (start != null)
        {
            start.AddHandler(InputElement.PointerPressedEvent,
                (object? s, PointerPressedEventArgs a) => { Vm.Engine.SetButton(NezBindings.ButtonStart, true); a.Handled = true; },
                RoutingStrategies.Tunnel);
            start.AddHandler(InputElement.PointerReleasedEvent,
                (object? s, PointerReleasedEventArgs a) => { Vm.Engine.SetButton(NezBindings.ButtonStart, false); },
                RoutingStrategies.Tunnel);
        }
    }

    private void OnSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (Vm?.IsDesktop != false) return;
        UpdateMobileLayout();
    }

    private void UpdateMobileLayout()
    {
        if (Vm?.IsDesktop != false) return;

        bool landscape = Bounds.Width > Bounds.Height;
        _isLandscape = landscape;

        if (MobilePortrait != null) MobilePortrait.IsVisible = !landscape;
        if (MobileLandscape != null) MobileLandscape.IsVisible = landscape;
    }

    private void OnFrameReady()
    {
        try
        {
            if (Vm == null) return;

            if (!_displayInitialized && Vm.Engine.FrameBitmap != null)
            {
                Display?.SetBitmap(Vm.Engine.FrameBitmap);
                MobileDisplay?.SetBitmap(Vm.Engine.FrameBitmap);
                LandscapeDisplay?.SetBitmap(Vm.Engine.FrameBitmap);
                _displayInitialized = true;
            }

            Display?.SetFps(Vm.Engine.Fps);
            MobileDisplay?.SetFps(Vm.Engine.Fps);
            LandscapeDisplay?.SetFps(Vm.Engine.Fps);

            if (!_invalidatePending)
            {
                _invalidatePending = true;
                Dispatcher.UIThread.Post(() =>
                {
                    _invalidatePending = false;
                    Display?.InvalidateVisual();
                    MobileDisplay?.InvalidateVisual();
                    LandscapeDisplay?.InvalidateVisual();

                    if (Vm?.ShowDebugPanel == true)
                    {
                        if (DebugPC != null)
                            DebugPC.Text = $"PC: ${Vm.Engine.CpuPc:X4}";
                        if (DebugPaused != null)
                            DebugPaused.Text = $"Paused: {(Vm.Engine.IsPaused ? "YES" : "NO")}";
                        if (DebugFps != null)
                            DebugFps.Text = $"FPS: {Vm.Engine.Fps}";
                    }
                }, DispatcherPriority.Input);
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"NEZ OnFrameReady suppressed: {ex.GetType().Name}: {ex.Message}");
        }
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (Vm?.HandleKeyDown(e.Key, e.KeyModifiers) == true)
        {
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape)
        {
            OnBack(null, e);
            e.Handled = true;
            return;
        }

        base.OnKeyDown(e);
    }

    protected override void OnKeyUp(KeyEventArgs e)
    {
        if (Vm?.HandleKeyUp(e.Key) == true)
        {
            e.Handled = true;
            return;
        }
        base.OnKeyUp(e);
    }

    private void OnBack(object? sender, RoutedEventArgs e)
    {
        if (Vm != null)
        {
            Vm.Engine.FrameReady -= OnFrameReady;
            Vm.Settings.PropertyChanged -= OnSettingsChanged;
        }

        FindMainView()?.ExitGameplay();
    }

    private MainView? FindMainView()
    {
        Avalonia.Visual? v = this;
        while (v != null)
        {
            if (v is MainView mv) return mv;
            v = v.GetVisualParent();
        }
        return null;
    }

    private void OnTogglePause(object? sender, RoutedEventArgs e)
    {
        Vm?.TogglePauseCommand.Execute(null);
        Focus();
    }

    private void OnToggleRecord(object? sender, RoutedEventArgs e)
    {
        Vm?.ToggleRecordCommand.Execute(null);
        Focus();
    }

    private void OnToggleDebug(object? sender, RoutedEventArgs e)
    {
        Vm?.ToggleDebugCommand.Execute(null);
        Focus();
    }

    private void OnFitWindow(object? sender, RoutedEventArgs e)
    {
        var window = this.FindAncestorOfType<Window>();
        if (window == null) return;

        const double nesAspect = 256.0 / 240.0;
        const double chromeHeight = 80.0;
        var currentWidth = window.Width;
        var nesHeight = currentWidth / nesAspect;
        window.Height = nesHeight + chromeHeight;
        Focus();
    }

#if !BROWSER
    private void OnControllers(object? sender, RoutedEventArgs e)
    {
        if (Vm == null) return;
        var main = FindMainView();
        var mvm = main?.DataContext as MainViewModel;
        if (mvm == null) return;

        // Use the global gamepad server instance
        try
        {
            if (mvm.GamepadServerInstance == null)
            {
                mvm.GamepadServerInstance = new GamepadServer(Vm.Engine);
                mvm.GamepadServerInstance.Start();
            }
            else
            {
                mvm.GamepadServerInstance.SetEngine(Vm.Engine);
            }

            var gs = mvm.GamepadServerInstance;
            var ip = GamepadServer.GetLocalIp() ?? "0.0.0.0";
            var port = gs.Port;
            var urlP1 = $"http://{ip}:{port}/?player=1&mirror=true";
            var urlP2 = $"http://{ip}:{port}/?player=2&mirror=true";

            if (QrImageP1 != null) QrImageP1.Source = GenerateQrBitmap(urlP1);
            if (QrImageP2 != null) QrImageP2.Source = GenerateQrBitmap(urlP2);
            if (QrUrlP1 != null) QrUrlP1.Text = urlP1;
            if (QrUrlP2 != null) QrUrlP2.Text = urlP2;

            if (QrOverlay != null) QrOverlay.IsVisible = true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"NEZ: OnControllers error: {ex}");
        }
        Focus();
    }

    private void OnCloseQrOverlay(object? sender, RoutedEventArgs e)
    {
        if (QrOverlay != null) QrOverlay.IsVisible = false;
        Focus();
    }

    private static Bitmap? GenerateQrBitmap(string url)
    {
        try
        {
            using var qrGenerator = new QRCodeGenerator();
            using var qrCodeData = qrGenerator.CreateQrCode(url, QRCodeGenerator.ECCLevel.M);
            using var qrCode = new PngByteQRCode(qrCodeData);
            var pngBytes = qrCode.GetGraphic(8);
            using var ms = new MemoryStream(pngBytes);
            return new Bitmap(ms);
        }
        catch
        {
            return null;
        }
    }
#else
    // Browser stubs — GamepadServer is not available
    private void OnControllers(object? sender, RoutedEventArgs e) { Focus(); }
    private void OnCloseQrOverlay(object? sender, RoutedEventArgs e) { Focus(); }
#endif
}
