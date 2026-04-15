import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'nez_bindings.dart';

/// High-level emulator engine wrapping the FFI bindings.
/// Manages the game loop, framebuffer conversion, audio, and turbo button state.
class NezEngine extends ChangeNotifier {
  NezEmulator? _emu;
  Ticker? _ticker;

  // Frame state
  ui.Image? _currentFrame;
  int _fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Button state bitmask
  int _buttonState = 0;

  // Turbo state
  bool _turboA = false;
  bool _turboB = false;
  int _turboCounter = 0;
  static const _turboRate = 4; // toggle every N frames (~15Hz at 60fps)

  // Audio
  static const _audioChannel = MethodChannel('com.nez/audio');
  bool _audioStarted = false;
  final Pointer<Int16> _audioBuffer = malloc.allocate<Int16>(2048 * 2);
  static const _audioBufferSize = 2048;

  // GIF recording
  bool _recording = false;
  final List<Uint8List> _recordedFrames = [];
  static const _maxRecordFrames = 300; // ~5 seconds at 60fps
  Uint8List? _lastRgba; // keep last converted frame for recording

  // Callbacks
  VoidCallback? onFrameReady;

  String? _loadError;

  bool get isLoaded => _emu?.isLoaded ?? false;
  bool get isRunning => _emu?.isRunning ?? false;
  ui.Image? get currentFrame => _currentFrame;
  int get fps => _fps;
  bool get isPaused => _emu?.isPaused ?? true;
  String? get loadError => _loadError;
  bool get isRecording => _recording;

  int get screenWidth => isRunning ? _emu!.screenWidth : 256;
  int get screenHeight => isRunning ? _emu!.screenHeight : 240;

  /// Load a ROM and start the emulation loop.
  Future<bool> loadRom(String romPath) async {
    try {
      _emu ??= NezEmulator();
      debugPrint('NEZ: loading ROM: $romPath');
      final success = _emu!.loadRom(romPath);
      debugPrint('NEZ: loadRom result: $success, isRunning: ${_emu!.isRunning}');
      if (success) {
        _loadError = null;
        _startAudio();
        notifyListeners();
      } else {
        _loadError = 'Failed to load ROM (nez_create returned null)';
        debugPrint('NEZ: $_loadError');
      }
      return success;
    } catch (e) {
      _loadError = e.toString();
      debugPrint('NEZ: loadRom exception: $e');
      return false;
    }
  }

  void _startAudio() async {
    if (_audioStarted) return;
    try {
      await _audioChannel.invokeMethod('start');
      _audioStarted = true;
      debugPrint('NEZ: audio started');
    } catch (e) {
      debugPrint('NEZ: audio start failed: $e');
    }
  }

  void _stopAudio() async {
    if (!_audioStarted) return;
    try {
      await _audioChannel.invokeMethod('stop');
      _audioStarted = false;
    } catch (_) {}
  }

  /// Start the game loop ticker.
  void startLoop(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
    _ticker!.start();
  }

  Duration _lastElapsed = Duration.zero;
  static const _frameDuration = Duration(milliseconds: 16); // ~60fps

