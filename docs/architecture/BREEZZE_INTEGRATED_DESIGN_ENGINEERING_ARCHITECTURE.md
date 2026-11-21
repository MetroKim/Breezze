# Breezze Integrated Design Engineering Architecture

**Purpose:** Connect the Breezze interface contract to implementable Flutter, domain, backend, storage, and playback contracts. This is the engineering companion to `BREEZZE_INTERFACE_CONTRACT.md`, not a replacement for it.

**Product constraints**
- Breezze is a free music platform. No subscription, billing, upgrade, or paywall UI or schema is to be introduced.
- Preserve the five primary destinations: Home, Browse, Radio, Library, Search.
- Preserve the positions, section order, controls, and interactions in the interface contract.
- Use original Breezze SVG assets for interface icons. Do not introduce emoji or icon-font glyphs.
- Do not display invented catalog metadata, fake streams, fake charts, fake concerts, or pretend backend capabilities.
- Existing backend is a NestJS modular monolith with Prisma/PostgreSQL and Redis/BullMQ. Cloudflare is the API edge/security platform, not a forced replacement for this backend. Audio is streamed directly from approved external providers; Breezze does not host music files.

## 1. Architecture overview

### 1.1 Application layers (bottom-up)

```text
PRESENTATION — Flutter widgets, layouts, animations, accessibility
       ↓
APPLICATION — Riverpod Notifiers/Controllers, commands, screen state
       ↓
DOMAIN — entities, value objects, use cases, repository contracts,
         rights decisions, playback and queue contracts
       ↓
DATA — repository implementations, DTO mapping, local DB, API clients
       ↓
PLATFORM — NestJS API, Cloudflare edge, audio engine,
           secure storage, OS audio/session APIs
```

Dependency direction points inward. Presentation does not call HTTP, Prisma, R2, or audio plugins directly. Domain types must not depend on Flutter widgets, NestJS DTOs, or provider-specific response shapes.

### 1.2 Repository boundaries

- `apps/mobile`: Flutter presentation and app composition.
- `packages/design_system`: Breezze visual tokens, themes, components and SVG icon wrappers.
- `packages/audio_contracts`: playback state, queue, source and audio-engine abstractions.
- `packages/api_client`: transport and provider-facing DTO/client contracts.
- `backend/api`: NestJS modules, Prisma/PostgreSQL, Redis/BullMQ, authorization and domain services.
- `infra/cloudflare`: Workers, deployment configuration, cache and edge security.
- `docs/design`: visual/interface contracts.
- `docs/architecture`: system and implementation contracts.

### 1.3 Core shared services

| Service | Responsibility | Used by |
|---|---|---|
| PlayerController | Single global playback state and commands | Now Playing, MiniPlayer, every play action |
| QueueManager | Queue insertion, ordering, shuffle/repeat and removal | Player, Playing Next |
| AudioEngineAdapter | Adapter over just_audio/native playback | PlayerController |
| CatalogRepository | Canonical normalized tracks/albums/artists/categories | Browse, Search, Library, details |
| RightsDecisionService | Ask backend whether a requested action is allowed | Playback, download, stream resolution |
| LibrarySyncManager | Offline-first library state and sync outbox | Library, favorites, downloads |
| RecentStore | Recently played history | Home, Library |
| FavoritesStore | Favorite state and persistence | Search rows, player, library |
| SearchRepository | Remote catalog search + local library search | Search |
| AnalyticsClient | Opt-in/minimal usage and listening events | Navigation, playback, discovery |
| ShareService | Native share sheet and valid Breezze links | Track, album, artist, playlist, station |

There must be one global playback engine. Screens issue commands to PlayerController; they do not instantiate independent players.

## 2. State management pattern

Use the existing Riverpod setup. Keep provider ownership at the application layer and expose immutable state to widgets.

Recommended provider families (names are target names; reuse existing providers where equivalent):
- `authSessionProvider`
- `catalogRepositoryProvider`
- `playerControllerProvider`
- `queueManagerProvider`
- `librarySyncManagerProvider`
- `favoritesStoreProvider`
- `recentStoreProvider`
- `searchControllerProvider`
- `homeSectionsControllerProvider`
- `browseControllerProvider`
- `radioControllerProvider`
- `downloadControllerProvider`

Controller rules:
1. UI calls a typed controller method.
2. Controller sets loading/success/empty/error state.
3. Controller calls a domain use case or repository interface.
4. Repository chooses local cache, API, or provider source.
5. DTOs are mapped to domain entities before reaching widgets.
6. Errors are classified; do not turn network failures into empty results.
7. Cancel or ignore stale requests when query/route identity changes.
8. Controllers must not own duplicate copies of global player state.

