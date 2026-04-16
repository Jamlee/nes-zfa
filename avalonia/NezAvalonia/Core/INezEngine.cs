using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;

namespace NezAvalonia.Core;

/// <summary>
/// Common interface for NES emulator engines (native P/Invoke and WASM).
/// </summary>
public interface INezEngine : INotifyPropertyChanged, IDisposable
{
    WriteableBitmap? FrameBitmap { get; }
    bool IsLoaded { get; }
    bool IsRunning { get; }
    string? LoadError { get; }
    int Fps { get; }
    bool IsRecording { get; }
    bool IsPaused { get; }
    ushort CpuPc { get; }
    int ScreenWidth { get; }
    int ScreenHeight { get; }

    event Action? FrameReady;

    bool LoadRom(string romPath);
    void StartLoop();
    void StopLoop();
    void SetSoundEnabled(bool enabled);
    void SetVolume(double volume);
    void SetButton(int button, bool pressed);
    void SetButtonP2(int button, bool pressed);
    void SetTurboA(bool active);
    void SetTurboB(bool active);
    void TogglePause();
    void StartRecording(string romName);
    Task<string?> StopRecording();
    byte[]? GetBackBuffer();
}
