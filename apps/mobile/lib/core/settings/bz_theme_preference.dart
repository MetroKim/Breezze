import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable user-selected appearance for the whole app, including login and
/// every authenticated surface. System follows OS light/dark automatically.
/// Storage failures must not prevent a guest from entering Breezze.
class BzThemePreferenceController extends Notifier<ThemeMode> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'breezze.appearance.mode';

  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> restore() async {
    try {
      final stored = await _storage.read(key: _key);
      state = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // A browser/private-mode or OS keychain failure falls back to the OS.
      state = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {
      // UI remains usable with an in-memory preference.
    }
  }
}

final bzThemePreferenceProvider =
    NotifierProvider<BzThemePreferenceController, ThemeMode>(
  BzThemePreferenceController.new,
);
