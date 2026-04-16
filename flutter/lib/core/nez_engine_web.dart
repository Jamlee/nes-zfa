import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// NES button indices (matches native NezButton).
class NesWebButton {
  static const int a = 0;
  static const int b = 1;
  static const int select = 2;
  static const int start = 3;
  static const int up = 4;
  static const int down = 5;
  static const int left = 6;
  static const int right = 7;
}

/// Web-specific engine that runs the NES emulator via WASM.
class NezWebEngine extends ChangeNotifier {
  bool _ready = false;
  bool _running = false;
  String? _error;

  // Button state
  int _buttonState = 0;

  // FPS tracking
  int _fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Frame buffer as RGBA bytes
  Uint8List? _frameRgba;

  // Game loop
  int? _animationFrameId;
  static const int _frameDurationMs = 16; // ~60fps

  bool get isReady => _ready;
  bool get isRunning => _running;
  String? get error => _error;
  int get fps => _fps;
  Uint8List? get frameRgba => _frameRgba;

  /// Initialize the WASM emulator.
  Future<bool> initialize() async {
    if (_ready) return true;

    try {
      final nezWasm = (web.window as dynamic).NezWasm;
      final success = await nezWasm.load('nez_emu.wasm');
      if (success != true) {
        _error = 'Failed to load NEZ WASM module';
        notifyListeners();
        return false;
      }

      _ready = true;
      _error = null;
      debugPrint('NEZ Web: WASM initialized');
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'WASM init error: $e';
      debugPrint('NEZ Web: $_error');
      notifyListeners();
      return false;
    }
  }

  /// Load a ROM from a byte array.
  Future<bool> loadRomFromBytes(Uint8List romBytes) async {
    if (!_ready) {
      final initOk = await initialize();
      if (!initOk) return false;
    }

    try {
      final nezWasm = (web.window as dynamic).NezWasm;
      final jsArray = romBytes.toJS;
      final success = nezWasm.loadRom(jsArray);
      if (success != true) {
        _error = 'Failed to load ROM into WASM';
        return false;
      }

      _running = true;
      _startGameLoop();
      debugPrint('NEZ Web: ROM loaded, ${romBytes.length} bytes');
      return true;
    } catch (e) {
      _error = 'ROM load error: $e';
      debugPrint('NEZ Web: $_error');
      return false;
    }
  }

  /// Load one of the bundled demo ROMs by name.
  Future<bool> loadBundledRom(String romName) async {
    try {
      // Use dynamic fetch to avoid JS interop type mismatches
      final fetchResult = await _dynamicFetch('assets/roms/$romName.nes');
      if (fetchResult == null) throw Exception('Fetch failed');

      final bytes = Uint8List.fromList(fetchResult);
      return loadRomFromBytes(bytes);
    } catch (e) {
      _error = 'Bundled ROM "$romName" not found: $e';
      debugPrint('NEZ Web: $_error');
      return false;
    }
  }

  /// Fetch via JS interop using dynamic dispatch to avoid type issues.
  Future<Uint8List?> _dynamicFetch(String url) async {
    try {
      // Use dart:js_interop promiseToFuture extension
      final response = await ((web.window.fetch(url.toJS) as JSPromise)
          .toDart); // ignore: invalid_runtime_check_with_js_interop_types
      if (response == null) return null;
      final ok = (response as dynamic).ok;
      if (ok != true) return null;

      final bufferPromise =
          ((response as dynamic).arrayBuffer() as JSPromise);
      final buffer = await bufferPromise.toDart; // ignore: invalid_runtime_check_with_js_interop_types
      if (buffer == null) return null;

      // Convert ArrayBuffer to Uint8List via JS Uint8Array
      final jsUint8 = (JSUint8Array as dynamic)(buffer);
      final len = jsUint8.length;
      final result = Uint8List(len);
      for (int i = 0; i < len; i++) {
        result[i] = (jsUint8[i] as int);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  void _startGameLoop() {
    _stopGameLoop();
    _lastFpsUpdate = DateTime.now();

    void loop(int timestamp) {
      if (!_running) return;

      try {
        final nezWasm = (web.window as dynamic).NezWasm;
        nezWasm.setButtons(_buttonState);
        nezWasm.update(_frameDurationMs);

        _readFrameBuffer();

        _frameCount++;
        final now = DateTime.now();
        if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
          _fps = _frameCount;
          _frameCount = 0;
          _lastFpsUpdate = now;
          notifyListeners();
        }

        _animationFrameId = web.window.requestAnimationFrame(loop.toJS);
      } catch (e) {
        debugPrint('NEZ Web: game loop error: $e');
      }
    }

    _animationFrameId = web.window.requestAnimationFrame(loop.toJS);
  }

  void _stopGameLoop() {
    if (_animationFrameId != null) {
      web.window.cancelAnimationFrame(_animationFrameId!);
      _animationFrameId = null;
    }
  }

  void _readFrameBuffer() {
    try {
      final nezWasm = (web.window as dynamic).NezWasm;
      final fb = nezWasm.getFrameBuffer();
      if (fb == null) return;

      // fb is a JS Uint8Array of RGB24 data — use dynamic conversion
      final pixelCount = 256 * 240;
      final rgba = Uint8List(pixelCount * 4);

      // Access via indexed JS interop
      for (int i = 0; i < pixelCount; i++) {
        rgba[i * 4 + 0] = (fb[i * 3] as int); // R
        rgba[i * 4 + 1] = (fb[i * 3 + 1] as int); // G
        rgba[i * 4 + 2] = (fb[i * 3 + 2] as int); // B
        rgba[i * 4 + 3] = 255; // A
      }

      _frameRgba = rgba;
      notifyListeners();
    } catch (e) {
      debugPrint('NEZ Web: framebuffer read error: $e');
    }
  }

  // ---- Input ----

  void setButton(int button, bool pressed) {
    if (pressed) {
      _buttonState |= (1 << button);
    } else {
      _buttonState &= ~(1 << button);
    }
  }

  // ---- Control ----

  set paused(bool value) {
    final nezWasm = (web.window as dynamic).NezWasm;
    if (value) {
      _stopGameLoop();
      nezWasm?.setPause(true);
    } else {
      nezWasm?.setPause(false);
      _startGameLoop();
    }
    _running = !value;
    notifyListeners();
  }

  bool get paused => !_running && _ready;
  void togglePause() => paused = !paused;

  @override
  void dispose() {
    _stopGameLoop();
    _running = false;
    _ready = false;
    super.dispose();
  }
}
