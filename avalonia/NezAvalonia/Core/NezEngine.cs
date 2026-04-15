using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Gif;
using SixLabors.ImageSharp.PixelFormats;

namespace NezAvalonia.Core;

/// <summary>
/// High-level NES emulator engine wrapper.
/// Uses a dedicated high-precision thread for emulation + audio (not DispatcherTimer).
/// UI thread only reads the framebuffer for rendering.
/// </summary>
public sealed class NezEngine : INotifyPropertyChanged, IDisposable
{
    private IntPtr _console;
    private WriteableBitmap? _frameBitmap;
    private bool _isLoaded;
    private volatile bool _isRunning;
    private string? _loadError;

    // Emulation thread
    private Thread? _emuThread;

    // FPS
    private volatile int _fps;

    // Turbo
    private volatile bool _turboA;
    private volatile bool _turboB;

    // Button state
    private volatile byte _buttonState;

    // Audio
    private INezAudioPlayer? _audioPlayer;
    private IntPtr _audioBuffer;
    private const int AudioBufferSize = 2048;

    // Double-buffer: emu thread writes to _backBuffer, then swaps pointer
    private byte[]? _backBuffer; // BGRA32 pixel data
    private volatile bool _frameReady;

    // GIF recording
    private volatile bool _recording;
    private readonly List<byte[]> _recordedFrames = new();
    private const int MaxRecordFrames = 300; // ~5 seconds
    private int _recordFrameCounter;

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? FrameReady;

    public WriteableBitmap? FrameBitmap => _frameBitmap;
    public bool IsLoaded => _isLoaded;
    public bool IsRunning => _isRunning;
    public string? LoadError => _loadError;
    public int Fps => _fps;
    public bool IsRecording => _recording;

    public int ScreenWidth => (int)NezBindings.ScreenWidth();
    public int ScreenHeight => (int)NezBindings.ScreenHeight();

    public bool IsPaused => _console != IntPtr.Zero && NezBindings.IsPaused(_console);
    public ushort CpuPc => _console != IntPtr.Zero ? NezBindings.CpuGetPc(_console) : (ushort)0;

