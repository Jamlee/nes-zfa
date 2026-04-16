/// Bundled ROM manager — platform-conditional import.
///
/// On web: [BundledRomManager] from [bundled_roms_web.dart] (asset paths only).
/// On native: [BundledRomManager] from [bundled_roms_io.dart] (filesystem copy).

export 'bundled_roms_web.dart'
    if (dart.library.io) 'bundled_roms_io.dart';