Prefer AsyncValue or sealed state classes for asynchronous flows. Do not mix unrelated state in a single global notifier.

## 3. Shared data and service contracts

### 3.1 Core domain entities

- `Track`: canonical ID, title, primary artist reference, duration, artwork, explicit flag, availability metadata, quality capabilities, source attribution.
- `Artist`: canonical ID, display name, portrait/artwork, biography where supplied, follow state.
- `Album`: canonical ID, title, artist references, release date, artwork, track references, credits where supplied.
- `Playlist`: ID, owner, title, description, ordered track references, local/remote scope, version and collaboration capability.
- `Station`: ID, name, artwork, description, live status, stream capability, schedule.
- `PlayableSource`: URI or platform source handle, MIME type, quality, expiry, seek/pause/skip capabilities, attribution.
- `LibraryItem`: item type, canonical ID, saved timestamp, local availability, sync version.
- `RightsDecision`: allow/deny, reason code, territory, permitted actions, expiry where applicable.

All IDs are opaque canonical identifiers. Provider IDs remain source metadata and are not interchangeable with canonical IDs.

### 3.2 Backend endpoint contract status

The following paths are target logical API contracts, not a claim that every route is already implemented. The NestJS modules are the source of truth for the actual route prefix and DTO.

| Capability | Logical contract | Backend owner |
|---|---|---|
| Home feed | GET `/home/sections`, GET `/home/sections/:id/items` | Home / Recommendations |
| Listening events | POST `/listening-events` | Replay / analytics |
| Profile | GET `/users/me` | Users / Auth |
| Browse | GET `/browse/categories`, GET `/browse/:category` | Catalog / Recommendations |
| Search | GET `/search`, GET `/search/suggestions` | Search |
| Radio | GET `/radio/stations`, GET `/radio/stations/:id`, stream resolution contract | Radio / Rights / Playback |
| Library | GET/POST/DELETE `/library/items` | Library |
| Downloads | GET `/downloads`, POST `/downloads` | Downloads / Rights |
| Playback | POST `/playback/resolve` or existing equivalent | Playback / Rights |
| Songs | GET `/songs/:id`, lyrics/credits/availability subresources | Catalog / Lyrics / Rights |
| Albums | GET `/albums/:id`, tracks, credits, related | Catalog |
| Artists | GET `/artists/:id`, albums, tracks, videos, concerts, related | Catalog / Providers |
| Playlists | CRUD, tracks, reorder, share, collaborators | Playlists / Social |

Before wiring a screen, inspect the existing controller and DTO and map the logical contract to the actual API. Do not add client calls to endpoints that have not been implemented.

## 4. Section 1 — Top-level tab bar

### Visual and interaction contract
- Exactly five equally weighted destinations: Home, Browse, Radio, Library, Search.
- Target height: 54dp for the tab control, subject to safe-area/platform constraints.
- Active state: Breezze red SVG icon and light neutral selected surface.
- Inactive state: neutral SVG icon and subdued label.
- Long-press and horizontal slide selects another tab.
- MiniPlayer remains immediately above the bar when playback is active.

### Engineering
Tab selection is local UI state. Use the existing shell/router architecture; do not introduce a second navigation stack just to match a sample snippet. Route transitions must preserve each tab's scroll/navigation state where feasible.

Optional analytics event: `tab_navigation` with stable `tab_id` and `section_name`. Analytics is opt-in/minimized and must never block navigation. No audit log is required for every tab tap unless a concrete compliance need is approved.

### Flow
```text
Tap/slide → Shell navigation state → selected destination
          → restore/init screen state → repository loads if stale
          → render loading/cache/content/error state
```

## 5. Section 2 — Home / Listen Now

### Visual order
1. Brand and top-right profile/action cluster.
2. Listen Now heading.
3. Recently Played.
4. Shared With You.
5. Mixes / stations.
6. Replay summary.

Preserve the existing contract's placement. Profile, create-playlist, share, and overflow actions must have real handlers or be disabled with an explanation.

### Data and state
HomeController requests home sections from HomeRepository. Repository loads local cached sections first, then refreshes remote data. Use stable section IDs and typed section kinds; do not deserialize enum indexes from untrusted JSON.

Suggested entity shape:
```dart
class HomeSection {
  final String id;
  final String title;
  final HomeSectionType type;
  final List<HomeItem> items;
  final DateTime? updatedAt;
}
```

