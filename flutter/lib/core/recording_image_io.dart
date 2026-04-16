import 'dart:io';

import 'package:flutter/material.dart';

/// Native implementation — renders GIF from filesystem.
Widget recordingImage(String path) => Image.file(
  File(path),
  fit: BoxFit.cover,
  errorBuilder: (_, __, ___) => Container(
    color: const Color(0xFF1A1A2E),
    child: const Icon(Icons.gif_box, color: Color(0xFF4CAF50), size: 22),
  ),
);
