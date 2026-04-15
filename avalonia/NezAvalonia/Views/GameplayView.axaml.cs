using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using NezAvalonia.ViewModels;

namespace NezAvalonia.Views;

public partial class GameplayView : UserControl
{
    private bool _displayInitialized;
    private bool _invalidatePending;

    public GameplayView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private GameplayViewModel? Vm => DataContext as GameplayViewModel;

    private void OnDataContextChanged(object? sender, System.EventArgs e)
    {
        _displayInitialized = false;
        _invalidatePending = false;

        if (Vm == null) return;

        Vm.Engine.FrameReady += OnFrameReady;

        // Set focus for keyboard input
        Focus();
    }

    private void OnFrameReady()
    {
        if (Vm == null || Display == null) return;

        // Set the bitmap reference once (pixels update in-place via Lock/Unlock)
        if (!_displayInitialized && Vm.Engine.FrameBitmap != null)
        {
            Display.SetBitmap(Vm.Engine.FrameBitmap);
            _displayInitialized = true;
        }

        Display.SetFps(Vm.Engine.Fps);

        // Defer InvalidateVisual to avoid "invalidated during render pass" crash.
        // Coalesce multiple frames — only one Post at a time.
        if (!_invalidatePending)
        {
            _invalidatePending = true;
            Dispatcher.UIThread.Post(() =>
            {
                _invalidatePending = false;
                Display?.InvalidateVisual();

                // Update debug info
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
            Vm.Engine.FrameReady -= OnFrameReady;

        var mainWindow = TopLevel.GetTopLevel(this) as MainWindow;
        mainWindow?.ExitGameplay();
    }

    private void OnTogglePause(object? sender, RoutedEventArgs e)
    {
        Vm?.TogglePauseCommand.Execute(null);
        Focus();
    }

    private void OnToggleDebug(object? sender, RoutedEventArgs e)
    {
        Vm?.ToggleDebugCommand.Execute(null);
        Focus();
    }
}