  void _onTick(Duration elapsed) {
    if (!isRunning) return;

    // Throttle to ~60fps even on 120Hz displays
    final dt = elapsed - _lastElapsed;
    if (dt < _frameDuration) return;
    _lastElapsed = elapsed;

    // Update turbo buttons
    _turboCounter++;
    if (_turboCounter >= _turboRate) {
      _turboCounter = 0;
      if (_turboA) {
        _buttonState ^= (1 << NesButton.a);
      }
      if (_turboB) {
        _buttonState ^= (1 << NesButton.b);
      }
    }

    // Set input
    _emu!.setButtons(_buttonState);

    // Run emulation for 16ms (one NES frame)
    _emu!.update(16);

    // Grab frame buffer and convert
    _convertFrameBuffer();

    // Push audio samples
    _drainAudio();

    // FPS counter
    _frameCount++;
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _fps = _frameCount;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }
  }

  void _drainAudio() {
    if (!_audioStarted || _emu == null) return;
    final count = _emu!.drainAudioSamples(_audioBuffer, _audioBufferSize);
    if (count > 0) {
      // Convert native Int16 buffer to Dart bytes
      final byteData = _audioBuffer.cast<Uint8>().asTypedList(count * 2);
      _audioChannel.invokeMethod('pushSamples', byteData);
    }
  }

  void _convertFrameBuffer() {
    final fb = _emu!.getFrameBuffer();
    if (fb == null) return;

    final w = screenWidth;
    final h = screenHeight;
    final rgba = Uint8List(w * h * 4);

    for (int i = 0; i < w * h; i++) {
      rgba[i * 4 + 0] = fb[i * 3 + 0]; // R
      rgba[i * 4 + 1] = fb[i * 3 + 1]; // G
      rgba[i * 4 + 2] = fb[i * 3 + 2]; // B
      rgba[i * 4 + 3] = 255; // A
    }

    // Capture frame for GIF recording (every other frame to reduce size)
    if (_recording && _recordedFrames.length < _maxRecordFrames) {
      if (_frameCount % 2 == 0) {
        _recordedFrames.add(Uint8List.fromList(rgba));
      }
    }
    _lastRgba = rgba;

    for (int i = 0; i < w * h; i++) {
      rgba[i * 4 + 0] = fb[i * 3 + 0]; // R
      rgba[i * 4 + 1] = fb[i * 3 + 1]; // G
      rgba[i * 4 + 2] = fb[i * 3 + 2]; // B
      rgba[i * 4 + 3] = 255; // A
    }

    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      (image) {
        _currentFrame?.dispose();
        _currentFrame = image;
        onFrameReady?.call();
        notifyListeners();
      },
    );
  }

  // ---- Input ----

  void setButton(int button, bool pressed) {
    if (pressed) {
      _buttonState |= (1 << button);
    } else {
      _buttonState &= ~(1 << button);
    }
  }

  void setTurboA(bool active) => _turboA = active;
  void setTurboB(bool active) => _turboB = active;

  set paused(bool value) {
    _emu?.paused = value;
    notifyListeners();
  }

  void togglePause() {
    paused = !isPaused;
  }

  // ---- Debug ----
  int get cpuPc => _emu?.cpuPc ?? 0;

  // ---- GIF Recording ----

  void startRecording() {
    _recordedFrames.clear();
    _recording = true;
    notifyListeners();
  }

  /// Stop recording and encode to GIF. Returns file path or null.
  Future<String?> stopRecording() async {
    _recording = false;
    notifyListeners();
    if (_recordedFrames.isEmpty) return null;

    final w = screenWidth;
    final h = screenHeight;
    final frames = List<Uint8List>.from(_recordedFrames);
    _recordedFrames.clear();

    // Encode in background isolate
    return compute(_encodeGifIsolate, _GifParams(w, h, frames));
  }

  /// Stop and clean up.
  @override
  void dispose() {
    _stopAudio();
    _ticker?.dispose();
    _currentFrame?.dispose();
    _emu?.dispose();
    malloc.free(_audioBuffer);
    super.dispose();
  }
}

class _GifParams {
  final int w, h;
  final List<Uint8List> frames;
  _GifParams(this.w, this.h, this.frames);
}

String? _encodeGifIsolate(_GifParams p) {
  try {
    final firstFrame = img.Image(width: p.w, height: p.h);
    for (int i = 0; i < p.w * p.h; i++) {
      final rgba = p.frames[0];
      firstFrame.setPixelRgba(i % p.w, i ~/ p.w, rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], rgba[i * 4 + 3]);
    }
    firstFrame.frameDuration = 33;

    for (int f = 1; f < p.frames.length; f++) {
      final frame = img.Image(width: p.w, height: p.h);
      final rgba = p.frames[f];
      for (int i = 0; i < p.w * p.h; i++) {
        frame.setPixelRgba(i % p.w, i ~/ p.w, rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], rgba[i * 4 + 3]);
      }
      frame.frameDuration = 33;
      firstFrame.frames.add(frame);
    }

    final encoded = img.encodeGif(firstFrame);
    final path = '${Directory.systemTemp.path}/nez_${DateTime.now().millisecondsSinceEpoch}.gif';
    File(path).writeAsBytesSync(encoded);
    return path;
  } catch (_) {
    return null;
  }
}
