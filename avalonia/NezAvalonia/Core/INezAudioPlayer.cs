using System;

namespace NezAvalonia.Core;

/// <summary>
/// Platform-agnostic audio player interface.
/// </summary>
public interface INezAudioPlayer : IDisposable
{
    bool Start();
    void Stop();
    unsafe void PushSamples(IntPtr samplesPtr, int count);
    void SetVolume(double volume);
}

/// <summary>
/// Factory to create the correct audio player for the current platform.
/// </summary>
public static class NezAudioFactory
{
    public static INezAudioPlayer Create()
    {
#if ANDROID
        return new NezAudioPlayerAndroid();
#elif BROWSER
        return new NezAudioPlayerDummy();
#else
        return new NezAudioPlayerMacOS();
#endif
    }
}

/// <summary>
/// Dummy audio player for browser (WASM) — no audio output.
/// </summary>
#if BROWSER
public class NezAudioPlayerDummy : INezAudioPlayer
{
    public bool Start() => true;
    public void Stop() { }
    public unsafe void PushSamples(IntPtr samplesPtr, int count) { }
    public void SetVolume(double volume) { }
    public void Dispose() { }
}
#endif
