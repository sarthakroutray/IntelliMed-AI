import 'package:flutter/material.dart';

import 'api/patient_repository.dart';
import 'auth.dart';
import 'model_manager.dart';
import 'screens/capture_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_screen.dart';
import 'sync.dart';
import 'theme_controller.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/brand_mark.dart';

/// The signed-in app shell: bottom navigation over five destinations.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.models,
    required this.sync,
    required this.auth,
    required this.repository,
    required this.themeController,
  });

  final ModelManager models;
  final V2Sync sync;
  final AuthService auth;
  final PatientRepository repository;
  final ThemeController themeController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _destinations = <NavDestination>[
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

  int _index = 0;

  /// Bumped to make a tab reload after an action elsewhere (deleting a document
  /// should refresh both Docs and Home). Tabs that are not currently visible
  /// defer the reload until they are shown, so an action never fans out into
  /// network work for screens the user cannot see.
  int _refreshToken = 0;

  void _goTo(int index) => setState(() => _index = index);

  void _refreshAll() => setState(() => _refreshToken++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        repository: widget.repository,
        models: widget.models,
        sync: widget.sync,
        refreshToken: _refreshToken,
        isActive: _index == 0,
        onNavigate: _goTo,
      ),
      CaptureScreen(
        models: widget.models,
        sync: widget.sync,
        refreshToken: _refreshToken,
        isActive: _index == 1,
        onChanged: _refreshAll,
      ),
      ReportsScreen(
        repository: widget.repository,
        refreshToken: _refreshToken,
        isActive: _index == 2,
        onChanged: _refreshAll,
      ),
      DocumentsScreen(
        repository: widget.repository,
        refreshToken: _refreshToken,
        isActive: _index == 3,
        onChanged: _refreshAll,
      ),
      ProfileScreen(
        auth: widget.auth,
        repository: widget.repository,
        models: widget.models,
        sync: widget.sync,
        themeController: widget.themeController,
        refreshToken: _refreshToken,
        isActive: _index == 4,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            BrandMark(size: 26),
            SizedBox(width: 10),
            Text('IntelliMed-AI'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: AppBottomNav(
        destinations: _destinations,
        selectedIndex: _index,
        onSelected: _goTo,
      ),
    );
  }
}
