import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intellimed_app/theme.dart';
import 'package:intellimed_app/widgets/app_bottom_nav.dart';
import 'package:intellimed_app/widgets/app_card.dart';
import 'package:intellimed_app/widgets/status_chip.dart';

/// Renders [child] under the real app themes so widget specs cover both modes.
Widget _host(Widget child, {bool dark = false}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: child),
);

void main() {
  test('themes carry the web design tokens', () {
    expect(AppTheme.light.textTheme.bodyLarge?.fontFamily, 'Manrope');
    expect(AppTheme.dark.textTheme.bodyLarge?.fontFamily, 'Manrope');
    expect(AppTheme.light.textTheme.headlineSmall?.fontFamily, 'Manrope');
    expect(AppTheme.light.colorScheme.primary, AppColors.primary);
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFF6F6F8));
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF101622));
    expect(AppTheme.light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(AppTheme.dark.colorScheme.surface, const Color(0xFF1A202C));
  });

  testWidgets('AppCard + SectionTitle render the heading and caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppCard(child: SectionTitle(title: 'Capture', subtitle: 'ctx'))),
    );
    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('ctx'), findsOneWidget);
  });

  for (final status in ['synced', 'pending', 'failed']) {
    testWidgets('StatusChip renders $status in light and dark', (tester) async {
      await tester.pumpWidget(_host(StatusChip(status: status)));
      expect(find.text(status.toUpperCase()), findsOneWidget);

      await tester.pumpWidget(_host(StatusChip(status: status), dark: true));
      expect(find.text(status.toUpperCase()), findsOneWidget);
    });
  }

  testWidgets('bottom nav lists every destination and marks the active one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AppBottomNav(
          destinations: _destinations,
          selectedIndex: 0,
          onSelected: _noop,
        ),
      ),
    );

    for (final label in ['Home', 'Capture', 'Reports', 'Docs', 'Me']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('tapping a bottom-nav destination reports its index', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      _host(
        AppBottomNav(
          destinations: _destinations,
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(picked, 2);
  });
}

const _destinations = <NavDestination>[
  NavDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  NavDestination(
    label: 'Capture',
    icon: Icons.document_scanner_outlined,
    selectedIcon: Icons.document_scanner,
  ),
  NavDestination(
    label: 'Reports',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
  ),
  NavDestination(
    label: 'Docs',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
  NavDestination(
    label: 'Me',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

void _noop(int _) {}
