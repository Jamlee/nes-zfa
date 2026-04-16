import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/platform.dart';
import '../core/recording_image.dart';
import '../core/recordings_helper.dart';
import '../core/theme.dart';

/// Entry representing a recorded GIF file.
class RecordingEntry {
  final String path;
  final String filename;
  final DateTime date;
  final int sizeBytes;

  RecordingEntry({
    required this.path,
    required this.filename,
    required this.date,
    required this.sizeBytes,
  });

  /// Game name extracted from file name.
  /// Convention: nez_{gameName}_{timestamp}.gif
  /// Falls back to file name for old format.
  String get gameName {
    final name = filename.replaceAll(RegExp(r'\.gif$'), '');
    if (name.startsWith('nez_')) {
      final rest = name.substring(4);
      final lastUnderscore = rest.lastIndexOf('_');
      if (lastUnderscore > 0) {
        final afterUnderscore = rest.substring(lastUnderscore + 1);
        if (afterUnderscore.length >= 13 && int.tryParse(afterUnderscore) != null) {
          final gamePart = rest.substring(0, lastUnderscore);
          if (gamePart.isNotEmpty) return gamePart.replaceAll('_', ' ');
        }
      }
    }
    return name;
  }

  String get sizeText {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get dateText {
    final d = date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Recordings management screen.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<RecordingEntry> _recordings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    try {
      final entries = await RecordingsHelper.loadRecordings();
      setState(() {
        _recordings = entries.map((e) => RecordingEntry(
          path: e['path'] as String,
          filename: e['filename'] as String,
          date: e['date'] as DateTime,
          sizeBytes: e['sizeBytes'] as int,
        )).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('NEZ: failed to load recordings: $e');
      setState(() { _loading = false; });
    }
  }

  Future<void> _deleteRecording(RecordingEntry entry) async {
    await RecordingsHelper.deleteRecording(entry.path);
    setState(() => _recordings.remove(entry));
  }

  void _copyPath(RecordingEntry entry) {
    // Use clipboard via dart:html on web, or platform channel on native
    // For now just show the path
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Path: ${entry.path}')),
    );
  }

  void _openFolder(RecordingEntry entry) {
    RecordingsHelper.openFolder(entry.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Recordings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: NezTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadRecordings,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: NezTheme.bgSurface,
                      ),
                      child: const Icon(Icons.refresh, size: 18, color: NezTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _recordings.isEmpty
                      ? _buildEmptyState()
                      : isDesktop
                          ? _buildDesktopGrid()
                          : _buildMobileList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off, size: 64, color: NezTheme.textDim.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'No recordings yet',
            style: TextStyle(color: NezTheme.textDim, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Record gameplay using the toolbar button',
            style: TextStyle(color: NezTheme.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _recordings.length,
      itemBuilder: (ctx, i) => _RecordingCard(
        entry: _recordings[i],
        onCopyPath: () => _copyPath(_recordings[i]),
        onOpenFolder: () => _openFolder(_recordings[i]),
        onDelete: () => _deleteRecording(_recordings[i]),
        onPreview: () => _previewGif(_recordings[i]),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _recordings.length,
      itemBuilder: (ctx, i) {
        final entry = _recordings[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Dismissible(
            key: Key(entry.path),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _deleteRecording(entry),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: NezTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline, color: NezTheme.accentRed),
            ),
            child: GestureDetector(
              onTap: () => _previewGif(entry),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NezTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NezTheme.border),
                ),
                child: Row(
                  children: [
                    // GIF thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 60,
                        height: 56,
                        child: SizedBox(
                          width: 60,
                          height: 56,
                          child: recordingImage(entry.path),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.gameName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: NezTheme.textPrimary,
                            ),
                          ),
                          Text(
                            '${entry.dateText}  ${entry.sizeText}',
                            style: const TextStyle(fontSize: 11, color: NezTheme.textDim),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: NezTheme.textSecondary),
                      onPressed: () => _copyPath(entry),
                      tooltip: 'Copy path',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _previewGif(RecordingEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 512, maxHeight: 512),
            decoration: BoxDecoration(
              color: NezTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NezTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: recordingImage(entry.path),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.gameName}  •  ${entry.sizeText}',
                          style: const TextStyle(fontSize: 11, color: NezTheme.textDim),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _copyPath(entry),
                        child: const Icon(Icons.copy, size: 16, color: NezTheme.textSecondary),
                      ),
                      if (!kIsWeb && (NezPlatform.isMacOS || NezPlatform.isWindows || NezPlatform.isLinux)) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _openFolder(entry),
                          child: const Icon(Icons.folder_open, size: 16, color: NezTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop grid card for a recording.
class _RecordingCard extends StatelessWidget {
  final RecordingEntry entry;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _RecordingCard({
    required this.entry,
    required this.onCopyPath,
    required this.onOpenFolder,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPreview,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail area
          Expanded(
            flex: 3,
            child: Container(
              color: NezTheme.bgSurface,
              child: recordingImage(entry.path),
            ),
          ),
          // Info + actions
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.gameName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NezTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.dateText}  ${entry.sizeText}',
                    style: const TextStyle(fontSize: 10, color: NezTheme.textDim),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniAction(icon: Icons.copy, tooltip: 'Copy path', onTap: onCopyPath),
                      const SizedBox(width: 4),
                      _MiniAction(icon: Icons.folder_open, tooltip: 'Open folder', onTap: onOpenFolder),
                      const SizedBox(width: 4),
                      _MiniAction(icon: Icons.delete_outline, tooltip: 'Delete', onTap: onDelete, color: NezTheme.accentRed),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = NezTheme.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: NezTheme.bgSurface,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}
