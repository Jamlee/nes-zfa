import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages copying bundled ROM assets to the filesystem on first launch.
class BundledRomManager {
  static const _prefsBundledKey = 'nez_bundled_roms_copied_v3';

  /// Discover and copy all .nes files from assets/roms/ directory.
  static Future<List<String>> ensureBundledRoms() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyCopied = prefs.getBool(_prefsBundledKey) ?? false;

    final destDir = await _getDestDir();
    final paths = <String>[];

    // Get ROM assets from manifest
    final romAssets = await _discoverRomAssets();
    debugPrint('NEZ: Found ${romAssets.length} bundled ROM assets');

    for (final assetPath in romAssets) {
      final filename = assetPath.split('/').last;
      final destPath = '${destDir.path}/$filename';
      final destFile = File(destPath);

      if (!alreadyCopied || !destFile.existsSync()) {
        try {
          final data = await rootBundle.load(assetPath);
          await destDir.create(recursive: true);
          await destFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          debugPrint('NEZ: Copied bundled ROM: $filename');
        } catch (e) {
          debugPrint('NEZ: Failed to copy bundled ROM $filename: $e');
          continue;
        }
      }

      if (destFile.existsSync()) {
        paths.add(destPath);
      }
    }

    if (!alreadyCopied && romAssets.isNotEmpty) {
      await prefs.setBool(_prefsBundledKey, true);
    }

    return paths;
  }

  /// Discover .nes assets using AssetManifest.json
  static Future<List<String>> _discoverRomAssets() async {
    try {
      // Load the JSON manifest (works on all Flutter versions)
      final jsonStr = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(jsonStr);
      return manifest.keys
          .where((k) => k.startsWith('roms/') && k.toLowerCase().endsWith('.nes'))
          .toList();
    } catch (e) {
      debugPrint('NEZ: AssetManifest.json error: $e');
    }

    // Fallback: try the binary manifest
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets()
          .where((a) => a.startsWith('roms/') && a.toLowerCase().endsWith('.nes'))
          .toList();
    } catch (e) {
      debugPrint('NEZ: AssetManifest.bin error: $e');
    }

    return [];
  }

  static Future<Directory> _getDestDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      return Directory('${appDir.path}/bundled_roms');
    } else {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      return Directory('$home/.nes-zfa/bundled_roms');
    }
  }
}
