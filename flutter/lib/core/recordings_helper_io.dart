import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

/// Native recordings helper — reads/writes GIF files from filesystem.
class RecordingsHelper {
  /// Load all .gif files from the recordings directory.
  static Future<List<Map<String, dynamic>>> loadRecordings() async {
    String dirPath = _getRecordingsDir();

    // On Android, try getting actual files dir via method channel
    if (NezPlatform.isAndroid) {
      try {
        final appDir = await const MethodChannel('com.nez/storage')
            .invokeMethod<String>('getFilesDir');
        if (appDir != null) {
          dirPath = '$appDir/recordings';
        }
      } catch (_) {}
    }

    final dir = Directory(dirPath);
    final entries = <Map<String, dynamic>>[];
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.gif')) {
          final stat = await entity.stat();
          entries.add({
            'path': entity.path,
            'filename': entity.path.split('/').last,
            'date': stat.modified,
            'sizeBytes': stat.size,
          });
        }
      }
    }
    entries.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return entries;
  }

  /// Delete a recording file.
  static Future<void> deleteRecording(String path) async {
    try {
      await File(path).delete();
    } catch (e) {
      debugPrint('NEZ: failed to delete recording: $e');
    }
  }

  /// Open the folder containing a recording in the system file manager.
  static void openFolder(String filePath) {
    final dir = File(filePath).parent.path;
    if (NezPlatform.isMacOS) {
      Process.run('open', [dir]);
    } else if (NezPlatform.isWindows) {
      Process.run('explorer', [dir]);
    } else if (NezPlatform.isLinux) {
      Process.run('xdg-open', [dir]);
    }
  }

  static String _getRecordingsDir() {
    if (NezPlatform.isAndroid) {
      return '/data/data/com.nez.nez_flutter/files/recordings';
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.nes-zfa/recordings';
  }
}
