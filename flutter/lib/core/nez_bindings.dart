import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Opaque handle to the NES console instance on the native side.
typedef NezConsole = Pointer<Void>;

// ============================================================================
// Native function typedefs
// ============================================================================

// Lifecycle
typedef _NezCreateC = Pointer<Void> Function(Pointer<Uint8> path);
typedef _NezCreateDart = Pointer<Void> Function(Pointer<Uint8> path);

typedef _NezDestroyC = Void Function(Pointer<Void> console);
typedef _NezDestroyDart = void Function(Pointer<Void> console);

typedef _NezLoadRomC = Bool Function(Pointer<Void> console, Pointer<Uint8> path);
typedef _NezLoadRomDart = bool Function(Pointer<Void> console, Pointer<Uint8> path);

typedef _NezPowerOnC = Void Function(Pointer<Void> console);
typedef _NezPowerOnDart = void Function(Pointer<Void> console);

// Emulation
typedef _NezUpdateC = Uint64 Function(Pointer<Void> console, Uint64 dtMs);
typedef _NezUpdateDart = int Function(Pointer<Void> console, int dtMs);

// Framebuffer
typedef _NezFramebufferGetC = Pointer<Uint8> Function(Pointer<Void> console);
typedef _NezFramebufferGetDart = Pointer<Uint8> Function(Pointer<Void> console);

typedef _NezScreenDimC = Uint32 Function();
typedef _NezScreenDimDart = int Function();

typedef _NezFramebufferSizeC = Uint32 Function();
typedef _NezFramebufferSizeDart = int Function();

// Audio
typedef _NezAudioQueuePopC = Int16 Function(Pointer<Void> console);
typedef _NezAudioQueuePopDart = int Function(Pointer<Void> console);

typedef _NezAudioQueueLenC = Uint32 Function(Pointer<Void> console);
typedef _NezAudioQueueLenDart = int Function(Pointer<Void> console);

typedef _NezAudioQueueDrainC = Uint32 Function(
    Pointer<Void> console, Pointer<Int16> outBuffer, Uint32 maxSamples);
typedef _NezAudioQueueDrainDart = int Function(
    Pointer<Void> console, Pointer<Int16> outBuffer, int maxSamples);

// Input
typedef _NezInputSetButtonsC = Void Function(
    Pointer<Void> console, Uint8 buttonState);
typedef _NezInputSetButtonsDart = void Function(
    Pointer<Void> console, int buttonState);

typedef _NezInputSetButtonC = Void Function(
    Pointer<Void> console, Uint8 buttonIndex, Bool pressed);
typedef _NezInputSetButtonDart = void Function(
    Pointer<Void> console, int buttonIndex, bool pressed);

// Pause
typedef _NezIsPausedC = Bool Function(Pointer<Void> console);
typedef _NezIsPausedDart = bool Function(Pointer<Void> console);

typedef _NezSetPauseC = Void Function(Pointer<Void> console, Bool paused);
typedef _NezSetPauseDart = void Function(Pointer<Void> console, bool paused);

// Debug
typedef _NezCpuGetPcC = Uint16 Function(Pointer<Void> console);
typedef _NezCpuGetPcDart = int Function(Pointer<Void> console);

/// NES button indices (matches Zig Gamepad.Button enum order).
class NesButton {
  static const int a = 0;
  static const int b = 1;
  static const int select = 2;
  static const int start = 3;
  static const int up = 4;
  static const int down = 5;
  static const int left = 6;
  static const int right = 7;
}

/// CPU register snapshot from native side.
final class CpuRegisters extends Struct {
  @Uint8()
  external int a;
  @Uint8()
  external int x;
  @Uint8()
  external int y;
  @Uint8()
  external int s;
  @Uint16()
  external int pc;
  @Uint8()
  external int p;
}

typedef _NezCpuGetRegistersC = CpuRegisters Function(Pointer<Void> console);
typedef _NezCpuGetRegistersDart = CpuRegisters Function(Pointer<Void> console);

