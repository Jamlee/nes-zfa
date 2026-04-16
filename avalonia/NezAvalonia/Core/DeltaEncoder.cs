using System;

namespace NezAvalonia.Core;

/// <summary>
/// Incremental frame transfer protocol for NES emulator.
/// Only transmits changed pixel blocks between frames, drastically reducing bandwidth.
///
/// Wire format (binary, little-endian):
///   Header (8 bytes):
///     [0..2]  Magic: 0x4E 0x5A ("NZ")
///     [2]     Version: 0x01
///     [3]     Frame type:
///               0x00 = Full frame (raw pixels)
///               0x01 = Delta frame (block diffs)
///     [4..6]  Frame number (uint16, wraps around for freshness check)
///     [6]     Pixel format: 0x00 = BGRA32, 0x01 = RGBA32
///     [7]     Reserved (0x00)
///
///   Full frame body (type 0x00):
///     Raw BGRA32 pixel data [256 * 240 * 4 = 245760 bytes]
///
///   Delta frame body (type 0x01):
///     [0..2]  Block size (uint16) — e.g. 8 means 8x8 pixel blocks
///     [2..4]  Cols (uint16) — width / block_size
///     [4..6]  Rows (uint16) — height / block_size
///     [6..8]  Changed block count N (uint16)
///     For each changed block:
///       [0..2]  Block index (uint16) — row * cols + col
///       [2..]   Raw BGRA32 pixel data for this block (block_size * block_size * 4 bytes)
///
/// Client must track the previous frame buffer. On receiving a full frame, replace entirely.
/// On receiving a delta frame, patch changed blocks into the previous buffer.
/// If frame number skips or client has no buffer, request a full frame.
/// </summary>
public sealed class DeltaEncoder
{
    private readonly int _width;
    private readonly int _height;
    private readonly int _blockSize;
    private readonly int _cols;
    private readonly int _rows;
    private readonly int _blocksPerPixel = 4; // BGRA32

    // Previous frame buffer for diff computation (BGRA32)
    private byte[]? _prevFrame;

    // Sequential frame counter
    private ushort _frameNum;

    // Cached change flags per block (avoid GC alloc each frame)
    private bool[]? _changedBlocks;

    /// <summary>
    /// Wire protocol magic bytes.
    /// </summary>
    public static ReadOnlySpan<byte> Magic => new byte[] { 0x4E, 0x5A }; // "NZ"

    /// <summary>
    /// Current protocol version.
    /// </summary>
    public const byte ProtocolVersion = 0x01;

    /// <summary>
    /// Frame type: full raw frame.
    /// </summary>
    public const byte FrameTypeFull = 0x00;

    /// <summary>
    /// Frame type: delta (block diffs).
    /// </summary>
    public const byte FrameTypeDelta = 0x01;

    /// <summary>
    /// Pixel format: BGRA32 (native framebuffer format).
    /// </summary>
    public const byte PixelFormatBgra32 = 0x00;

    /// <summary>
    /// Pixel format: RGBA32.
    /// </summary>
    public const byte PixelFormatRgba32 = 0x01;

    private readonly byte _pixelFormat;

    public DeltaEncoder(int width, int height, int blockSize = 8, byte pixelFormat = PixelFormatBgra32)
    {
        if (width % blockSize != 0 || height % blockSize != 0)
            throw new ArgumentException($"Screen dimensions ({width}x{height}) must be divisible by block size ({blockSize})");

        _width = width;
        _height = height;
        _blockSize = blockSize;
        _cols = width / blockSize;
        _rows = height / blockSize;
        _pixelFormat = pixelFormat;
    }

    /// <summary>
    /// Encode a new BGRA32 frame. First call always produces a full frame.
    /// Subsequent calls produce delta frames when possible.
    /// Returns the encoded binary payload ready to send.
    /// </summary>
    public byte[] Encode(byte[] bgraFrame)
    {
        if (bgraFrame.Length != _width * _height * _blocksPerPixel)
            throw new ArgumentException($"Frame size mismatch: expected {_width * _height * _blocksPerPixel}, got {bgraFrame.Length}");

        // First frame: always full
        if (_prevFrame == null)
        {
            _prevFrame = new byte[bgraFrame.Length];
            Buffer.BlockCopy(bgraFrame, 0, _prevFrame, 0, bgraFrame.Length);
            _changedBlocks = new bool[_cols * _rows];
            return BuildFullFrame(bgraFrame);
        }

        // Detect changed blocks
        int changedCount = DetectChangedBlocks(bgraFrame);

        // If too many blocks changed, send full frame (more efficient)
        if (changedCount > _cols * _rows * 2 / 3)
        {
            Buffer.BlockCopy(bgraFrame, 0, _prevFrame, 0, bgraFrame.Length);
            return BuildFullFrame(bgraFrame);
        }

        // Build delta frame
        var delta = BuildDeltaFrame(bgraFrame, changedCount);

        // Update previous frame
        Buffer.BlockCopy(bgraFrame, 0, _prevFrame, 0, bgraFrame.Length);

        return delta;
    }

