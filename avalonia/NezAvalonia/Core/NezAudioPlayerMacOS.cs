#if !ANDROID
using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace NezAvalonia.Core;

/// <summary>
/// Audio player using macOS AudioToolbox (AudioQueue) via P/Invoke.
/// Uses Float32 PCM format at 44100 Hz mono.
/// </summary>
public sealed class NezAudioPlayerMacOS : INezAudioPlayer
{
    private const int SampleRate = 44100;
    private const int NumBuffers = 3;
    private const int BufferFrames = 1024;
    private const int BytesPerFrame = 4; // Float32
    private const int BufferBytes = BufferFrames * BytesPerFrame;

    private IntPtr _audioQueue;
    private readonly IntPtr[] _buffers = new IntPtr[NumBuffers];
    private bool _isRunning;
    private bool _disposed;

    // Thread-safe ring buffer (stores Float32 samples)
    private const int RingSize = 1 << 16; // 65536
    private const int RingMask = RingSize - 1;
    private readonly float[] _ring = new float[RingSize];
    private int _writeHead;
    private int _readHead;

    private readonly AudioQueueOutputCallback _callbackDelegate;
    private GCHandle _callbackHandle;

    // Define the struct to avoid manual pointer offsets
    [StructLayout(LayoutKind.Sequential)]
    private struct AudioQueueBuffer
    {
        public uint mAudioDataBytesCapacity;
        public IntPtr mAudioData;
        public uint mAudioDataByteSize;
        public IntPtr mUserData;
        public uint mPacketDescriptionCapacity;
        public IntPtr mPacketDescriptions;
        public uint mPacketDescriptionCount;
    }

    public NezAudioPlayerMacOS()
    {
        _callbackDelegate = OnCallback;
        _callbackHandle = GCHandle.Alloc(_callbackDelegate);
    }

    public bool Start()
    {
        if (_isRunning) return true;

        // Float32, mono, 44100 Hz — matches Flutter's AVAudioEngine format
        var desc = new AudioStreamBasicDescription
        {
            mSampleRate = SampleRate,
            mFormatID = 0x6C70636D, // 'lpcm'
            mFormatFlags = 0x01 | 0x08, // kFloat(0x1) | kPacked(0x8)
            mBytesPerPacket = BytesPerFrame,
            mFramesPerPacket = 1,
            mBytesPerFrame = BytesPerFrame,
            mChannelsPerFrame = 1,
            mBitsPerChannel = 32,
            mReserved = 0,
        };

        int status = AudioQueueNewOutput(ref desc, _callbackDelegate, IntPtr.Zero,
            IntPtr.Zero, IntPtr.Zero, 0, out _audioQueue);
        if (status != 0) return false;

        // Set volume
        AudioQueueSetParameter(_audioQueue, 1 /* kAudioQueueParam_Volume */, 1.0f);

        for (int i = 0; i < NumBuffers; i++)
        {
            status = AudioQueueAllocateBuffer(_audioQueue, (uint)BufferBytes, out _buffers[i]);
            if (status != 0) return false;
            ClearBuffer(_buffers[i]);
            AudioQueueEnqueueBuffer(_audioQueue, _buffers[i], 0, IntPtr.Zero);
        }

        status = AudioQueueStart(_audioQueue, IntPtr.Zero);
        if (status != 0) return false;

        _isRunning = true;
        return true;
    }

    public void Stop()
    {
        if (!_isRunning || _audioQueue == IntPtr.Zero) return;
        _isRunning = false;
        AudioQueueStop(_audioQueue, true);
        AudioQueueDispose(_audioQueue, true);
        _audioQueue = IntPtr.Zero;
    }

    public void SetVolume(double volume)
    {
        if (_audioQueue != IntPtr.Zero)
            AudioQueueSetParameter(_audioQueue, 1 /* kAudioQueueParam_Volume */, (float)volume);
    }

    /// <summary>
    /// Push Int16 PCM samples from emulator, converting to Float32 for the ring buffer.
    /// Called from game loop (UI thread) — single producer.
    /// </summary>
    public unsafe void PushSamples(IntPtr samplesPtr, int count)
    {
        if (count <= 0 || !_isRunning) return;

        short* src = (short*)samplesPtr;
        int wh = _writeHead;
        for (int i = 0; i < count; i++)
        {
            // Int16 → Float32, same conversion as Flutter's Swift code
            _ring[(wh + i) & RingMask] = src[i] / 32768.0f;
        }
        Thread.MemoryBarrier();
        _writeHead = wh + count;
    }

    private void OnCallback(IntPtr userData, IntPtr audioQueue, IntPtr bufferPtr)
    {
        // Guard against callbacks firing after Stop()/Dispose() has already cleaned up.
        // AudioQueueStop(immediate:true) should drain pending buffers, but race conditions
        // can still deliver one final callback on the audio thread.
        if (_disposed || !_isRunning) return;
        unsafe
        {
            AudioQueueBuffer* buf = (AudioQueueBuffer*)bufferPtr;
            float* dst = (float*)buf->mAudioData;

            Thread.MemoryBarrier();
            int rh = _readHead;
            int wh = _writeHead;
            int available = wh - rh;
            int toWrite = Math.Min(BufferFrames, Math.Max(0, available));

            for (int i = 0; i < toWrite; i++)
            {
                dst[i] = _ring[(rh + i) & RingMask];
            }
            for (int i = toWrite; i < BufferFrames; i++)
            {
                dst[i] = 0f;
            }

            _readHead = rh + toWrite;
            buf->mAudioDataByteSize = (uint)BufferBytes;
        }

        AudioQueueEnqueueBuffer(audioQueue, bufferPtr, 0, IntPtr.Zero);
    }

    private unsafe void ClearBuffer(IntPtr bufferPtr)
    {
        AudioQueueBuffer* buf = (AudioQueueBuffer*)bufferPtr;
        new Span<byte>((void*)buf->mAudioData, BufferBytes).Clear();
        buf->mAudioDataByteSize = (uint)BufferBytes;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Stop();
        if (_callbackHandle.IsAllocated)
            _callbackHandle.Free();
    }

    // ---- P/Invoke ----

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void AudioQueueOutputCallback(IntPtr userData, IntPtr audioQueue, IntPtr buffer);

    [StructLayout(LayoutKind.Sequential)]
    private struct AudioStreamBasicDescription
    {
        public double mSampleRate;
        public uint mFormatID;
        public uint mFormatFlags;
        public uint mBytesPerPacket;
        public uint mFramesPerPacket;
        public uint mBytesPerFrame;
        public uint mChannelsPerFrame;
        public uint mBitsPerChannel;
        public uint mReserved;
    }

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueNewOutput(ref AudioStreamBasicDescription format,
        AudioQueueOutputCallback callback, IntPtr userData,
        IntPtr callbackRunLoop, IntPtr callbackRunLoopMode, uint flags, out IntPtr audioQueue);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueAllocateBuffer(IntPtr aq, uint bufferByteSize, out IntPtr buffer);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueEnqueueBuffer(IntPtr aq, IntPtr buffer, uint numPackets, IntPtr packetDescs);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueStart(IntPtr aq, IntPtr startTime);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueStop(IntPtr aq, [MarshalAs(UnmanagedType.I1)] bool immediate);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueDispose(IntPtr aq, [MarshalAs(UnmanagedType.I1)] bool immediate);

    [DllImport("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox")]
    private static extern int AudioQueueSetParameter(IntPtr aq, uint paramID, float value);
}
#endif
