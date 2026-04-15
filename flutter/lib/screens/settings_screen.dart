import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Settings screen with persistent preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showFps = true;
  bool _soundEnabled = true;
  bool _vibration = true;
  bool _debugMode = false;
  double _volume = 0.8;
  String _aspectRatio = '4:3 Original';
  String _pixelFilter = 'None';
  String _buttonSize = 'Medium';
  double _buttonOpacity = 0.7;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _showFps = _prefs!.getBool('showFps') ?? true;
      _soundEnabled = _prefs!.getBool('soundEnabled') ?? true;
      _vibration = _prefs!.getBool('vibration') ?? true;
      _debugMode = _prefs!.getBool('debugMode') ?? false;
      _volume = _prefs!.getDouble('volume') ?? 0.8;
      _aspectRatio = _prefs!.getString('aspectRatio') ?? '4:3 Original';
      _pixelFilter = _prefs!.getString('pixelFilter') ?? 'None';
      _buttonSize = _prefs!.getString('buttonSize') ?? 'Medium';
      _buttonOpacity = _prefs!.getDouble('buttonOpacity') ?? 0.7;
    });
  }

  void _save(String key, dynamic value) {
    if (_prefs == null) return;
    if (value is bool) _prefs!.setBool(key, value);
    else if (value is double) _prefs!.setDouble(key, value);
    else if (value is String) _prefs!.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: NezTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _SettingsGroup(
              title: 'DISPLAY',
              children: [
                _SettingsDropdown(
                  label: 'Aspect Ratio',
                  value: _aspectRatio,
                  options: const ['4:3 Original', '16:9 Stretch', 'Pixel Perfect'],
                  onChanged: (v) { setState(() => _aspectRatio = v); _save('aspectRatio', v); },
                ),
                _SettingsDropdown(
                  label: 'Pixel Filter',
                  value: _pixelFilter,
                  options: const ['None', 'CRT Scanline', 'LCD Grid'],
                  onChanged: (v) { setState(() => _pixelFilter = v); _save('pixelFilter', v); },
                ),
                _SettingsToggle(
                  label: 'Show FPS',
                  value: _showFps,
                  onChanged: (v) { setState(() => _showFps = v); _save('showFps', v); },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsGroup(
              title: 'AUDIO',
              children: [
                _SettingsToggle(
                  label: 'Sound',
                  value: _soundEnabled,
                  onChanged: (v) { setState(() => _soundEnabled = v); _save('soundEnabled', v); },
                ),
                _SettingsSlider(
                  label: 'Volume',
                  value: _volume,
                  onChanged: (v) { setState(() => _volume = v); _save('volume', v); },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsGroup(
              title: 'CONTROLS',
              children: [
                _SettingsToggle(
                  label: 'Vibration',
                  value: _vibration,
                  onChanged: (v) { setState(() => _vibration = v); _save('vibration', v); },
                ),
                _SettingsDropdown(
                  label: 'Button Size',
                  value: _buttonSize,
                  options: const ['Small', 'Medium', 'Large'],
                  onChanged: (v) { setState(() => _buttonSize = v); _save('buttonSize', v); },
                ),
                _SettingsSlider(
                  label: 'Button Opacity',
                  value: _buttonOpacity,
                  onChanged: (v) { setState(() => _buttonOpacity = v); _save('buttonOpacity', v); },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsGroup(
              title: 'ADVANCED',
              children: [
                _SettingsToggle(
                  label: 'Debug Mode',
                  value: _debugMode,
                  onChanged: (v) { setState(() => _debugMode = v); _save('debugMode', v); },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'NEZ-ZFA v0.1.0 • Zig + Flutter',
                style: TextStyle(
                  fontSize: 12,
                  color: NezTheme.textDim.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NezTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NezTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: NezTheme.textDim,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: NezTheme.textPrimary)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: NezTheme.accentPrimary,
          ),
        ],
      ),
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: NezTheme.textPrimary)),
          GestureDetector(
            onTap: () => _showPicker(context),
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: NezTheme.textDim),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NezTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...options.map((opt) => ListTile(
                  title: Text(opt),
                  trailing: opt == value
                      ? const Icon(Icons.check, color: NezTheme.accentPrimary)
                      : null,
                  onTap: () {
                    onChanged(opt);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SettingsSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SettingsSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: NezTheme.textPrimary)),
          const Spacer(),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(fontSize: 12, color: NezTheme.textDim),
          ),
          SizedBox(
            width: 120,
            child: Slider(
              value: value,
              onChanged: onChanged,
              activeColor: NezTheme.accentPrimary,
              inactiveColor: NezTheme.bgElevated,
            ),
          ),
        ],
      ),
    );
  }
}
