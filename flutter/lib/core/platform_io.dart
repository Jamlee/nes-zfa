import 'dart:io' show Platform;

/// IO (native) platform implementation.
bool get isWebImpl => false;
bool get isDesktopImpl =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;
bool get isMobileImpl =>
    Platform.isAndroid || Platform.isIOS;
bool get isIOSImpl => Platform.isIOS;
bool get isAndroidImpl => Platform.isAndroid;
bool get isMacOSImpl => Platform.isMacOS;
bool get isWindowsImpl => Platform.isWindows;
bool get isLinuxImpl => Platform.isLinux;
