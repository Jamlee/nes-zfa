using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace NezAvalonia.Core;

/// <summary>
/// Web-specific NES emulator engine that uses WASM interop instead of P/Invoke.
/// Runs on Avalonia Browser (Blazor WebAssembly).
/// The Zig emulator is compiled to .wasm and accessed through JS interop.
/// </summary>
public sealed class NezWasmEngine : INezEngine
{
    private WriteableBitmap? _frameBitmap;
    private bool _isLoaded;
    private volatile bool _isRunning;
    private string? _loadError;

    // Emulation loop (uses DispatcherTimer on web — no dedicated thread in WASM)
    private DispatcherTimer? _emuTimer;

    // FPS
    private volatile int _fps;
    private int _frameCount;
    private DateTime _lastFpsUpdate = DateTime.Now;

    // Turbo
    private volatile bool _turboA;
    private volatile bool _turboB;

    // Button state
    private volatile byte _buttonState;
    private volatile byte _buttonStateP2;

    // Double-buffer
    private byte[]? _backBuffer;

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? FrameReady;

    public WriteableBitmap? FrameBitmap => _frameBitmap;
    public bool IsLoaded => _isLoaded;
    public bool IsRunning => _isRunning;
    public string? LoadError => _loadError;
    public int Fps => _fps;
    public bool IsRecording => false;
    public bool IsPaused => false; // TODO: WASM pause
    public ushort CpuPc => 0; // TODO: WASM CPU debug

    public int ScreenWidth => 256;
    public int ScreenHeight => 240;

    public bool LoadRom(string romPath)
    {
        // On WASM, file paths don't work. Use LoadRomFromBytes instead.
        return false;
    }

    public bool LoadRomFromBytes(byte[] romData)
    {
        try
        {
            // Call into JS: NezWasm.loadRom(romData)
            var result = NezJsInterop.LoadRom(romData);
            if (!result)
            {
                _loadError = "Failed to load ROM into WASM";
                OnPropertyChanged(nameof(LoadError));
                return false;
            }

            int w = ScreenWidth, h = ScreenHeight;
            _frameBitmap = new WriteableBitmap(
                new PixelSize(w, h),
                new Vector(96, 96),
                PixelFormat.Bgra8888,
                AlphaFormat.Opaque);
            _backBuffer = new byte[w * h * 4];

            _isLoaded = true;
            _loadError = null;
            OnPropertyChanged(nameof(IsLoaded));
            OnPropertyChanged(nameof(LoadError));
            return true;
        }
        catch (Exception ex)
        {
            _loadError = ex.Message;
            OnPropertyChanged(nameof(LoadError));
            return false;
        }
    }

    public void StartLoop()
    {
        if (!_isLoaded || _isRunning) return;
        _isRunning = true;

        _emuTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(16), DispatcherPriority.Send, OnTick);
        _emuTimer.Start();

