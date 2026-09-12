import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Theme mode, persisted locally so the choice survives a restart.
///
/// The web app stores a boolean `dark_mode` on the profile; we keep the same
/// value in sync (so the setting follows the account across clients) but store
/// a tri-state locally, because "follow system" is a real choice that a
/// boolean cannot express.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      super(ThemeMode.system);

  static const _key = 'intellimed_theme_mode';

  final FlutterSecureStorage _storage;

  /// True once the user has made an explicit choice, so a profile load doesn't
  /// overwrite it.
  bool _explicit = false;

  bool get isExplicit => _explicit;

  Future<void> load() async {
    try {
      final stored = await _storage.read(key: _key);
      switch (stored) {
        case 'light':
          value = ThemeMode.light;
          _explicit = true;
        case 'dark':
          value = ThemeMode.dark;
          _explicit = true;
        default:
          value = ThemeMode.system;
      }
    } catch (_) {
      // Storage unavailable — following the system is a safe default.
    }
  }

  /// Apply the server-side preference, but never override an explicit local
  /// choice (the user's most recent action wins).
  void applyFromProfile(bool darkMode) {
    if (_explicit) return;
    value = darkMode ? ThemeMode.dark : ThemeMode.light;
  }


  Future<void> set(ThemeMode mode) async {
    _explicit = true;
    value = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }

  /// The boolean the backend profile expects (`dark_mode`).
  bool get prefersDark => value == ThemeMode.dark;
}