    public bool LoadRom(string romPath)
    {
        try
        {
            if (_console != IntPtr.Zero)
            {
                NezBindings.Destroy(_console);
                _console = IntPtr.Zero;
            }

            _console = NezBindings.Create(romPath);
            if (_console == IntPtr.Zero)
            {
                _loadError = $"Failed to create/load ROM: {romPath}";
                OnPropertyChanged(nameof(LoadError));
                return false;
            }

            int w = ScreenWidth;
            int h = ScreenHeight;
            _frameBitmap = new WriteableBitmap(
                new PixelSize(w, h),
                new Vector(96, 96),
                Avalonia.Platform.PixelFormat.Bgra8888,
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

        // Start audio
        _audioPlayer = NezAudioFactory.Create();
        _audioPlayer.Start();
        _audioBuffer = Marshal.AllocHGlobal(AudioBufferSize * 2);

        // Start dedicated emulation thread
        _emuThread = new Thread(EmulationLoop)
        {
            Name = "NezEmulation",
            IsBackground = true,
            Priority = ThreadPriority.AboveNormal,
        };
        _emuThread.Start();

        OnPropertyChanged(nameof(IsRunning));
    }

    public void StopLoop()
    {
        _isRunning = false;
        _emuThread?.Join(500);
        _emuThread = null;

        _audioPlayer?.Stop();
        _audioPlayer?.Dispose();
        _audioPlayer = null;
        if (_audioBuffer != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_audioBuffer);
            _audioBuffer = IntPtr.Zero;
        }

        OnPropertyChanged(nameof(IsRunning));
    }

    /// <summary>
    /// High-precision emulation loop running on dedicated thread.
    /// Targets exactly 60 FPS (16.6667ms per frame) using Stopwatch spin-wait.
    /// </summary>
    private void EmulationLoop()
    {
        const double TargetFrameTimeMs = 1000.0 / 60.0; // 16.6667ms
        var sw = Stopwatch.StartNew();
        double nextFrameMs = sw.Elapsed.TotalMilliseconds;
        int frameCount = 0;
        double fpsTimer = nextFrameMs;
        int turboCounter = 0;

        while (_isRunning)
        {
            double now = sw.Elapsed.TotalMilliseconds;

            // Wait until it's time for the next frame
            if (now < nextFrameMs)
            {
                double sleepMs = nextFrameMs - now;
                // Sleep for most of the wait, then spin for precision
                if (sleepMs > 2.0)
                    Thread.Sleep((int)(sleepMs - 1.0));
                // Spin-wait for sub-millisecond precision
                while (sw.Elapsed.TotalMilliseconds < nextFrameMs)
                    Thread.SpinWait(10);
            }
            nextFrameMs += TargetFrameTimeMs;

            if (_console == IntPtr.Zero) continue;

            // Turbo
            turboCounter++;
            bool turboPhase = (turboCounter % 4) < 2;
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
            NezBindings.InputSetButtons(_console, buttons);

            // Run emulation
            NezBindings.Update(_console, 16);

            // Convert framebuffer to BGRA32 in back buffer
            ConvertFramebuffer();

            // Drain audio
            DrainAudio();

            // FPS counting
            frameCount++;
            now = sw.Elapsed.TotalMilliseconds;
            if (now - fpsTimer >= 1000.0)
            {
                _fps = frameCount;
                frameCount = 0;
                fpsTimer = now;
            }

            // Signal UI thread to copy back buffer → WriteableBitmap and repaint
            _frameReady = true;
            Dispatcher.UIThread.Post(FlushFrame, DispatcherPriority.Send);
        }
    }

    /// <summary>
    /// Called on UI thread: copy back buffer into WriteableBitmap and notify view.
    /// </summary>
    private void FlushFrame()
    {
        if (!_frameReady || _frameBitmap == null || _backBuffer == null) return;
        _frameReady = false;

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

    /// <summary>
    /// Convert RGB24 framebuffer → BGRA32 back buffer (runs on emu thread).
    /// </summary>
    private unsafe void ConvertFramebuffer()
    {
        if (_backBuffer == null || _console == IntPtr.Zero) return;

        IntPtr fbPtr = NezBindings.FramebufferGet(_console);
        if (fbPtr == IntPtr.Zero) return;

        int pixelCount = ScreenWidth * ScreenHeight;
        byte* src = (byte*)fbPtr;

        fixed (byte* dst = _backBuffer)
        {
            for (int i = 0; i < pixelCount; i++)
            {
                int si = i * 3;
                int di = i * 4;
                dst[di + 0] = src[si + 2]; // B
                dst[di + 1] = src[si + 1]; // G
                dst[di + 2] = src[si + 0]; // R
                dst[di + 3] = 255;         // A
            }
        }

        // Capture frame for GIF recording (every other frame)
        if (_recording && _recordedFrames.Count < MaxRecordFrames)
        {
            _recordFrameCounter++;
            if (_recordFrameCounter % 2 == 0)
            {
                var copy = new byte[_backBuffer.Length];
                Buffer.BlockCopy(_backBuffer, 0, copy, 0, _backBuffer.Length);
                lock (_recordedFrames) { _recordedFrames.Add(copy); }
            }
        }
    }

    private void DrainAudio()
    {
        if (_audioPlayer == null || _console == IntPtr.Zero || _audioBuffer == IntPtr.Zero) return;
        uint count = NezBindings.AudioQueueDrain(_console, _audioBuffer, AudioBufferSize);
        if (count > 0)
            _audioPlayer.PushSamples(_audioBuffer, (int)count);
    }

    public void SetButton(int button, bool pressed)
    {
        if (pressed)
            _buttonState |= (byte)(1 << button);
        else
            _buttonState &= unchecked((byte)~(1 << button));
    }

    public void SetTurboA(bool active) => _turboA = active;
    public void SetTurboB(bool active) => _turboB = active;

    public void TogglePause()
    {
        if (_console == IntPtr.Zero) return;
        NezBindings.SetPause(_console, !NezBindings.IsPaused(_console));
        OnPropertyChanged(nameof(IsPaused));
    }

    private void OnPropertyChanged(string name)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    // ---- GIF Recording ----

    public void StartRecording()
    {
        lock (_recordedFrames) { _recordedFrames.Clear(); }
        _recordFrameCounter = 0;
        _recording = true;
        OnPropertyChanged(nameof(IsRecording));
    }

    public async Task<string?> StopRecording()
    {
        _recording = false;
        OnPropertyChanged(nameof(IsRecording));

        List<byte[]> frames;
        lock (_recordedFrames)
        {
            frames = new List<byte[]>(_recordedFrames);
            _recordedFrames.Clear();
        }
        if (frames.Count == 0) return null;

        int w = ScreenWidth, h = ScreenHeight;
        return await Task.Run(() => EncodeGif(w, h, frames));
    }

    private static string? EncodeGif(int w, int h, List<byte[]> frames)
    {
        try
        {
            using var gif = new Image<Bgra32>(w, h);
            gif.Frames.RemoveFrame(0);

            foreach (var bgra in frames)
            {
                using var frame = SixLabors.ImageSharp.Image.LoadPixelData<Bgra32>(bgra, w, h);
                var meta = frame.Frames.RootFrame.Metadata.GetGifMetadata();
                meta.FrameDelay = 3; // ~30fps
                gif.Frames.AddFrame(frame.Frames.RootFrame);
            }

            gif.Metadata.GetGifMetadata().RepeatCount = 0;

            var recordingsDir = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".nes-zfa", "recordings");
            Directory.CreateDirectory(recordingsDir);

            var path = System.IO.Path.Combine(recordingsDir, $"nez_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}.gif");
            gif.SaveAsGif(path);
            return path;
        }
        catch
        {
            return null;
        }
    }

    public void Dispose()
    {
        StopLoop();
        if (_console != IntPtr.Zero)
        {
            NezBindings.Destroy(_console);
            _console = IntPtr.Zero;
        }
        _frameBitmap?.Dispose();
        _frameBitmap = null;
        _backBuffer = null;
    }
}