        OnPropertyChanged(nameof(IsRunning));
    }

    public void StopLoop()
    {
        _isRunning = false;
        _emuTimer?.Stop();
        _emuTimer = null;
        OnPropertyChanged(nameof(IsRunning));
    }

    private void OnTick(object? sender, EventArgs e)
    {
        if (!_isRunning || !_isLoaded) return;

        // Turbo
        _frameCount++;
        bool turboPhase = (_frameCount % 4) < 2;
        byte buttons = _buttonState;
        if (_turboA)
        {
            if (turboPhase) buttons |= (1 << NezBindings.ButtonA);
            else buttons &= unchecked((byte)~(1 << NezBindings.ButtonA));
        }
        if (_turboB)
        {
            if (turboPhase) buttons |= (1 << NezBindings.ButtonB);
            else buttons &= unchecked((byte)~(1 << NezBindings.ButtonB));
        }

        // Set input
        NezJsInterop.SetButtons(buttons);

        // Run emulation
        NezJsInterop.Update(16);

        // Convert framebuffer
        ConvertFrameBuffer();

        // FPS
        var now = DateTime.Now;
        if ((now - _lastFpsUpdate).TotalMilliseconds >= 1000)
        {
            _fps = _frameCount;
            _frameCount = 0;
            _lastFpsUpdate = now;
        }

        // Flush frame to bitmap
        FlushFrame();
    }

    private void ConvertFrameBuffer()
    {
        if (_backBuffer == null) return;

        var fb = NezJsInterop.GetFrameBuffer();
        if (fb == null) return;

        int pixelCount = ScreenWidth * ScreenHeight;
        for (int i = 0; i < pixelCount; i++)
        {
            int si = i * 3;
            int di = i * 4;
            _backBuffer[di + 0] = fb[si + 2]; // B
            _backBuffer[di + 1] = fb[si + 1]; // G
            _backBuffer[di + 2] = fb[si + 0]; // R
            _backBuffer[di + 3] = 255;         // A
        }
    }

    private void FlushFrame()
    {
        if (_frameBitmap == null || _backBuffer == null) return;

        unsafe
        {
            using var locked = _frameBitmap.Lock();
            fixed (byte* src = _backBuffer)
            {
                Buffer.MemoryCopy(src, (void*)locked.Address, _backBuffer.Length, _backBuffer.Length);
            }
        }

        FrameReady?.Invoke();
    }

    public void SetSoundEnabled(bool enabled) { /* WASM: no native audio control */ }
    public void SetVolume(double volume) { /* WASM: no native audio control */ }

    public void SetButton(int button, bool pressed)
    {
        if (pressed) _buttonState |= (byte)(1 << button);
        else _buttonState &= unchecked((byte)~(1 << button));
    }

    public void SetButtonP2(int button, bool pressed)
    {
        if (pressed) _buttonStateP2 |= (byte)(1 << button);
        else _buttonStateP2 &= unchecked((byte)~(1 << button));
    }

    public byte[]? GetBackBuffer()
    {
        var buf = _backBuffer;
        if (buf == null) return null;
        var copy = new byte[buf.Length];
        Buffer.BlockCopy(buf, 0, copy, 0, buf.Length);
        return copy;
    }

    public void SetTurboA(bool active) => _turboA = active;
    public void SetTurboB(bool active) => _turboB = active;

    public void TogglePause()
    {
        // TODO: WASM pause
    }

    public void StartRecording(string romName) { /* GIF recording not supported on web */ }

    public Task<string?> StopRecording() => Task.FromResult<string?>(null); // GIF recording not supported on web

    private void OnPropertyChanged(string name) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public void Dispose()
    {
        StopLoop();
        _frameBitmap?.Dispose();
        _frameBitmap = null;
        _backBuffer = null;
    }
}

/// <summary>
/// JavaScript interop for calling the NezWasm bridge from C# on WASM.
/// </summary>
internal static class NezJsInterop
{
    [DllImport("__Internal", EntryPoint = "nez_js_load_rom")]
    private static extern int NezJsLoadRom(byte[] data, int length);

    [DllImport("__Internal", EntryPoint = "nez_js_update")]
    private static extern void NezJsUpdate(int dtMs);

    [DllImport("__Internal", EntryPoint = "nez_js_set_buttons")]
    private static extern void NezJsSetButtons(int bitmask);

    [DllImport("__Internal", EntryPoint = "nez_js_set_pause")]
    private static extern void NezJsSetPause(int paused);

    [DllImport("__Internal", EntryPoint = "nez_js_get_framebuffer")]
    private static extern int NezJsGetFramebuffer();

    public static bool LoadRom(byte[] romData)
    {
        // On WASM, use JS interop
        try
        {
            return NezJsLoadRom(romData, romData.Length) != 0;
        }
        catch
        {
            return false;
        }
    }

    public static void Update(int dtMs) => NezJsUpdate(dtMs);
    public static void SetButtons(int bitmask) => NezJsSetButtons(bitmask);
    public static void SetPause(bool paused) => NezJsSetPause(paused ? 1 : 0);

    public static byte[]? GetFrameBuffer()
    {
        try
        {
            int ptr = NezJsGetFramebuffer();
            if (ptr == 0) return null;
            int size = 256 * 240 * 3;
            var result = new byte[size];
            Marshal.Copy((IntPtr)ptr, result, 0, size);
            return result;
        }
        catch
        {
            return null;
        }
    }
}
