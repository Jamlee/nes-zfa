#if ANDROID
using System;
using System.Threading;
using Android.Media;

namespace NezAvalonia.Core;

/// <summary>
/// Audio player using Android AudioTrack.
/// PCM Int16 mono 44100 Hz — matches Flutter version.
/// </summary>
public sealed class NezAudioPlayerAndroid : INezAudioPlayer
{
    private const int SampleRate = 44100;
    private AudioTrack? _track;
    private bool _isRunning;
    private bool _disposed;

    // Ring buffer (Int16 — Android AudioTrack supports Int16 natively)
    private const int RingSize = 1 << 16;
    private const int RingMask = RingSize - 1;
    private readonly short[] _ring = new short[RingSize];
    private int _writeHead;
    private int _readHead;

    // Playback thread
    private Thread? _playThread;

    public bool Start()
    {
        if (_isRunning) return true;

        int bufSize = AudioTrack.GetMinBufferSize(SampleRate,
            ChannelOut.Mono, Encoding.Pcm16bit);
        if (bufSize <= 0) bufSize = 4096;

        _track = new AudioTrack.Builder()
            .SetAudioAttributes(new AudioAttributes.Builder()
                .SetUsage(AudioUsageKind.Game)!
                .SetContentType(AudioContentType.Music)!
                .Build()!)
            .SetAudioFormat(new AudioFormat.Builder()
                .SetSampleRate(SampleRate)!
                .SetChannelMask(ChannelOut.Mono)!
                .SetEncoding(Encoding.Pcm16bit)!
                .Build()!)
            .SetBufferSizeInBytes(bufSize * 2)
            .SetTransferMode(AudioTrackMode.Stream)
            .Build();

        _track.Play();
        _isRunning = true;

        _playThread = new Thread(PlayLoop)
        {
            Name = "NezAudioAndroid",
            IsBackground = true,
        };
        _playThread.Start();

        return true;
    }

    public void Stop()
    {
        if (!_isRunning) return;
        _isRunning = false;
        _playThread?.Join(500);
        _playThread = null;

        _track?.Stop();
        _track?.Release();
        _track?.Dispose();
        _track = null;
    }

    public unsafe void PushSamples(IntPtr samplesPtr, int count)
    {
        if (count <= 0 || !_isRunning) return;

        short* src = (short*)samplesPtr;
        int wh = _writeHead;
        for (int i = 0; i < count; i++)
        {
            _ring[(wh + i) & RingMask] = src[i];
        }
        Thread.MemoryBarrier();
        _writeHead = wh + count;
    }

    private void PlayLoop()
    {
        var buf = new short[1024];
        while (_isRunning && _track != null)
        {
            Thread.MemoryBarrier();
            int rh = _readHead;
            int wh = _writeHead;
            int available = wh - rh;

            if (available <= 0)
            {
                // No samples, write silence to keep stream alive
                Array.Clear(buf, 0, buf.Length);
                _track.Write(buf, 0, buf.Length);
                continue;
            }

            int toWrite = Math.Min(buf.Length, available);
            for (int i = 0; i < toWrite; i++)
            {
                buf[i] = _ring[(rh + i) & RingMask];
            }
            _readHead = rh + toWrite;

            _track.Write(buf, 0, toWrite);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Stop();
    }
}
#endif
