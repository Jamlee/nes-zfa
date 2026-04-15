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
#else
        return new NezAudioPlayerMacOS();
#endif
    }
}
