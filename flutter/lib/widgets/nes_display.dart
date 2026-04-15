import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Widget that renders the NES frame buffer.
class NesDisplay extends StatelessWidget {
  final ui.Image? frame;
  final int fps;
  final bool showFps;

  const NesDisplay({
    super.key,
    required this.frame,
    this.fps = 0,
    this.showFps = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (frame != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _NesPainter(frame!),
                  isComplex: true,
                  willChange: true,
                ),
              )
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videogame_asset, size: 48, color: NezTheme.textDim),
                    SizedBox(height: 8),
                    Text(
                      'NES 256 × 240',
                      style: TextStyle(
                        color: NezTheme.textDim,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (showFps)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$fps FPS',
                    style: const TextStyle(
                      color: NezTheme.accentGreen,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NesPainter extends CustomPainter {
  final ui.Image image;

  _NesPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _NesPainter old) => true;
}