### Data flow
```text
HomeScreen → HomeController.load()
           → HomeRepository
           → local cache (immediate)
           → NestJS Home/Recommendations API (refresh)
           → DTO mapping → cache update → Riverpod state
```

Shared With You requires real social/share records. Replay requires listening-event aggregation. Until those services return data, show honest empty/building states. Recently Played comes from RecentStore and listening events; never fabricate play counts.

## 6. Section 3 — Browse

### Visual contract
Browse exposes Latest Songs, New Releases, Trending Songs, Daily Top 100, Coming Soon, Music Videos, Charts, Browse by Genre, Moods & Activities, City Charts, and Concerts. Preserve this section order from the product contract.

### Engineering
BrowseController takes a typed category and cursor/page token. BrowseRepository maps category responses to normalized BrowseItems. Load the first page, then fetch additional pages near the end of the list. Cache by category + cursor + territory + locale + catalog version.

Search debounce is 300ms for the search field; Browse category selection is not a text-search debounce.

### States
Initial, loading, success, empty, error/retry, and loading-more. Keep cached content visible while refreshing. Distinguish unavailable provider from a legitimate empty category.

### API and source boundaries
The current connected public source is track-oriented. Official chart positions, city rankings, editorial releases, video catalogs, and concert events require provider-backed or Breezze-owned data. Do not label arbitrary search results as editorial feeds.

### Performance and accessibility
- Cursor pagination, not unbounded result loading.
- Artwork caching with bounded disk usage.
- Stable keys and progressive image loading.
- Reduced-motion mode disables shimmer/animated placeholders.
- Semantic labels include category and item title.

## 7. Section 4 — Radio

### Visual contract
- Live radio banner.
- First six featured stations in a fixed two-column grid.
- Full station directory below.
- Station detail with schedule, live status, share and add-to-library actions.

### Engineering
RadioController loads station metadata and schedule independently. Station metadata does not imply an audio stream exists.

Radio playback requires a dedicated `RadioPlayableSource` or equivalent source capability model. Live streams may not support seeking or pausing. The audio engine must model these constraints rather than pass a fake track ID to the track player.

### Live tune-in flow
```text
Tap Listen Live → RadioController
               → backend stream resolution
               → RightsDecisionService
               → short-lived authorized stream grant
               → AudioEngineAdapter radio session
               → buffering / playing / reconnect / failed
```

Stream URLs must be short-lived and protected. Handle network recovery with bounded retries and jitter. Schedule times must be rendered in the station's declared timezone. Radio playback remains unavailable until this complete contract exists.

## 8. Section 5 — Library

### Visual contract
Order: Playlists, Artists, Albums, Songs, Genres, Compilations. Downloads remains a dedicated Library sub-section. Edit mode customizes section visibility/order; do not move Downloads into the five-tab bar.

### Engineering
LibraryController reads local database first, then synchronizes remote records. Local mutations write to an outbox with idempotency keys. Sync responses update canonical versions.

Use per-user ownership on the server. Never accept a client-supplied user ID as authorization; derive identity from the authenticated session.

### Sync flow
```text
Local mutation → local DB transaction + outbox
               → connectivity/sync trigger
               → authenticated API mutation
               → server ownership + rights validation
               → canonical version response
               → merge/update local DB → UI refresh
```

Conflict policy must be explicit per operation. Favorites are set/unset operations with server timestamps or versioning; a boolean merge rule such as “local true always wins” is unsafe because it can resurrect a removed favorite.

### Downloads
Use states: notDownloaded, queued, downloading, paused, downloaded, failed, expired, revoked. Real progress comes from the download task/stream; never simulate progress with sleeps or random speeds. Verify rights and offline-download permission before starting. Store media in app-private storage and persist integrity metadata.

## 9. Section 6 — Search

### Visual contract
Search field, Breezze/Your Library scope switch, recent searches, suggested discovery grid, result rows and contextual menus. Search result metadata must only show fields supplied by the catalog.

### Engineering
SearchController debounces query changes by 300ms, cancels or ignores stale requests, and exposes distinct idle/debouncing/loading/success/no-results/error states.

- Recent search history: local-first and capped/deduplicated.
- Your Library: query local saved entities, not only favorites once the library repository is complete.
- Global search: backend search endpoint with cursor pagination and server ranking.
- Suggestions: backend suggestions endpoint with bounded cache TTL.

