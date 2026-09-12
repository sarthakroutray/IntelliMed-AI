import 'package:flutter/material.dart';

import '../theme.dart';

/// One destination in the bottom navigation bar.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom navigation for the signed-in app.
///
/// The web app uses a sidebar; on a phone the primary destinations need to be
/// thumb-reachable, so this is the one place the navigation chrome differs. The
/// colour, typography and radius tokens are still shared with the web app.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        border: Border(top: BorderSide(color: AppColors.divider(brightness))),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon, size: 22),
                selectedIcon: Icon(d.selectedIcon, size: 22),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}
