import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/nez_engine_stub.dart' if (dart.library.io) '../core/nez_engine_native.dart';
import '../core/nez_bindings_stub.dart' if (dart.library.io) '../core/nez_bindings_native.dart';
import '../core/gamepad_server_stub.dart' if (dart.library.io) '../core/gamepad_server_native.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../widgets/nes_display.dart';
import '../widgets/key_hints.dart';
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
  late final GamepadServer _gamepadServer;
  bool _showDebug = false;
  bool _showControllers = false;
  bool _loading = true;
  String? _error;

  // Keyboard state tracking for desktop
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    _engine = NezEngine();
    _gamepadServer = GamepadServer(_engine);
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
      _gamepadServer.start(); // Auto-start web gamepad server
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
    _gamepadServer.stop();
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
      _engine.startRecording(widget.romName);
    }
    setState(() {});
  }

  Future<void> _fitWindow() async {
    if (kIsWeb || !NezPlatform.isMacOS) return;
    try {
      await const MethodChannel('com.nez/window')
          .invokeMethod('fitToAspectRatio', {'chromeHeight': 80.0});
    } catch (e) {
      debugPrint('NEZ: fitWindow error: $e');
    }
  }

  // ---- Keyboard handling for macOS ----

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (kIsWeb || (!NezPlatform.isMacOS && !NezPlatform.isLinux && !NezPlatform.isWindows)) {
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
    final isDesktop = !kIsWeb && (NezPlatform.isDesktop || MediaQuery.of(context).size.width > 800);

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
          Icon(Icons.error_outline, size: 48, color: NezTheme.accentRed),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: NezTheme.textSecondary)),
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
    return Stack(
      children: [
        Column(
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
              onControllers: _toggleControllers,
              showControllers: _showControllers,
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
        KeybindingsBar(),
      ],
    ),
    // QR overlay
    if (_showControllers) _buildQrOverlay(),
    ],
    );
  }

  void _toggleControllers() async {
    if (!_gamepadServer.isRunning) {
      await _gamepadServer.start();
    }
    setState(() => _showControllers = !_showControllers);
  }

  Widget _buildQrOverlay() {
    final isDesktop = !kIsWeb && NezPlatform.isDesktop;
    final p1Url = isDesktop ? _gamepadServer.p1Url : _gamepadServer.p1MirrorUrl;
    final p2Url = isDesktop ? _gamepadServer.p2Url : _gamepadServer.p2MirrorUrl;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showControllers = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NezTheme.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Scan to Connect Controller',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _gamepadServer.localIp ?? '',
                    style: TextStyle(fontSize: 11, color: NezTheme.textDim),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QrCard(label: 'Player 1', url: p1Url, color: NezTheme.accentPrimary),
                      const SizedBox(width: 24),
                      _QrCard(label: 'Player 2', url: p2Url, color: NezTheme.accentSecondary),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isDesktop ? 'Gamepad only' : 'Gamepad + mirrored display',
                    style: TextStyle(fontSize: 10, color: NezTheme.textDim),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    return Stack(
      children: [
        Column(
          children: [
            // Top bar
            _MobileTopBar(
              romName: widget.romName,
              isPaused: _engine.isPaused,
              isRecording: _engine.isRecording,
              onBack: () => Navigator.pop(context),
              onPause: () => _engine.togglePause(),
              onControllers: _toggleControllers,
              onRecord: _toggleRecording,
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
    ),
    if (_showControllers) _buildQrOverlay(),
    ],
    );
  }

  Widget _buildMobileLandscape() {
    return Stack(
      children: [
        // Game viewport — fullscreen behind everything
        Positioned.fill(
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
        // Transparent controls overlay
        Positioned.fill(
          child: Row(
            children: [
              // Left: D-pad / joystick
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: VirtualGamepad.joystickOnly(
                    onButton: _engine.setButton,
                  ),
                ),
              ),
              // Center spacer with mini top bar + system buttons
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
                            child: Text('← Back', style: TextStyle(color: NezTheme.accentSecondary, fontSize: 12, shadows: [Shadow(blurRadius: 4)])),
                          ),
                          const SizedBox(width: 12),
                          Text(widget.romName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 4)])),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _toggleControllers,
                            child: Icon(Icons.qr_code, size: 18, color: _showControllers ? NezTheme.accentPrimary : NezTheme.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _toggleRecording,
                            child: Icon(Icons.fiber_manual_record, size: 18, color: _engine.isRecording ? NezTheme.accentRed : NezTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // SELECT / START at bottom center
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
                    const SizedBox(height: 4),
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
          ),
        ),
        // QR overlay (if showing)
        if (_showControllers) _buildQrOverlay(),
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
  final bool showControllers;
  final VoidCallback onBack;
  final VoidCallback onPause;
  final VoidCallback onToggleDebug;
  final VoidCallback onRecord;
  final VoidCallback onFit;
  final VoidCallback onControllers;

  const _DesktopToolbar({
    required this.romName,
    required this.isPaused,
    required this.isRecording,
    required this.showDebug,
    required this.showControllers,
    required this.onBack,
    required this.onPause,
    required this.onToggleDebug,
    required this.onRecord,
    required this.onFit,
    required this.onControllers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xF00F0F1A),
        border: Border(bottom: BorderSide(color: NezTheme.border)),
      ),
      child: Row(
        children: [
          _ToolbarBtn(icon: Icons.arrow_back, label: 'Library', kbd: 'Esc', onTap: onBack),
          const SizedBox(width: 8),
          Text(romName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NezTheme.textSecondary)),
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
          _ToolbarBtn(icon: Icons.qr_code, label: 'Controllers', onTap: onControllers, highlighted: showControllers),
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
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D18),
        border: Border(left: BorderSide(color: NezTheme.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('CPU REGISTERS'),
          _regRow('PC', '\$${engine.cpuPc.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
          Divider(color: NezTheme.border, height: 24),
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
        style: TextStyle(
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
  final bool isRecording;
  final VoidCallback onBack;
  final VoidCallback onPause;
  final VoidCallback? onControllers;
  final VoidCallback? onRecord;

  const _MobileTopBar({
    required this.romName,
    required this.isPaused,
    this.isRecording = false,
    required this.onBack,
    required this.onPause,
    this.onControllers,
    this.onRecord,
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
            child: Text('← Back', style: TextStyle(color: NezTheme.accentSecondary, fontSize: 13)),
          ),
          const Spacer(),
          Text(romName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (onRecord != null) ...[
            GestureDetector(
              onTap: onRecord,
              child: Icon(
                Icons.fiber_manual_record,
                color: isRecording ? NezTheme.accentRed : NezTheme.textSecondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (onControllers != null) ...[
            GestureDetector(
              onTap: onControllers,
              child: Icon(Icons.qr_code, color: NezTheme.textSecondary, size: 18),
            ),
            const SizedBox(width: 12),
          ],
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
        child: Text(label, style: TextStyle(color: NezTheme.textDim, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String label;
  final String url;
  final Color color;

  const _QrCard({required this.label, required this.url, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: QrImageView(
            data: url,
            version: QrVersions.auto,
            size: 160,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          url,
          style: TextStyle(fontSize: 9, color: NezTheme.textDim, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
