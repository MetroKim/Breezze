import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart' show FavoritesStore;
import '../app/recent_store.dart' show RecentStore;
import 'database_providers.dart';
import 'favorites_store_drift.dart';
import 'recent_store_drift.dart';

/// One-shot legacy migration: JSON stores → SQLite (Drift).
/// Runs once per app launch; idempotent (safe if it runs again).
/// After migration, the drift facades are the app's stores.
Future<void> migrateJsonStoresToDrift(ProviderContainer container) async {
  try {
    final legacyFavorites = await FavoritesStore().load();
    await container
        .read(favoritesStoreDriftProvider)
        .migrateFromJson(legacyFavorites);

    final legacyRecent = await RecentStore().load();
    await container
        .read(recentStoreDriftProvider)
        .migrateFromJson(legacyRecent);
  } catch (_) {
    // Migration is best-effort: a corrupt legacy JSON must never
    // block app startup. The DB simply starts empty.
  }
}