Do not download all results to filter on-device. Server performs relevance ranking, type filtering, and pagination; client may apply lightweight presentation filters to the loaded page.

### Flow
```text
Query → debounce → SearchController
      → SearchRepository
      → local library or NestJS catalog search
      → normalized SearchResult entities
      → cache + state → UI
```

PostgreSQL full-text/trigram search is a backend implementation option; use the indexes actually present in the migration/schema and measure query plans before claiming it is enabled.

## 10. Section 7 — Now Playing and global playback

### Visual contract
Artwork, title/artist, playhead, previous/play-pause/next, favorite, lyrics, Playing Next, shuffle, repeat, and supported output controls. Unsupported platform features must not appear as active controls.

### Playback state machine
Use explicit states: idle, resolving, loading, buffering, playing, paused, seeking, transitioning, ended, failed, interrupted, offline. Define legal transitions and test invalid transitions. Timeouts must be cancellable and must not emit stale state after a newer request.

### Playback resolution
```text
Track ID → PlaybackResolver
         → local authorized download OR backend live resolution
         → RightsDecisionService / server rights decision
         → device format capability check
         → PlayableSource
         → AudioEngineAdapter (just_audio)
         → PlayerController state + queue
```

The server is authoritative for rights. Client-side checks are UX hints only and must never grant access.

### QueueManager
Owns the canonical upcoming queue, current entry, shuffle/repeat modes and stable queue-entry IDs. Implement add-next, add-to-end, remove, reorder, clear-upcoming and shuffle restoration. Queue operations must be deterministic and tested; version checks should compare an actual expected version supplied by the caller, not a value just incremented locally.

### MiniPlayer
MiniPlayer observes PlayerController state and dispatches commands. Expansion is a UI animation; it must not delay or mutate audio state. Avoid artificial Future.delayed state transitions when the animation controller already represents progress.

### Background audio
Use the existing audio_service integration and native platform configuration. Test lock-screen metadata, headset unplug, Bluetooth route changes, audio focus/interruption, app background/foreground, and process restart on real devices. Do not invent custom native APIs or package names; use the dependencies actually installed.

## 11. Section 8 — MiniPlayer

MiniPlayer is a projection of global PlayerController state, not a second player. It displays current track, artwork, playback progress, and controls. Tap/swipe expands Now Playing. When no active item exists, it is hidden or follows the existing empty-player shell design.

MiniPlayer actions dispatch to PlayerController. The widget never calls the audio plugin directly.

## 12. Section 9 — Album detail

### Visual contract
Album artwork and metadata hero; play/shuffle/favorite/download/share/overflow actions; tracklist; credits and related albums where metadata exists.

### Engineering
AlbumController loads AlbumRepository.getAlbum(albumId), then resolves tracks and optional credits/related content. Cache normalized album details with a freshness timestamp. A stale cache may render immediately while refresh runs.

### API boundary
The supplied GET `/albums/:id`, tracks, credits and related routes are target contracts. Inspect existing Catalog controllers/DTOs before wiring. Do not construct an album page from a search result that lacks a canonical album ID.

Credits are optional structured metadata. Omit unavailable songwriter/producer/engineer fields rather than inventing them. Download album action is permitted only if all selected tracks pass the rights/download checks.

## 13. Section 10 — Playlist detail

### Visual contract
Playlist artwork/title/description/owner/count; play/shuffle/add/share/overflow; ordered tracklist. Add/remove/reorder controls depend on ownership and collaboration permissions.

### Engineering
PlaylistRepository owns CRUD, track membership, ordering, version and sync. Local-only playlists must be labeled local and must not display a fake share link.

Collaborative playlist sync is a future NestJS Social/Playlists capability. Do not introduce Firebase/Firestore just because an example snippet uses it; this repository uses NestJS/PostgreSQL/Redis. A collaboration design should use authenticated API writes, versioned mutations, and a real-time transport only if the product requires live updates.

### Conflict handling
Use optimistic concurrency (version/ETag) and idempotency keys. On conflict, fetch canonical server state and merge only operations that are safe to replay. Deleting a playlist or removing a track must not silently resurrect stale local data.

## 14. Section 11 — Artist page

### Visual contract
Artist portrait/name/follow/play/share/overflow; Essential Albums; Essential Songs; Music Videos; Upcoming Concerts; Similar Artists; full discography; Singles/EPs.

### Engineering
ArtistRepository loads core profile first, then independently loads albums, tracks, videos, events, similar artists and discography. Each subresource has its own loading/empty/error state so one unavailable provider does not blank the whole artist page.

