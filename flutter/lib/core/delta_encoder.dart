import 'dart:typed_data';

/// Incremental frame transfer protocol for NES emulator.
/// Only transmits changed pixel blocks between frames.
///
/// Wire format (binary, little-endian):
///   Header (8 bytes):
///     [0..2]  Magic: 0x4E 0x5A ("NZ")
///     [2]     Version: 0x01
///     [3]     Frame type: 0x00=Full, 0x01=Delta
///     [4..6]  Frame number (uint16)
///     [6]     Pixel format: 0x00 = BGRA32, 0x01 = RGBA32
///     [7]     Reserved
///
///   Full frame (type 0x00): raw BGRA32 pixels
///   Delta frame (type 0x01):
///     [0..2]  Block size (uint16)
///     [2..4]  Cols (uint16)
///     [4..6]  Rows (uint16)
///     [6..8]  Changed block count N (uint16)
///     N times: [blockIndex:uint16][blockData:blockSize*blockSize*4]
class DeltaEncoder {
  final int width;
  final int height;
  final int blockSize;
  final int cols;
  final int rows;
  static const int _bpp = 4; // BGRA32/RGBA32

  /// Pixel format constants
  static const int pixelFormatBgra32 = 0x00;
  static const int pixelFormatRgba32 = 0x01;

  Uint8List? _prevFrame;
  int _frameNum = 0;
  final int _pixelFormat;

  /// List of (blockIndex, blockData) for changed blocks
  final List<(int, Uint8List)> _changedBlocks = [];

  DeltaEncoder({
    required this.width,
    required this.height,
    this.blockSize = 8,
    int pixelFormat = pixelFormatBgra32,
  })  : cols = width ~/ blockSize,
        rows = height ~/ blockSize,
        _pixelFormat = pixelFormat {
    assert(width % blockSize == 0 && height % blockSize == 0);
  }

  /// Encode a new BGRA32 frame. First call always produces a full frame.
  Uint8List encode(Uint8List bgraFrame) {
    if (_prevFrame == null) {
      _prevFrame = Uint8List.fromList(bgraFrame);
      return _buildFullFrame(bgraFrame);
    }

    final changedCount = _detectChangedBlocks(bgraFrame);

    // If too many blocks changed (>66%), full frame is more efficient
    if (changedCount > cols * rows * 2 ~/ 3) {
      _prevFrame = Uint8List.fromList(bgraFrame);
      return _buildFullFrame(bgraFrame);
    }

    final delta = _buildDeltaFrame(bgraFrame, changedCount);
    _prevFrame = Uint8List.fromList(bgraFrame);
    return delta;
  }

  /// Force a full frame on next encode (e.g. after client reconnect).
  void reset() {
    _prevFrame = null;
    _frameNum = 0;
  }

  int _detectChangedBlocks(Uint8List frame) {
    _changedBlocks.clear();
    final prev = _prevFrame!;

    for (int by = 0; by < rows; by++) {
      for (int bx = 0; bx < cols; bx++) {
        final blockIdx = by * cols + bx;
        bool changed = false;

        final baseX = bx * blockSize;
        final baseY = by * blockSize;

        for (int py = 0; py < blockSize && !changed; py++) {
          final rowOff = ((baseY + py) * width + baseX) * _bpp;
          for (int px = 0; px < blockSize * _bpp; px++) {
            if (frame[rowOff + px] != prev[rowOff + px]) {
              changed = true;
              break;
            }
          }
        }

        if (changed) {
          // Extract block data
          final blockData = Uint8List(blockSize * blockSize * _bpp);
          for (int py = 0; py < blockSize; py++) {
            final srcOff = ((baseY + py) * width + baseX) * _bpp;
            final dstOff = py * blockSize * _bpp;
            for (int i = 0; i < blockSize * _bpp; i++) {
              blockData[dstOff + i] = frame[srcOff + i];
            }
          }
          _changedBlocks.add((blockIdx, blockData));
        }
      }
    }

    return _changedBlocks.length;
  }

  Uint8List _buildFullFrame(Uint8List frame) {
    final payload = Uint8List(8 + frame.length);
    final bd = ByteData.view(payload.buffer);

    bd.setUint8(0, 0x4E); // 'N'
    bd.setUint8(1, 0x5A); // 'Z'
    bd.setUint8(2, 0x01); // version
    bd.setUint8(3, 0x00); // full frame
    bd.setUint16(4, _frameNum & 0xFFFF, Endian.little);
    bd.setUint8(6, _pixelFormat);
    bd.setUint8(7, 0x00);

    payload.setRange(8, 8 + frame.length, frame);
    _frameNum++;
    return payload;
  }

  Uint8List _buildDeltaFrame(Uint8List frame, int changedCount) {
    final blockDataSize = blockSize * blockSize * _bpp;
    final payloadSize = 8 + 8 + changedCount * (2 + blockDataSize);
    final payload = Uint8List(payloadSize);
    final bd = ByteData.view(payload.buffer);

    // Wire header
    bd.setUint8(0, 0x4E);
    bd.setUint8(1, 0x5A);
    bd.setUint8(2, 0x01);
    bd.setUint8(3, 0x01); // delta frame
    bd.setUint16(4, _frameNum & 0xFFFF, Endian.little);
    bd.setUint8(6, _pixelFormat);
    bd.setUint8(7, 0x00);

    // Delta header
    bd.setUint16(8, blockSize, Endian.little);
    bd.setUint16(10, cols, Endian.little);
    bd.setUint16(12, rows, Endian.little);
    bd.setUint16(14, changedCount, Endian.little);

    int pos = 16;
    for (final (blockIdx, blockData) in _changedBlocks) {
      bd.setUint16(pos, blockIdx, Endian.little);
      pos += 2;
      payload.setRange(pos, pos + blockDataSize, blockData);
      pos += blockDataSize;
    }

    _frameNum++;
    return payload;
  }
}
