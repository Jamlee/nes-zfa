import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import 'gameplay_screen.dart';

/// ROM metadata for the library list.
class RomEntry {
  final String name;
  final String path;
  final int sizeKB;
  final String mapper;
  final Color color;
  final IconData icon;
  DateTime lastPlayed;
  bool exists;

  RomEntry({
    required this.name,
    required this.path,
    required this.sizeKB,
    this.mapper = 'Unknown',
    this.color = NezTheme.accentPrimary,
    this.icon = Icons.videogame_asset,
    DateTime? lastPlayed,
    this.exists = true,
  }) : lastPlayed = lastPlayed ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'sizeKB': sizeKB,
        'mapper': mapper,
        'colorValue': color.toARGB32(),
        'lastPlayed': lastPlayed.toIso8601String(),
      };

  factory RomEntry.fromJson(Map<String, dynamic> json, int index) {
    return RomEntry(
      name: json['name'] ?? 'Unknown',
      path: json['path'] ?? '',
      sizeKB: json['sizeKB'] ?? 0,
      mapper: json['mapper'] ?? 'Unknown',
      color: json['colorValue'] != null
          ? Color(json['colorValue'])
          : _colorForIndex(index),
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.tryParse(json['lastPlayed']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static Color _colorForIndex(int i) {
    const colors = [
      Color(0xFFE74C3C),
      Color(0xFFF39C12),
      Color(0xFF3498DB),
      Color(0xFF2ECC71),
      Color(0xFF9B59B6),
      Color(0xFF1ABC9C),
      Color(0xFFE91E63),
      Color(0xFF607D8B),
    ];
    return colors[i % colors.length];
  }
}

/// Game library screen (home).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<RomEntry> _roms = [];
  String _searchQuery = '';
  bool _initialized = false;

  static const _prefsKey = 'nez_rom_library';

  @override
  void initState() {
    super.initState();
    _loadSavedRoms();
  }

  /// Load saved ROM list from shared_preferences and check file existence.
  Future<void> _loadSavedRoms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        final entries = <RomEntry>[];
        for (int i = 0; i < list.length; i++) {
          final entry = RomEntry.fromJson(list[i], i);
          // Check if file still exists
          entry.exists = await File(entry.path).exists();
          entries.add(entry);
        }
        setState(() {
          _roms.addAll(entries);
        });
      } catch (_) {
        // Corrupted data, ignore
      }
    }
    setState(() => _initialized = true);
  }

  /// Save ROM list to shared_preferences.
  Future<void> _saveRoms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_roms.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);
  }

  List<RomEntry> get _filteredRoms => _searchQuery.isEmpty
      ? _roms
      : _roms
          .where((r) =>
              r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();

  Future<void> _addRom() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select NES ROM',
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.nes')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a .nes file')),
          );
        }
        return;
      }
      // Don't add duplicates
      if (_roms.any((r) => r.path == path)) {
        _launchGame(_roms.firstWhere((r) => r.path == path));
        return;
      }
      final file = File(path);
      final name = path.split('/').last.replaceAll('.nes', '');
      final size = await file.length();
      final entry = RomEntry(
        name: name,
        path: path,
        sizeKB: size ~/ 1024,
        color: RomEntry._colorForIndex(_roms.length),
        icon: Icons.videogame_asset,
      );
      setState(() {
        _roms.add(entry);
      });
      _saveRoms();
    } catch (e) {
      debugPrint('NEZ: file picker error: $e');
    }
  }

  void _removeRom(RomEntry rom) {
    setState(() {
      _roms.remove(rom);
    });
    _saveRoms();
  }

  void _launchGame(RomEntry rom) {
    rom.lastPlayed = DateTime.now();
    _saveRoms();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameplayScreen(romPath: rom.path, romName: rom.name),
      ),
    );
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
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [NezTheme.accentPrimary, NezTheme.accentSecondary],
                    ).createShader(bounds),
                    child: const Text(
                      'Nez',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _IconBtn(
                    icon: Icons.add,
                    onTap: _addRom,
                    tooltip: isDesktop ? '⌘O' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  prefixIcon:
                      const Icon(Icons.search, size: 20, color: NezTheme.textDim),
                  hintText: 'Search ROMs...',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixIcon: isDesktop
                      ? const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: _KBD('⌘F'),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: !_initialized
                  ? const Center(child: CircularProgressIndicator())
                  : _roms.isEmpty
                      ? _buildEmptyState()
                      : _buildRomList(isDesktop),
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
          Icon(Icons.folder_open, size: 64, color: NezTheme.textDim.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'No ROMs loaded',
            style: TextStyle(color: NezTheme.textDim, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _addRom,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add ROM'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NezTheme.accentPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRomList(bool isDesktop) {
    final roms = _filteredRoms;
    if (isDesktop) {
      return _buildGridView(roms);
    }
    return _buildListView(roms);
  }

  Widget _buildGridView(List<RomEntry> roms) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: roms.length,
      itemBuilder: (ctx, i) => _GameCard(
        rom: roms[i],
        onTap: () => _launchGame(roms[i]),
        onRemove: () => _removeRom(roms[i]),
      ),
    );
  }

  Widget _buildListView(List<RomEntry> roms) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: roms.length,
      itemBuilder: (ctx, i) => _GameListTile(
        rom: roms[i],
        onTap: () => _launchGame(roms[i]),
        onRemove: () => _removeRom(roms[i]),
      ),
    );
  }
}

/// Game card for desktop grid view.
class _GameCard extends StatelessWidget {
  final RomEntry rom;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _GameCard({required this.rom, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: rom.exists ? onTap : null,
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: rom.exists ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: rom.exists ? 1.0 : 0.4,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [rom.color, rom.color.withValues(alpha: 0.7)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(child: Icon(rom.icon, size: 36, color: Colors.white.withValues(alpha: 0.9))),
                        if (!rom.exists)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Missing',
                                style: TextStyle(color: NezTheme.accentRed, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rom.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NezTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${rom.sizeKB} KB',
                          style: const TextStyle(
                            fontSize: 10,
                            color: NezTheme.textDim,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          rom.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 8,
                            color: NezTheme.textDim,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          onTap: onRemove,
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: NezTheme.accentRed),
              SizedBox(width: 8),
              Text('Remove', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Game list tile for mobile.
class _GameListTile extends StatelessWidget {
  final RomEntry rom;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _GameListTile({required this.rom, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: Key(rom.path),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
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
          onTap: rom.exists ? onTap : null,
          child: Opacity(
            opacity: rom.exists ? 1.0 : 0.4,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NezTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NezTheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [rom.color, rom.color.withValues(alpha: 0.7)],
                      ),
                    ),
                    child: Icon(rom.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rom.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: NezTheme.textPrimary,
                          ),
                        ),
                        Text(
                          rom.exists
                              ? '${rom.sizeKB} KB'
                              : 'File missing',
                          style: TextStyle(
                            fontSize: 11,
                            color: rom.exists ? NezTheme.textDim : NezTheme.accentRed,
                          ),
                        ),
                        Text(
                          rom.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: NezTheme.textDim,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rom.exists)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: NezTheme.accentPrimary,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _IconBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: NezTheme.bgSurface,
          ),
          child: Icon(icon, size: 18, color: NezTheme.textSecondary),
        ),
      ),
    );
  }
}

class _KBD extends StatelessWidget {
  final String text;
  const _KBD(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: NezTheme.textDim,
          ),
        ),
      ),
    );
  }
}
