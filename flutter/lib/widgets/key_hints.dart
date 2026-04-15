import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Keyboard shortcut hint badge (styled like a keycap).
class KeyBadge extends StatelessWidget {
  final String label;
  final double fontSize;

  const KeyBadge(this.label, {super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.12)),
          left: BorderSide(color: Colors.white.withOpacity(0.12)),
          right: BorderSide(color: Colors.white.withOpacity(0.12)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.12), width: 2),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: NezTheme.textDim,
          height: 1.2,
        ),
      ),
    );
  }
}

/// A row showing a keybinding: [KeyBadge] + label text.
class KeybindItem extends StatelessWidget {
  final List<String> keys;
  final String label;

  const KeybindItem({super.key, required this.keys, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...keys.map((k) => Padding(
              padding: const EdgeInsets.only(right: 3),
              child: KeyBadge(k),
            )),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: NezTheme.textDim),
        ),
      ],
    );
  }
}

/// Keybindings bar shown at the bottom of desktop gameplay.
class KeybindingsBar extends StatelessWidget {
  const KeybindingsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xF00A0A0F),
        border: Border(top: BorderSide(color: NezTheme.border)),
      ),
      child: const Wrap(
        spacing: 20,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          KeybindItem(keys: ['W', 'A', 'S', 'D'], label: 'Move'),
          _Sep(),
          KeybindItem(keys: ['J'], label: 'A Button'),
          KeybindItem(keys: ['K'], label: 'B Button'),
          _Sep(),
          KeybindItem(keys: ['U'], label: 'Turbo A'),
          KeybindItem(keys: ['I'], label: 'Turbo B'),
          _Sep(),
          KeybindItem(keys: ['Enter'], label: 'Start'),
          KeybindItem(keys: ['X'], label: 'Select'),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      color: NezTheme.border,
    );
  }
}
