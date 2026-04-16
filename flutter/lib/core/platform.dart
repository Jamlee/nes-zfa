import 'platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    if (dart.library.js_interop) 'platform_web.dart';

/// Platform detection utility for conditional logic across desktop/mobile/web.
class NezPlatform {
  static bool get isWeb => isWebImpl;
  static bool get isDesktop => isDesktopImpl;
  static bool get isMobile => isMobileImpl;
  static bool get isIOS => isIOSImpl;
  static bool get isAndroid => isAndroidImpl;
  static bool get isMacOS => isMacOSImpl;
  static bool get isWindows => isWindowsImpl;
  static bool get isLinux => isLinuxImpl;

  /// Returns a platform string identifier for logging and feature flags.
  static String get name {
    if (isWeb) return 'web';
    if (isMacOS) return 'macos';
    if (isWindows) return 'windows';
    if (isLinux) return 'linux';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    return 'unknown';
  }

  /// Whether FFI-based native emulation is available (not on web).
  static bool get hasNativeEmulation => !isWeb;
}
