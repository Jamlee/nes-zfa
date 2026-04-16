/// Web stub — provides [NezEngine] class that delegates to [NezWebEngine].
/// Used when dart:io is unavailable (web compilation).
///
/// On native platforms, [nez_engine.dart] provides the real FFI-based implementation.

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:typed_data';

import 'nez_engine_web.dart';

/// Web-compatible engine that wraps [NezWebEngine] with the same API surface
/// as the native [NezEngine] so that screens can use either interchangeably.
class NezEngine extends ChangeNotifier {
  final NezWebEngine _web = NezWebEngine();
  bool get isLoaded => _web.isReady;
  bool get isRunning => _web.isRunning;
  bool get isPaused => _web.paused;
  int get fps => _web.fps;
  /// Web renders via HTML canvas — always returns null on web.
  dynamic get currentFrame => null;
  bool get isRecording => false; // GIF recording not supported on web
  int get screenWidth => 256;
  int get screenHeight => 240;
  String? get loadError => _web.error;

  VoidCallback? onFrameReady;
  Uint8List? _lastRgba;

  Future<bool> loadRom(String romPath) async {
    // On web, try loading as bundled asset name
    return _web.loadBundledRom(romPath);
  }

  void startLoop(dynamic vsync) {
    // Web uses requestAnimationFrame, no TickerProvider needed
    _web.setButton(0, false); // noop
  }

  void setButton(int button, bool pressed) => _web.setButton(button, pressed);
  void setTurboA(bool active) { /* turbo via JS interop not implemented */ }
  void setTurboB(bool active) { /* turbo via JS interop not implemented */ }
  void setButtonP2(int button, bool pressed) { /* P2 not supported on web */ }
  Uint8List? get lastRgbaFrame => _lastRgba;
  int get cpuPc => 0; // Not available on web

  set paused(bool value) { _web.paused = value; }
  void togglePause() => _web.togglePause();

  void startRecording([String romName = '']) {}
  Future<String?> stopRecording() async => null;

  @override
  void dispose() {
    _web.dispose();
    super.dispose();
  }
}
