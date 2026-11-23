# Breezze saved albums — account cloud sync contract

## Purpose and scope

Saved albums are **bookmarks containing catalog metadata**, not media entitlement records. The cloud endpoints are authenticated with the existing JWT guard, bound to the authenticated user and fixed to the `apple_itunes` discovery source for this first integration. No Apple Music playback, downloads, cookies or premium API access are introduced.

## API

- `GET /api/v1/library/albums?cursor=<opaque id>` returns at most 100 saved albums and an optional next cursor. The cursor must belong to the same authenticated user; otherwise it is rejected.
- `POST /api/v1/library/albums` upserts the user's `externalAlbumId`, `title`, `artist`, `genres`, and optional approved artwork and catalog URLs, plus explicit `isCompilation` when actually supplied by the source.
- `DELETE /api/v1/library/albums/:externalAlbumId` deletes only the authenticated user's own bookmark and is idempotent.

The database has a unique constraint on `(userId, source, externalAlbumId)`, `ON DELETE CASCADE` on the user relation, and a bounded keyset pagination index. Changes are an additive migration. Server metadata URLs permit only trusted Apple/iTunes catalog and artwork hosts over HTTPS; this prevents user-provided URLs from becoming private-host links.

## Mobile offline / account behavior

The existing `SavedAlbumStore` remains the local first-read cache, keyed by the authenticated account ID. Every add/remove operation persists a per-owner encrypted-storage outbox entry **before** it updates the local view. A later refresh replays those operations using idempotent server upserts/deletes, discards each entry only after the network operation completes and the owner is still active, then reconciles from the complete server page sequence.

- **Offline:** local change remains visible; the same outbox operation is retried on reconnect.
- **Restart:** pending operations persist in secure storage.
- **Account switch or token mutation:** the sync operation aborts before making further calls or replacing the local cache. No account A album is uploaded with account B's token.
- **Legacy upgrade:** pre-cloud albums are enqueued for upload once per account; a durable marker prevents later remote deletions from being resurrected.
- **Failure/cursor error:** do not replace the local cache with a partial page. Unknown catalog source rows are ignored, not converted into a playback path.
- **Remote changes:** after pending local operations finish, server data is authoritative, including deletions made by other devices. The next Library refresh reconciles them.

## Validation

- Backend unit tests cover scope, invalid cursors/URLs, upsert idempotency and bounded pagination.
- PostgreSQL integration tests cover two-account isolation, concurrent upserts, user-deletion cascade and cross-account cursor rejection.
- Flutter tests cover real API request paths/JWT, app restart, offline queue replay, local deletion, account/token switch, original local migration and remote-deletion reconciliation.
- CI now also runs the design-system widget test package and retains a non-store-ready Android release test APK artifact.

## Still outside this slice

Native audible playback remains authorized through the separate media resolver; saved-album metadata never changes its permissions. A signed release, real-device sync/audio QA, provider licences, full-catalog availability, radio streams, mass album pagination/load and multi-device conflict stress tests remain release acceptance requirements. Do not mark the entire app 100% complete from a successful CI run alone.