/// Dart wrapper around the Zig NES emulator shared library.
class NezEmulator {
  late final DynamicLibrary _lib;
  Pointer<Void> _console = nullptr;

  // Bound functions
  late final _NezCreateDart _create;
  late final _NezDestroyDart _destroy;
  late final _NezLoadRomDart _loadRom;
  late final _NezPowerOnDart _powerOn;
  late final _NezUpdateDart _update;
  late final _NezFramebufferGetDart _framebufferGet;
  late final _NezScreenDimDart _screenWidth;
  late final _NezScreenDimDart _screenHeight;
  late final _NezFramebufferSizeDart _framebufferSize;
  late final _NezAudioQueueDrainDart _audioQueueDrain;
  late final _NezAudioQueueLenDart _audioQueueLen;
  late final _NezInputSetButtonsDart _inputSetButtons;
  late final _NezInputSetButtonDart _inputSetButton;
  late final _NezIsPausedDart _isPaused;
  late final _NezSetPauseDart _setPause;
  late final _NezCpuGetPcDart _cpuGetPc;
  late final _NezCpuGetRegistersDart _cpuGetRegisters;

  bool _loaded = false;

  NezEmulator() {
    _lib = _openLibrary();
    _bindFunctions();
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      // Load from same directory as the executable (app bundle Contents/MacOS/)
      final exeDir = Platform.resolvedExecutable
          .substring(0, Platform.resolvedExecutable.lastIndexOf('/'));
      final bundlePath = '$exeDir/libnez_emu.dylib';
      try {
        return DynamicLibrary.open(bundlePath);
      } catch (_) {}
      // Fallback: zig-out (for development when running from source)
      final locations = [
        'libnez_emu.dylib',
        '${Directory.current.path}/../lib/zig-out/lib/libnez_emu.dylib',
      ];
      for (final path in locations) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {
          continue;
        }
      }
      throw UnsupportedError('Could not find libnez_emu.dylib');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libnez_emu.so');
    }
    throw UnsupportedError('Platform not supported');
  }

  void _bindFunctions() {
    _create = _lib.lookupFunction<_NezCreateC, _NezCreateDart>('nez_create');
    _destroy =
        _lib.lookupFunction<_NezDestroyC, _NezDestroyDart>('nez_destroy');
    _loadRom =
        _lib.lookupFunction<_NezLoadRomC, _NezLoadRomDart>('nez_load_rom');
    _powerOn =
        _lib.lookupFunction<_NezPowerOnC, _NezPowerOnDart>('nez_power_on');
    _update = _lib.lookupFunction<_NezUpdateC, _NezUpdateDart>('nez_update');
    _framebufferGet =
        _lib.lookupFunction<_NezFramebufferGetC, _NezFramebufferGetDart>(
            'nez_framebuffer_get');
    _screenWidth =
        _lib.lookupFunction<_NezScreenDimC, _NezScreenDimDart>(
            'nez_screen_width');
    _screenHeight =
        _lib.lookupFunction<_NezScreenDimC, _NezScreenDimDart>(
            'nez_screen_height');
    _framebufferSize =
        _lib.lookupFunction<_NezFramebufferSizeC, _NezFramebufferSizeDart>(
            'nez_framebuffer_size');
    _audioQueueDrain =
        _lib.lookupFunction<_NezAudioQueueDrainC, _NezAudioQueueDrainDart>(
            'nez_audio_queue_drain');
    _audioQueueLen =
        _lib.lookupFunction<_NezAudioQueueLenC, _NezAudioQueueLenDart>(
            'nez_audio_queue_len');
    _inputSetButtons =
        _lib.lookupFunction<_NezInputSetButtonsC, _NezInputSetButtonsDart>(
            'nez_input_set_buttons');
    _inputSetButton =
        _lib.lookupFunction<_NezInputSetButtonC, _NezInputSetButtonDart>(
            'nez_input_set_button');
    _isPaused =
        _lib.lookupFunction<_NezIsPausedC, _NezIsPausedDart>('nez_is_paused');
    _setPause =
        _lib.lookupFunction<_NezSetPauseC, _NezSetPauseDart>('nez_set_pause');
    _cpuGetPc = _lib.lookupFunction<_NezCpuGetPcC, _NezCpuGetPcDart>(
        'nez_cpu_get_pc');
    _cpuGetRegisters =
        _lib.lookupFunction<_NezCpuGetRegistersC, _NezCpuGetRegistersDart>(
            'nez_cpu_get_registers');
  }

  // ---- Public API ----

  bool get isLoaded => _loaded;
  bool get isRunning => _loaded && _console != nullptr;

  /// Load a ROM file and power on.
  bool loadRom(String romPath) {
    final pathPtr = romPath.toNativeUtf8();
    try {
      _console = _create(pathPtr);
      if (_console == nullptr) {
        _loaded = false;
        return false;
      }
      _loaded = true;
      return true;
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Run emulation for [dtMs] milliseconds worth of CPU cycles.
  int update(int dtMs) {
    if (!isRunning) return 0;
    return _update(_console, dtMs);
  }

  /// Get a pointer to the RGB24 frame buffer (256*240*3 bytes).
  Uint8List? getFrameBuffer() {
    if (!isRunning) return null;
    final ptr = _framebufferGet(_console);
    if (ptr == nullptr) return null;
    return ptr.asTypedList(_framebufferSize());
  }

  int get screenWidth => _screenWidth();
  int get screenHeight => _screenHeight();
  int get framebufferSize => _framebufferSize();

  /// Set all 8 buttons at once as a bitmask.
  /// Bit 0=A, 1=B, 2=Select, 3=Start, 4=Up, 5=Down, 6=Left, 7=Right
  void setButtons(int bitmask) {
    if (!isRunning) return;
    _inputSetButtons(_console, bitmask);
  }

  /// Set a single button state.
  void setButton(int buttonIndex, bool pressed) {
    if (!isRunning) return;
    _inputSetButton(_console, buttonIndex, pressed);
  }

  bool get isPaused {
    if (!isRunning) return true;
    return _isPaused(_console);
  }

  set paused(bool value) {
    if (!isRunning) return;
    _setPause(_console, value);
  }

  /// Drain audio samples into a buffer. Returns number of samples written.
  int drainAudioSamples(Pointer<Int16> outBuffer, int maxSamples) {
    if (!isRunning) return 0;
    return _audioQueueDrain(_console, outBuffer, maxSamples);
  }

  int get audioQueueLength {
    if (!isRunning) return 0;
    return _audioQueueLen(_console);
  }

  int get cpuPc {
    if (!isRunning) return 0;
    return _cpuGetPc(_console);
  }

  CpuRegisters? getCpuRegisters() {
    if (!isRunning) return null;
    return _cpuGetRegisters(_console);
  }

  /// Clean up native resources.
  void dispose() {
    if (_console != nullptr) {
      _destroy(_console);
      _console = nullptr;
      _loaded = false;
    }
  }
}

// Helper: allocate native UTF-8 string (null-terminated)
extension _StringToNative on String {
  Pointer<Uint8> toNativeUtf8() {
    final units = utf8.encode(this);
    final ptr = malloc.allocate<Uint8>(units.length + 1);
    final list = ptr.asTypedList(units.length + 1);
    list.setAll(0, units);
    list[units.length] = 0; // null terminator
    return ptr;
  }
}

/// Access to the system's malloc/free.
final malloc = _Malloc();

class _Malloc {
  Pointer<T> allocate<T extends NativeType>(int byteCount) {
    return _mallocFunc(byteCount).cast();
  }

  void free(Pointer ptr) {
    _freeFunc(ptr);
  }

  static final _mallocFunc = DynamicLibrary.process()
      .lookupFunction<Pointer Function(IntPtr), Pointer Function(int)>(
          'malloc');
  static final _freeFunc = DynamicLibrary.process()
      .lookupFunction<Void Function(Pointer), void Function(Pointer)>('free');
}
