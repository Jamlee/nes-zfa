import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages copying bundled ROM assets to the filesystem on first launch.
class BundledRomManager {
  static const _prefsBundledKey = 'nez_bundled_roms_copied';

  /// List of ROM filenames bundled in the assets/roms/ directory.
  static const List<String> bundledRomFiles = [
    'jackal.nes',
  ];

  /// Ensures bundled ROMs are extracted to the filesystem.
  /// Returns a list of filesystem paths for the bundled ROMs.
  static Future<List<String>> ensureBundledRoms() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyCopied = prefs.getBool(_prefsBundledKey) ?? false;

    final destDir = await _getDestDir();
    final paths = <String>[];

    for (final filename in bundledRomFiles) {
      final destPath = '${destDir.path}/$filename';
      final destFile = File(destPath);

      if (!alreadyCopied || !destFile.existsSync()) {
        try {
          final data = await rootBundle.load('roms/$filename');
          await destDir.create(recursive: true);
          await destFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          debugPrint('NEZ: Copied bundled ROM: $filename -> $destPath');
        } catch (e) {
          debugPrint('NEZ: Failed to copy bundled ROM $filename: $e');
          continue;
        }
      }

      if (destFile.existsSync()) {
        paths.add(destPath);
      }
    }

    if (!alreadyCopied) {
      await prefs.setBool(_prefsBundledKey, true);
    }

    return paths;
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
