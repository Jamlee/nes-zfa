import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web implementation of BundledRomManager — returns asset paths for bundled ROMs.
/// No filesystem access needed on web; ROMs are served from Flutter assets.

class BundledRomManager {
  static const _prefsBundledKey = 'nez_bundled_roms_copied_v4';

  static Future<List<String>> ensureBundledRoms() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyCopied = prefs.getBool(_prefsBundledKey) ?? false;

    final romAssets = await _discoverRomAssets();
    debugPrint('NEZ: Found ${romAssets.length} bundled ROM assets');

    if (!alreadyCopied && romAssets.isNotEmpty) {
      await prefs.setBool(_prefsBundledKey, true);
    }

    return romAssets;
  }

  /// Discover .nes ROM assets.
  /// Tries multiple strategies for compatibility across Flutter versions.
  static Future<List<String>> _discoverRomAssets() async {
    // Strategy 1: Try standard AssetManifest.json
    try {
      final jsonStr = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(jsonStr);
      final roms = _extractNesRoms(manifest);
      if (roms.isNotEmpty) {
        debugPrint('NEZ: Found ROMs via AssetManifest.json');
        return roms;
      }
    } catch (e) {
      debugPrint('NEZ: AssetManifest.json not available: $e');
    }

    // Strategy 2: Try AssetManifest.bin (Flutter 3.22+)
    try {
      final byteData = await rootBundle.load('AssetManifest.bin');
      // Binary manifest — skip, fall through to strategy 3
      debugPrint('NEZ: AssetManifest.bin exists but format unsupported, trying fallback');
    } catch (_) {}

    // Strategy 3: Direct probe — try loading common ROM names from assets
    debugPrint('NEZ: Falling back to direct asset probing');
    return await _probeRomAssets();
  }

  /// Extract .nes paths from a manifest map.
  static List<String> _extractNesRoms(Map<String, dynamic> manifest) {
    return manifest.keys
        .where((k) => k.startsWith('roms/') && k.toLowerCase().endsWith('.nes'))
        .toList();
  }

  /// Fallback: probe for .nes files by attempting to load them.
  /// Checks a list of well-known NES ROM filenames plus any in roms/.
  static Future<List<String>> _probeRomAssets() async {
    final found = <String>[];

    // First, try loading the AssetManifest with the 'assets/' prefix (some Flutter versions)
    for (final prefix in ['', 'assets/']) {
      try {
        final jsonStr = await rootBundle.loadString('${prefix}AssetManifest.json');
        final Map<String, dynamic> manifest = json.decode(jsonStr);
        final roms = _extractNesRoms(manifest);
        if (roms.isNotEmpty) return roms;
      } catch (_) {}
    }

    // Last resort: try known ROM filenames
    final candidates = [
      'roms/contra.nes',
      'roms/smb.nes',
      'roms/mario.nes',
      'roms/zelda.nes',
      'roms/drmario.nes',
      'roms/tetris.nes',
      'roms/megaman.nes',
      'roms/castlevania.nes',
    ];

    for (final candidate in candidates) {
      try {
        // Just check if the asset exists by loading first few bytes
        await rootBundle.load(candidate);
        found.add(candidate);
        debugPrint('NEZ: Probed and found: $candidate');
      } catch (_) {
        // Asset doesn't exist, skip
      }
    }

    return found;
  }
}