Cache according to data volatility: profile/artwork longer; concerts shorter; paginated discography by cursor. Concert dates must retain source timezone and country/city. Ticket links must be source-verified.

Current provider/catalog data may not expose every entity or subresource. Hide unavailable sections or show an honest unavailable state; do not generate artist profiles from a name-only string.

## 15. Section 12 — Song search result and track metadata

Track rows use normalized Track entities. Actions: play, favorite, download, add to library, add to playlist, share, overflow, queue. Each action dispatches to the relevant controller/use case.

Badges:
- Explicit E: only if explicit metadata is supplied.
- Favorite: current FavoritesStore state.
- Download: actual download state.
- Lossless / Dolby Atmos: only when the source supplies a verified rendition and the device/output path supports it.
- Collaborate: only for a real collaborative playlist context.

A favorite toggle must mutate favorite state, not copy unrelated fields. Download toggles must call DownloadController; they cannot simply flip a local boolean.

## 16. Section 13 — Symbols and badges

Build reusable SVG-based components from Breezze's asset set. Components receive semantic state and callbacks, not hard-coded data.

- ExplicitBadge: non-interactive label.
- FavoriteButton: stateful semantic button; accessible label changes between Add to favorites / Remove from favorites.
- DownloadIndicator: reflects queued/downloading/paused/downloaded/failed/expired/revoked.
- QualityBadge: shown only for verified source capability.
- CollaboratorBadge: shown only when collaborator data is present.

Reduced-motion preference must suppress scale/flash transitions while preserving state feedback.

## 17. Section 14 — Popovers, share sheets and menus

Context menus are built from item type, ownership, rights and available callbacks. Do not show actions that cannot execute. Destructive operations require confirmation.

ShareService uses the platform share sheet and a real canonical Breezze deep link. Until deep links resolve to a valid public route, share plain text or disable link sharing with an explanation. Never fabricate a URL.

AirPlay, SharePlay, lyrics translation/pronunciation and collaboration invitations are capability-gated platform/backend features. A visual menu alone is not an implementation.

## 18. Section 15 — Interface affordances

- Favorite animation: short, restrained, and disabled/reduced under reduced-motion settings.
- Download progress: sourced from actual stream/task progress, with real bytes/speed only if measured.
- Queue gestures: provide accessible alternatives to swipe/drag.
- Loading: skeleton only when it improves perceived loading; never animate indefinitely under reduced-motion.
- All tappable controls have semantic labels, focus states, adequate touch targets and disabled explanations.
- SVGs use consistent stroke/fill rules and theme-aware colors.

## 19. Section 16 — Platform variations

### Android and iOS phones
Primary five-tab navigation, safe-area-aware MiniPlayer, background audio, lock-screen metadata and system audio focus.

### Tablets
Use wider content rails or a sidebar when width supports it, but preserve the same five destinations and hierarchy. Do not infer tablet mode solely from OS; use available width and layout breakpoints.

### Desktop
Add keyboard shortcuts only when desktop targets are supported and tested. Example mappings: Cmd/Ctrl+F focuses search; Space toggles playback when focus is not inside a text field. Keyboard handling must not steal standard text-editing shortcuts.

### AirPlay / HomePod / Bluetooth
Feature-detect actual output routes and synchronize output state with PlayerController. Do not display fake output device names.

### Apple Watch / CarPlay
Treat as separate platform projects requiring native entitlements, templates, review and real-device QA. Do not claim Flutter-only placeholder classes provide CarPlay or Watch support.

## 20. Security, rights and privacy

- Authentication proves who the user is; authorization determines whether the user can access a specific resource/action.
- Backend derives user identity from the verified session, never a client-provided user ID.
- RightsDecisionService must be checked server-side before playback grants, downloads, stream resolution, and territory-restricted actions.
- Keep provider/API secrets on the backend or Cloudflare secret bindings.
- Use opt-in/minimal analytics; do not log raw search queries, tokens, signed URLs, or unnecessary personal information.
- User A must never access User B's library, playlists, downloads, profile, or private listening data.
- All user-owned Prisma queries must scope by authenticated user identity and have tests for cross-user access.

## 21. Offline-first, caching and synchronization

Local database is a cache and offline workspace, not the canonical owner of remote data. Define cache TTLs per entity and keep a sync outbox for mutations. Mutations are idempotent. Conflict rules are operation-specific. Do not let a stale cache bypass a revoked rights decision.

## 22. Observability and analytics

