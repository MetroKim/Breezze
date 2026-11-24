import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'breezze_database.dart';
import 'db_instance.dart';
import 'catalog_id_map_dao.dart';
import 'favorites_dao.dart';
import 'recently_played_dao.dart';
import 'sync_outbox_dao.dart';

/// One database instance for the whole app; provider consumers and legacy
/// stores MUST share the same SQLite connection. Otherwise an outbox insert
/// and a cloud reconciliation could race across independent DB connections.
final breezzeDatabaseProvider = Provider<BreezzeDatabase>(
  (ref) => breezzeDb,
  // Owned by the app-wide singleton; never dispose from a provider scope.
);

final favoritesDaoProvider = Provider<FavoritesDao>(
  (ref) => FavoritesDao(ref.watch(breezzeDatabaseProvider)),
);

final recentlyPlayedDaoProvider = Provider<RecentlyPlayedDao>(
  (ref) => RecentlyPlayedDao(ref.watch(breezzeDatabaseProvider)),
);

final syncOutboxDaoProvider = Provider<SyncOutboxDao>(
  (ref) => SyncOutboxDao(ref.watch(breezzeDatabaseProvider)),
);

final catalogIdMapDaoProvider = Provider<CatalogIdMapDao>(
  (ref) => CatalogIdMapDao(ref.watch(breezzeDatabaseProvider)),
);
