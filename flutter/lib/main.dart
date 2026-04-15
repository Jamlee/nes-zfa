import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const NezApp());
}

class NezApp extends StatelessWidget {
  const NezApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nez',
      debugShowCheckedModeBanner: false,
      theme: NezTheme.darkTheme,
      home: const NezShell(),
    );
  }
}

/// Main shell with bottom navigation (mobile) or sidebar (desktop).
class NezShell extends StatefulWidget {
  const NezShell({super.key});

  @override
  State<NezShell> createState() => _NezShellState();
}

class _NezShellState extends State<NezShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.videogame_asset_outlined),
      selectedIcon: Icon(Icons.videogame_asset),
      label: 'Library',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _screens = [
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return _buildDesktopShell();
    }
    return _buildMobileShell();
  }

  Widget _buildMobileShell() {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _destinations,
        height: 64,
      ),
    );
  }

  Widget _buildDesktopShell() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 200,
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F1A),
              border: Border(right: BorderSide(color: NezTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [NezTheme.accentPrimary, NezTheme.accentSecondary],
                    ).createShader(bounds),
                    child: const Text(
                      'Nez',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const _SidebarSectionTitle('BROWSE'),
                _SidebarItem(
                  icon: Icons.videogame_asset,
                  label: 'All Games',
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const Spacer(),
                _SidebarItem(
                  icon: Icons.settings,
                  label: 'Settings',
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Main content
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  final String text;
  const _SidebarSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: NezTheme.textDim,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? NezTheme.accentPrimary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      selected ? NezTheme.textPrimary : NezTheme.textSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? NezTheme.textPrimary
                      : NezTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
