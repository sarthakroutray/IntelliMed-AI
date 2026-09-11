import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intellimed_app/theme.dart';
import 'package:intellimed_app/widgets/app_card.dart';
import 'package:intellimed_app/widgets/app_drawer.dart';
import 'package:intellimed_app/widgets/brand_mark.dart';
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

  testWidgets('drawer lists every destination and marks the active one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppDrawer(selectedIndex: 0, onSelect: _noop)),
    );

    expect(find.byType(BrandMark), findsOneWidget);
    for (final label in ['Capture', 'Results', 'Bench', 'Spike']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('DEVELOPER'), findsOneWidget);
  });

  testWidgets('tapping a drawer destination reports it and closes the drawer', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: AppDrawer(
                      selectedIndex: 0,
                      onSelect: (i) => picked = i,
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDrawer), findsOneWidget);

    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();

    expect(picked, 1);
    expect(find.byType(AppDrawer), findsNothing);
  });
}

void _noop(int _) {}