Use correlation/request IDs across Flutter, Cloudflare Worker and NestJS. Track:
- app/API error rate and latency;
- search latency and zero-result rate;
- playback resolve/start/buffer/failure;
- download completion/failure;
- queue age and worker retries;
- edge/API cache hit ratio and provider resolution errors.

Analytics must not block UI and should be privacy-minimized. Tab navigation analytics are optional, not an audit log.

## 23. Testing strategy and release gates

| Layer | Required tests | Tooling |
|---|---|---|
| Domain | entities, rights decisions, queue invariants, state transitions | Dart unit tests |
| Application | controller state, stale response protection, retries | Provider/container tests |
| Data | DTO parsing, repository cache/API merge, outbox | Unit + integration tests |
| UI | section order, empty/loading/error, gestures, accessibility | flutter_test |
| Audio | seek, interruptions, background, queue, route changes | real-device QA + integration_test |
| Backend | authz, ownership isolation, rights, API contracts | Jest + Nest testing |
| Cloudflare | WAF/rate-limit behavior, Worker auth, public-cache allowlist and cache headers | Worker tests + staging smoke tests |
| Performance | cold start, search, playback start, hot media, cache miss | Flutter DevTools + load tests |

Release gate:
- [ ] Flutter analyze and tests pass.
- [ ] Backend typecheck and tests pass.
- [ ] Prisma migrations are reviewed and deployable.
- [ ] Cross-user authorization tests pass.
- [ ] Playback rights and territory tests pass.
- [ ] Cloudflare staging smoke tests pass.
- [ ] Audio tested on at least three representative real devices.
- [ ] Accessibility and reduced-motion audit completed.
- [ ] Performance/load test results recorded.
- [ ] No subscription, billing, or paywall surface exists.

## 24. Implementation priority

1. Foundation: shell/navigation, auth session, repositories, global PlayerController, rights boundary.
2. Core: Library, Favorites, Recently Played, local cache/outbox.
3. Media: AudioEngineAdapter, queue, Now Playing, MiniPlayer, background audio.
4. Discovery: Search, Browse, Radio metadata and real stream capability.
5. Content: Song, Album, Artist detail using canonical catalog IDs.
6. Organization: playlist sync, share/deep links, library customization.
7. Advanced: lyrics enhancements, downloads, social/collaboration, AirPlay and platform-specific features.
8. Infrastructure: Cloudflare DNS/WAF/API edge, public metadata cache policies, provider resolver resilience, observability and staged load testing.


## 21. Provider resolution, fallback and traffic scale

### Provider fallback policy
Playback uses a modular ProviderResolver with independent adapters. Each adapter exposes search/resolve/health/capabilities and typed errors. A fallback is allowed only when it is contractually permitted, rights-compatible for the user's territory, and confidently matched to the same recording. Do not substitute a remix/live version or cache a signed stream URL.

Liner Desktop is not an approved Breezze fallback. Its current source-available license prohibits commercial deployment/distribution and extraction of core algorithms, and requires modified builds to use official Liner services. Do not embed, fork, rebrand, extract its resolver or depend on its private client behavior without explicit written authorization. See the separate scaling plan for the provider approval gate.

### Audio and Cloudflare
Audio is delivered directly from approved provider hosts to the Flutter audio engine. Do not store music in R2 or relay full audio through Workers/NestJS by default. Cloudflare protects the API, applies WAF/rate limits and caches only public, non-personalized metadata/assets.

### One-million-active-listener engineering target
One million concurrent users is a target to prove with workload models and staged load tests, not a guarantee supplied by Cloudflare. Keep NestJS stateless and horizontally scalable; use PostgreSQL connection pooling/query budgets, Redis for bounded ephemeral caches, BullMQ for non-interactive jobs, per-provider concurrency limits/circuit breakers, cursor pagination and request coalescing. Test 10k → 50k → 100k → 250k → 500k → 1M virtual active clients, including cold-cache bursts, provider throttling and origin failures. Record p95/p99 latency, cache hit ratio, DB saturation, queue age, provider failures and playback resolution/start success.

See `infra/cloudflare/README.md` and `docs/architecture/BREEZZE_ONE_MILLION_SCALING_PLAN.md` for cache keys, TTLs, invalidation, edge policy, capacity assumptions and release gates.

## 26. Implementation truth rule

This document defines the target architecture. A feature is **implemented** only when real behavior exists and its relevant tests pass. A proposed endpoint, interface, placeholder state, disabled control, or documentation entry is not implementation evidence. Update the gap register with evidence after each completed feature.
