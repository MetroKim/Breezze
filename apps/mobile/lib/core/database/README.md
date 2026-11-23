# Breezze Mobile — Local Database (Drift / SQLite)

## What changed

`FavoritesStore` and `RecentStore` are now **drift-backed (SQLite)**.
Their public APIs (`load` / `toggle` / `record`, `FavoriteTrack`,
`RecentEntry`) are unchanged — every screen keeps compiling and
behaving identically. The old JSON files are read **once** by a
best-effort one-shot migration at shell startup
(`core/database/migrate_to_drift.dart`), which is idempotent and
never blocks startup.

Every favorite/recent mutation also writes an op to the **sync
outbox** (`favorite.add` / `favorite.remove` / `recent.play`) so
these actions can be replayed to the backend
(`/library/favorites`, `/home/plays`) once the user is signed in.

## Files

| File | Purpose |
|---|---|
| `core/database/breezze_database.dart` | Tables: favorite_tracks, recently_played, sync_outbox |
| `core/database/favorites_dao.dart` | Favorites CRUD + outbox writes |
| `core/database/recently_played_dao.dart` | Recent CRUD, 12-row cap, outbox writes |
| `core/database/sync_outbox_dao.dart` | Ordered pending ops + drain/clear |
| `core/database/db_instance.dart` | Lazy singleton for direct-construction call sites |
| `core/database/database_providers.dart` | Riverpod providers over the DAOs |
| `core/database/migrate_to_drift.dart` | One-shot JSON → SQLite import |
| `app/bootstrap.dart` | FavoritesStore → drift-backed (FavoriteTrack kept) |
| `app/recent_store.dart` | RecentStore → drift-backed (RecentEntry kept) |

## First run after checkout

The drift `.g.dart` files are generated, not committed:

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Then `flutter create .` (first checkout only), `flutter run`.

## Sync-outbox drain (next step)

`SyncOutboxDao.drain` is ready; wiring it to the auth session happens
in the onboarding-wiring round — ops replay against the backend when
a valid JWT session exists, clearing as they succeed.

## Platform database backends

The generated Drift database uses a conditional connection factory:

- Android, iOS, macOS, Windows and Linux: native SQLite via NativeDatabase.
- Web: Drift WasmDatabase with browser-backed persistence.

Before building Flutter Web locally, run `bash tool/prepare_web_database.sh`
from `apps/mobile`. It downloads the pinned `sqlite3.wasm` and `drift_worker.js`
runtime assets into `apps/mobile/web/`. The CI Web job runs this script before
the release build. Keep the pinned release aligned with the resolved Drift and
sqlite3 dependencies when upgrading them.


## Durable playback heartbeat outbox

Playback heartbeat retries are stored separately from user-library sync operations
in `playback_heartbeat_outbox`. Each row is scoped to the authenticated owner
and retains the exact server session ID, event UUID and sequence used by the
original request. The player writes the row before sending a heartbeat, removes
it only after acknowledgement, and retries the same event identity.

After authentication is restored, Breezze replays pending rows for that same
account and attempts to stop each abandoned server session. A successful stop
clears that session's pending rows. Rows belonging to another account are never
read or replayed during the active account's recovery. The server's session TTL
remains the final cleanup mechanism when the device stays offline or the
session is no longer addressable.

Schema version 3 adds this table without changing existing favorites, recent
history, sync outbox or catalog ID data.
