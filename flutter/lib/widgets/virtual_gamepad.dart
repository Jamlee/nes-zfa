import 'dart:math';

import 'package:flutter/material.dart';

import '../core/nez_bindings.dart';
import '../core/theme.dart';

/// Callback for button state changes.
typedef ButtonCallback = void Function(int button, bool pressed);
typedef TurboCallback = void Function(bool active);

/// Virtual gamepad overlay for mobile gameplay.
class VirtualGamepad extends StatelessWidget {
  final ButtonCallback onButton;
  final TurboCallback onTurboA;
  final TurboCallback onTurboB;

  const VirtualGamepad({
    super.key,
    required this.onButton,
    required this.onTurboA,
    required this.onTurboB,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // D-Pad + Action buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Joystick(onDirection: onButton),
              _ActionButtons(
                onButton: onButton,
                onTurboA: onTurboA,
                onTurboB: onTurboB,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // System buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SystemButton(
                label: 'SELECT',
                onPressed: (p) => onButton(NesButton.select, p),
              ),
              const SizedBox(width: 24),
              _SystemButton(
                label: 'START',
                onPressed: (p) => onButton(NesButton.start, p),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Virtual joystick that maps to NES D-Pad.
class _Joystick extends StatefulWidget {
  final ButtonCallback onDirection;

  const _Joystick({required this.onDirection});

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  Offset _thumbPosition = Offset.zero;
  bool _isDragging = false;
  static const double _size = 120;
  static const double _thumbSize = 50;
  static const double _deadZone = 0.25;

  // Track which directions are currently active
  bool _up = false, _down = false, _left = false, _right = false;

  void _updateDirection(Offset localPos) {
    final center = const Offset(_size / 2, _size / 2);
    var delta = localPos - center;
    final distance = delta.distance;
    final maxDist = (_size - _thumbSize) / 2;

    if (distance > maxDist) {
      delta = delta / distance * maxDist;
    }

    setState(() {
      _thumbPosition = delta;
    });

    final norm = distance / maxDist;
    final angle = atan2(delta.dy, delta.dx);

    final newUp = norm > _deadZone && angle < -pi / 6 && angle > -5 * pi / 6;
    final newDown = norm > _deadZone && angle > pi / 6 && angle < 5 * pi / 6;
    final newLeft =
        norm > _deadZone && (angle > 2 * pi / 3 || angle < -2 * pi / 3);
    final newRight = norm > _deadZone && angle > -pi / 3 && angle < pi / 3;

    if (newUp != _up) widget.onDirection(NesButton.up, newUp);
    if (newDown != _down) widget.onDirection(NesButton.down, newDown);
    if (newLeft != _left) widget.onDirection(NesButton.left, newLeft);
    if (newRight != _right) widget.onDirection(NesButton.right, newRight);

    _up = newUp;
    _down = newDown;
    _left = newLeft;
    _right = newRight;
  }

  void _resetJoystick() {
    setState(() {
      _thumbPosition = Offset.zero;
      _isDragging = false;
    });
    if (_up) widget.onDirection(NesButton.up, false);
    if (_down) widget.onDirection(NesButton.down, false);
    if (_left) widget.onDirection(NesButton.left, false);
    if (_right) widget.onDirection(NesButton.right, false);
    _up = _down = _left = _right = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) {
        _isDragging = true;
        _updateDirection(d.localPosition);
      },
      onPanUpdate: (d) => _updateDirection(d.localPosition),
      onPanEnd: (_) => _resetJoystick(),
      onPanCancel: _resetJoystick,
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _JoystickPainter(
            thumbOffset: _thumbPosition,
            isDragging: _isDragging,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset thumbOffset;
  final bool isDragging;

  _JoystickPainter({required this.thumbOffset, required this.isDragging});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Base circle
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()
        ..color = NezTheme.bgSurface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()
        ..color = NezTheme.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Direction indicators
    final indicatorPaint = Paint()
      ..color = NezTheme.textDim.withOpacity(0.15);
    const indicatorSize = 6.0;
    final r = size.width / 2 - 10;
    for (final angle in [0.0, pi / 2, pi, 3 * pi / 2]) {
      canvas.drawCircle(
        center + Offset(cos(angle) * r, sin(angle) * r),
        indicatorSize,
        indicatorPaint,
      );
    }

    // Thumb
    final thumbCenter = center + thumbOffset;
    // Shadow
    canvas.drawCircle(
      thumbCenter + const Offset(0, 2),
      25,
      Paint()..color = Colors.black.withOpacity(0.4),
    );
    // Gradient
    canvas.drawCircle(
      thumbCenter,
      25,
      Paint()
        ..shader = RadialGradient(
          colors: [
            isDragging ? NezTheme.accentPrimary.withOpacity(0.5) : const Color(0xFF444466),
            const Color(0xFF2A2A44),
          ],
        ).createShader(Rect.fromCircle(center: thumbCenter, radius: 25)),
    );
    // Border
    canvas.drawCircle(
      thumbCenter,
      25,
      Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Highlight
    canvas.drawCircle(
      thumbCenter + const Offset(-5, -6),
      7,
      Paint()..color = Colors.white.withOpacity(0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.thumbOffset != thumbOffset || old.isDragging != isDragging;
}

/// A/B and Turbo A/B buttons in 2x2 grid.
class _ActionButtons extends StatelessWidget {
  final ButtonCallback onButton;
  final TurboCallback onTurboA;
  final TurboCallback onTurboB;

  const _ActionButtons({
    required this.onButton,
    required this.onTurboA,
    required this.onTurboB,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Turbo row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TurboButton(
                label: 'B',
                color: NezTheme.accentRed,
                onChanged: (p) => onTurboB(p),
              ),
              const SizedBox(width: 14),
              _TurboButton(
                label: 'A',
                color: NezTheme.accentPrimary,
                onChanged: (p) => onTurboA(p),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Main A/B row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                label: 'B',
                color: NezTheme.accentRed,
                onPressed: (p) => onButton(NesButton.b, p),
              ),
              const SizedBox(width: 14),
              _ActionButton(
                label: 'A',
                color: NezTheme.accentPrimary,
                onPressed: (p) => onButton(NesButton.a, p),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Main A/B action button.
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final void Function(bool pressed) onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressed(true),
      onTapUp: (_) => onPressed(false),
      onTapCancel: () => onPressed(false),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Turbo A/B button (outline style).
class _TurboButton extends StatefulWidget {
  final String label;
  final Color color;
  final void Function(bool active) onChanged;

  const _TurboButton({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_TurboButton> createState() => _TurboButtonState();
}

class _TurboButtonState extends State<_TurboButton> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? widget.color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: widget.color, width: 2),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'TURBO',
              style: TextStyle(
                color: widget.color,
                fontSize: 6,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// System button (SELECT / START).
class _SystemButton extends StatelessWidget {
  final String label;
  final void Function(bool pressed) onPressed;

  const _SystemButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressed(true),
      onTapUp: (_) => onPressed(false),
      onTapCancel: () => onPressed(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: NezTheme.bgSurface,
          border: Border.all(color: NezTheme.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: NezTheme.textDim,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
