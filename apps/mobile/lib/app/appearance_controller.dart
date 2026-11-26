import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

final appearanceProvider = AsyncNotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);

class AppearanceController extends AsyncNotifier<ThemeMode> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'breezze.appearance';

  @override
  Future<ThemeMode> build() async {
    final saved = await _storage.read(key: _key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> select(ThemeMode mode) async {
    final previous = state;
    state = const AsyncLoading<ThemeMode>().copyWithPrevious(previous);
    try {
      await _storage.write(key: _key, value: mode.name);
      state = AsyncData(mode);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}
