import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nez_bindings.dart';
import '../core/nez_engine.dart';
import '../core/theme.dart';
import '../widgets/key_hints.dart';
import '../widgets/nes_display.dart';
import '../widgets/virtual_gamepad.dart';

/// Gameplay screen - shows the NES display and controls.
class GameplayScreen extends StatefulWidget {
  final String romPath;
  final String romName;

  const GameplayScreen({
    super.key,
    required this.romPath,
    required this.romName,
  });

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with SingleTickerProviderStateMixin {
  late final NezEngine _engine;
  bool _showDebug = false;
  bool _loading = true;
  String? _error;

  // Keyboard state tracking for desktop
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    _engine = NezEngine();
    _engine.onFrameReady = () {
      if (mounted) setState(() {});
    };
    _initEmulator();
  }

  Future<void> _initEmulator() async {
    try {
      final success = await _engine.loadRom(widget.romPath);
      if (!success) {
        setState(() {
          _error = 'Failed to load ROM: ${widget.romName}';
          _loading = false;
        });
        return;
      }
      _engine.startLoop(this);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_engine.isRecording) {
      final path = await _engine.stopRecording();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GIF saved: $path')),
        );
      }
    } else {
      _engine.startRecording();
    }
    setState(() {});
  }

  Future<void> _fitWindow() async {
    if (!Platform.isMacOS) return;
    try {
      await const MethodChannel('com.nez/window')
          .invokeMethod('fitToAspectRatio', {'chromeHeight': 80.0});
    } catch (e) {
      debugPrint('NEZ: fitWindow error: $e');
    }
  }

  // ---- Keyboard handling for macOS ----

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;

    if (isDown) {
      _pressedKeys.add(key);
    } else {
      _pressedKeys.remove(key);
    }

    // Game controls
    final mapping = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.keyW: NesButton.up,
      LogicalKeyboardKey.keyS: NesButton.down,
      LogicalKeyboardKey.keyA: NesButton.left,
      LogicalKeyboardKey.keyD: NesButton.right,
      LogicalKeyboardKey.keyJ: NesButton.a,
      LogicalKeyboardKey.keyK: NesButton.b,
      LogicalKeyboardKey.enter: NesButton.start,
      LogicalKeyboardKey.keyX: NesButton.select,
    };

    if (mapping.containsKey(key)) {
      _engine.setButton(mapping[key]!, isDown);
      return KeyEventResult.handled;
    }

    // Turbo
    if (key == LogicalKeyboardKey.keyU) {
      _engine.setTurboA(isDown);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      _engine.setTurboB(isDown);
      return KeyEventResult.handled;
    }

    // System shortcuts
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.space) {
        _engine.togglePause();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD &&
          HardwareKeyboard.instance.isMetaPressed) {
        setState(() => _showDebug = !_showDebug);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : isDesktop
                      ? _buildDesktopLayout()
                      : _buildMobileLayout(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: NezTheme.accentRed),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: NezTheme.textSecondary)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Library'),
          ),
        ],
      ),
    );
  }

  // ---- Desktop Layout ----

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        // Toolbar
        _DesktopToolbar(
          romName: widget.romName,
          isPaused: _engine.isPaused,
          isRecording: _engine.isRecording,
          showDebug: _showDebug,
          onBack: () => Navigator.pop(context),
          onPause: () {
            _engine.togglePause();
            setState(() {});
          },
          onToggleDebug: () => setState(() => _showDebug = !_showDebug),
          onRecord: _toggleRecording,
          onFit: _fitWindow,
        ),
        // Main content
        Expanded(
          child: Row(
            children: [
              // Viewport — fill available space, maintain NES aspect ratio
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 256,
                      height: 240,
                      child: NesDisplay(
                        frame: _engine.currentFrame,
                        fps: _engine.fps,
                      ),
                    ),
                  ),
                ),
              ),
              // Debug panel
              if (_showDebug) _DebugPanel(engine: _engine),
            ],
          ),
        ),
        // Keybindings bar
        const KeybindingsBar(),
      ],
    );
  }

  // ---- Mobile Layout ----

  Widget _buildMobileLayout() {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    if (isLandscape) {
      return _buildMobileLandscape();
    }
    return _buildMobilePortrait();
  }

  Widget _buildMobilePortrait() {
    return Column(
      children: [
        // Top bar
        _MobileTopBar(
          romName: widget.romName,
          isPaused: _engine.isPaused,
          onBack: () => Navigator.pop(context),
          onPause: () => _engine.togglePause(),
        ),
        // NES viewport — fill width, maintain ratio
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 256,
                height: 240,
                child: NesDisplay(
                  frame: _engine.currentFrame,
                  fps: _engine.fps,
                ),
              ),
            ),
          ),
        ),
        // Virtual gamepad
        Flexible(
          flex: 2,
          child: VirtualGamepad(
            onButton: _engine.setButton,
            onTurboA: _engine.setTurboA,
            onTurboB: _engine.setTurboB,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLandscape() {
    return Row(
      children: [
        // Left: D-pad / joystick area
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: VirtualGamepad.joystickOnly(
              onButton: _engine.setButton,
            ),
          ),
        ),
        // Center: Game viewport
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Mini top bar
              SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text('← Back', style: TextStyle(color: NezTheme.accentSecondary, fontSize: 12)),
                    ),
                    const SizedBox(width: 16),
                    Text(widget.romName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              // Viewport
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 256,
                      height: 240,
                      child: NesDisplay(
                        frame: _engine.currentFrame,
                        fps: _engine.fps,
                      ),
                    ),
                  ),
                ),
              ),
              // SELECT / START
              SizedBox(
                height: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MiniSysBtn(label: 'SEL', onPressed: (p) => _engine.setButton(NesButton.select, p)),
                    const SizedBox(width: 16),
                    _MiniSysBtn(label: 'START', onPressed: (p) => _engine.setButton(NesButton.start, p)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Right: Action buttons
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: VirtualGamepad.buttonsOnly(
              onButton: _engine.setButton,
              onTurboA: _engine.setTurboA,
              onTurboB: _engine.setTurboB,
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop toolbar with keybinding hints.
class _DesktopToolbar extends StatelessWidget {
  final String romName;
  final bool isPaused;
  final bool isRecording;
  final bool showDebug;
  final VoidCallback onBack;
  final VoidCallback onPause;
  final VoidCallback onToggleDebug;
  final VoidCallback onRecord;
  final VoidCallback onFit;

  const _DesktopToolbar({
    required this.romName,
    required this.isPaused,
    required this.isRecording,
    required this.showDebug,
    required this.onBack,
    required this.onPause,
    required this.onToggleDebug,
    required this.onRecord,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xF00F0F1A),
        border: Border(bottom: BorderSide(color: NezTheme.border)),
      ),
      child: Row(
        children: [
          _ToolbarBtn(icon: Icons.arrow_back, label: 'Library', kbd: 'Esc', onTap: onBack),
          const SizedBox(width: 8),
          Text(romName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NezTheme.textSecondary)),
          const Spacer(),
          _ToolbarBtn(
            icon: isPaused ? Icons.play_arrow : Icons.pause,
            label: isPaused ? 'Resume' : 'Pause',
            kbd: 'Space',
            onTap: onPause,
          ),
          const SizedBox(width: 6),
          _ToolbarBtn(
            icon: isRecording ? Icons.stop : Icons.fiber_manual_record,
            label: isRecording ? 'Stop' : 'Record',
            onTap: onRecord,
            highlighted: isRecording,
          ),
          const SizedBox(width: 6),
          _ToolbarBtn(icon: Icons.fit_screen, label: 'Fit', onTap: onFit),
          const SizedBox(width: 6),
          _ToolbarBtn(icon: Icons.bug_report, label: 'Debug', kbd: '⌘D', onTap: onToggleDebug, highlighted: showDebug),
        ],
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? kbd;
  final VoidCallback onTap;
  final bool highlighted;

  const _ToolbarBtn({
    required this.icon,
    required this.label,
    this.kbd,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: highlighted ? NezTheme.accentPrimary : NezTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: highlighted ? NezTheme.accentPrimary : NezTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: highlighted ? Colors.white : NezTheme.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: highlighted ? Colors.white : NezTheme.textSecondary,
                ),
              ),
              if (kbd != null) ...[
                const SizedBox(width: 6),
                KeyBadge(kbd!, fontSize: 9),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug panel showing CPU registers, PPU info.
class _DebugPanel extends StatelessWidget {
  final NezEngine engine;

  const _DebugPanel({required this.engine});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D18),
        border: Border(left: BorderSide(color: NezTheme.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('CPU REGISTERS'),
          _regRow('PC', '\$${engine.cpuPc.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
          const Divider(color: NezTheme.border, height: 24),
          _sectionTitle('STATUS'),
          _regRow('Paused', engine.isPaused ? 'YES' : 'NO'),
          _regRow('FPS', '${engine.fps}'),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: NezTheme.accentSecondary,
        ),
      ),
    );
  }

  Widget _regRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: NezTheme.textDim,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: NezTheme.accentCyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  final String romName;
  final bool isPaused;
  final VoidCallback onBack;
  final VoidCallback onPause;

  const _MobileTopBar({
    required this.romName,
    required this.isPaused,
    required this.onBack,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Text('← Back', style: TextStyle(color: NezTheme.accentSecondary, fontSize: 13)),
          ),
          const Spacer(),
          Text(romName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: onPause,
            child: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: NezTheme.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }
}

class _MiniSysBtn extends StatelessWidget {
  final String label;
  final void Function(bool pressed) onPressed;

  const _MiniSysBtn({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressed(true),
      onTapUp: (_) => onPressed(false),
      onTapCancel: () => onPressed(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: NezTheme.bgSurface,
          border: Border.all(color: NezTheme.border),
        ),
        child: Text(label, style: const TextStyle(color: NezTheme.textDim, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
      ),
    );
  }
}