    /// <summary>
    /// Force a full frame on next encode call (e.g. after client reconnect).
    /// </summary>
    public void Reset()
    {
        _prevFrame = null;
        _frameNum = 0;
    }

    private int DetectChangedBlocks(byte[] frame)
    {
        int changedCount = 0;
        int blockStride = _blockSize * _blocksPerPixel; // bytes per row of a block
        int frameStride = _width * _blocksPerPixel;     // bytes per row of the full frame

        for (int by = 0; by < _rows; by++)
        {
            for (int bx = 0; bx < _cols; bx++)
            {
                int blockIdx = by * _cols + bx;
                bool changed = false;

                int baseX = bx * _blockSize;
                int baseY = by * _blockSize;

                for (int py = 0; py < _blockSize; py++)
                {
                    int srcOffset = ((baseY + py) * _width + baseX) * _blocksPerPixel;
                    int prevOffset = srcOffset;

                    // Compare 4 bytes (one BGRA pixel) at a time
                    for (int px = 0; px < _blockSize; px++)
                    {
                        int offset = srcOffset + px * 4;
                        int pOff = prevOffset + px * 4;
                        if (frame[offset] != _prevFrame![pOff] ||
                            frame[offset + 1] != _prevFrame[pOff + 1] ||
                            frame[offset + 2] != _prevFrame[pOff + 2] ||
                            frame[offset + 3] != _prevFrame[pOff + 3])
                        {
                            changed = true;
                            goto BlockDone;
                        }
                    }
                }

            BlockDone:
                _changedBlocks![blockIdx] = changed;
                if (changed) changedCount++;
            }
        }

        return changedCount;
    }

    private byte[] BuildFullFrame(byte[] frame)
    {
        // Header (8) + raw pixels
        byte[] payload = new byte[8 + frame.Length];
        int pos = 0;

        // Magic
        payload[pos++] = Magic[0];
        payload[pos++] = Magic[1];
        // Version
        payload[pos++] = ProtocolVersion;
        // Frame type
        payload[pos++] = FrameTypeFull;
        // Frame number
        WriteUInt16(payload, ref pos, _frameNum++);
        // Pixel format
        payload[pos++] = _pixelFormat;
        // Reserved
        payload[pos++] = 0x00;

        Buffer.BlockCopy(frame, 0, payload, pos, frame.Length);
        return payload;
    }

    private byte[] BuildDeltaFrame(byte[] frame, int changedCount)
    {
        int blockDataSize = _blockSize * _blockSize * _blocksPerPixel;
        // Header (8) + delta header (8) + N * (2 + blockDataSize)
        int payloadSize = 8 + 8 + changedCount * (2 + blockDataSize);
        byte[] payload = new byte[payloadSize];
        int pos = 0;

        // === Wire header ===
        payload[pos++] = Magic[0];
        payload[pos++] = Magic[1];
        payload[pos++] = ProtocolVersion;
        payload[pos++] = FrameTypeDelta;
        WriteUInt16(payload, ref pos, _frameNum++);
        payload[pos++] = _pixelFormat;
        payload[pos++] = 0x00;

        // === Delta header ===
        WriteUInt16(payload, ref pos, (ushort)_blockSize);
        WriteUInt16(payload, ref pos, (ushort)_cols);
        WriteUInt16(payload, ref pos, (ushort)_rows);
        WriteUInt16(payload, ref pos, (ushort)changedCount);

        // === Changed blocks ===
        int frameStride = _width * _blocksPerPixel;

        for (int i = 0; i < _cols * _rows; i++)
        {
            if (!_changedBlocks![i]) continue;

            // Block index
            WriteUInt16(payload, ref pos, (ushort)i);

            // Block pixel data
            int bx = (i % _cols) * _blockSize;
            int by = (i / _cols) * _blockSize;

            for (int py = 0; py < _blockSize; py++)
            {
                int srcOffset = ((by + py) * _width + bx) * _blocksPerPixel;
                int copyLen = _blockSize * _blocksPerPixel;
                Buffer.BlockCopy(frame, srcOffset, payload, pos, copyLen);
                pos += copyLen;
            }
        }

        return payload;
    }

    private static void WriteUInt16(byte[] buf, ref int offset, ushort value)
    {
        buf[offset++] = (byte)(value & 0xFF);
        buf[offset++] = (byte)((value >> 8) & 0xFF);
    }
}
