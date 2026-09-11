import 'package:flutter/material.dart';

import '../theme.dart';
import 'brand_mark.dart';

/// One entry in the drawer's navigation list.
class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.developer = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Developer-only destination, grouped under the "Developer" section.
  final bool developer;
}

/// Web-style sidebar navigation. Mirrors the layout of the web app's sidebar:
/// brand header, nav items with a `bg-primary/10` active state, then a footer.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Order must match the page list built in `main.dart`.
  static const items = <AppNavItem>[
    AppNavItem(
      label: 'Capture',
      icon: Icons.document_scanner_outlined,
      selectedIcon: Icons.document_scanner,
    ),
    AppNavItem(
      label: 'Results',
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
    ),
    AppNavItem(
      label: 'Bench',
      icon: Icons.speed_outlined,
      selectedIcon: Icons.speed,
      developer: true,
    ),
    AppNavItem(
      label: 'Spike',
      icon: Icons.science_outlined,
      selectedIcon: Icons.science,
      developer: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: AppColors.surface(brightness),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                children: [
                  for (final (i, item) in AppDrawer.items.indexed)
                    if (!item.developer)
                      _NavTile(
                        item: item,
                        selected: i == selectedIndex,
                        onTap: () => _select(context, i),
                      ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      'DEVELOPER',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  for (final (i, item) in AppDrawer.items.indexed)
                    if (item.developer)
                      _NavTile(
                        item: item,
                        selected: i == selectedIndex,
                        onTap: () => _select(context, i),
                      ),
                ],
              ),
            ),
            Divider(color: AppColors.divider(brightness), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Text(
                'On-device • offline-first',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, int index) {
    onSelect(index);
    Navigator.of(context).pop();
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider(brightness)),
        ),
      ),
      child: const BrandLockup(),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final muted = AppColors.textMuted(brightness);
    final shape = BorderRadius.circular(AppRadius.control);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.activeNavFill : Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 20,
                  color: selected ? AppColors.primary : muted,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppColors.primary : muted,
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
