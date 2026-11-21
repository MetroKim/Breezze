# Breezze Multi-Source Music Architecture

**Status:** Approved product direction; implementation is staged behind provider capability and rights gates.
**Reference:** BitChord's architectural separation of catalogue discovery, source resolution, and native playback.
**Important:** This is an independently designed Breezze architecture. It does not copy BitChord source code, assets, private endpoints, or implementation.

## 1. Product decision

Breezze adopts a multi-source architecture. It is not a YouTube Music wrapper and it is not tied to one catalogue or playback vendor.

Breezze owns:
- The listener-facing product, navigation, library, playlists, favorites and history.
- Canonical track, artist, album and playlist identity.
- The global queue and the single native playback session.
- Source selection, rights checks, attribution, provider health and failover policy.
- User settings, recommendations and account data.

Providers supply only the operations they explicitly support. A provider's ability to return metadata does not imply playback, download, lyrics, radio or redistribution rights.

## 2. Three independent planes

### A. Catalogue plane

Responsible for search and metadata:
- Track, artist, album, playlist and video discovery.
- Charts, genres, moods and editorial collections when a provider exposes them.
- Normalization, de-duplication, recording matching and canonical IDs.
- Attribution and source provenance.

ytmusicapi remains a best-effort, unofficial YouTube Music metadata adapter. It is not the playback resolver. It is isolated behind the NestJS backend and Python sidecar; no Flutter screen calls YouTube endpoints directly.

### B. Playback plane

Responsible for finding an authorized playable source:
1. The client asks Breezze to play a canonical track.
2. The backend authenticates the user and resolves the canonical track.
3. The rights service checks action, territory, time window, takedowns and attribution.
4. The provider registry filters to enabled adapters that declare playback support.
5. Each candidate must return a source for the same recording/version, with format, expiry and provider identity.
6. Breezze selects the best eligible source using explicit priority and quality policy.
7. The client receives a short-lived playback grant and streams directly from the provider host or Breezze's licensed CDN.
8. On expiry, the client requests a new grant; it never reuses stale signed URLs.

Metadata-only providers are never candidates. There is no fallback to extracted YouTube stream URLs, arbitrary third-party URLs, or unrelated remixes.

### C. Player plane

The Flutter app owns one global native audio engine per active application session:
- Android: Media3/ExoPlayer through the selected Flutter engine.
- iOS/macOS: AVFoundation through the selected Flutter engine.
- Linux/Windows/Web: platform engine supported by the chosen Flutter audio package and its tested codecs.
- Mini-player, Now Playing, queue, shuffle, repeat, autoplay, seek, volume and playback state all dispatch to the same PlayerController.
- OS media controls and background playback are projections of that same player state.

A provider never creates a second player or owns Breezze's queue. The provider returns a playable source; the player handles it.

## 3. Provider plugin contract

Breezze uses a server-side provider adapter contract inspired by the concept of BitChord addons, but independently implemented.

Each adapter has:
- Stable provider ID and adapter version.
- Human-readable name and attribution requirements.
- Enabled/disabled state and explicit priority.
- Capabilities: search, metadata, albums, artists, playlists, videos, charts, radio, lyrics, availability, playback and downloads.
- Typed request/response schemas and typed error mapping.
- Health state, request timeout, concurrency budget and circuit breaker.
- Terms/rights review status and permitted territories/actions.

Operations are capability-gated. Unsupported operations return a typed UNSUPPORTED result; they must never fabricate URLs or empty success responses.

Provider registration is server-controlled. Do not load arbitrary user-supplied code or fetch arbitrary manifest URLs. Any future remote addon must be allowlisted by an administrator, signature-verified, sandboxed, schema-validated and protected against SSRF.

### Provider result types

- ok: validated result.
- unsupported: adapter does not implement the operation.
- not_found: provider has no matching item.
- unavailable: temporary upstream failure.
- rate_limited: provider quota or throttle response.
- rights_denied: the provider or territory cannot serve the requested use.
- invalid_response: upstream schema failed validation.

Retry only transient failures, with bounded exponential backoff and jitter. Never retry rights denials or not-found responses.

## 4. Initial provider roster

| Provider | Catalogue | Native playback | Download | Role |
|---|---:|---:|---:|---|
| YouTube Music via ytmusicapi | Yes, best-effort | No | No | Initial metadata/discovery |
| Breezze licensed media/CDN | Internal catalogue | Yes, only with explicit rights record | Only with download rights | First-party authorized media |
| User-owned local files | Local metadata | Yes, on supported platforms | Already local | User-controlled playback |
| Additional licensed providers | When integrated | Only after rights/terms approval | Only if explicitly licensed | Future pluggable sources |
| Official YouTube video player | Video metadata/launch | Separate official player; not Breezze audio | No | Optional music-video viewing |

Do not present an unimplemented provider as connected, available, or production-ready.

## 5. Track identity and source matching

Canonical Breezze IDs are independent of provider IDs. Provider mappings are stored server-side and are not trusted as user-supplied authorization.

Matching priority:
1. ISRC plus version/recording constraints, when verified.
2. Exact provider mapping already verified by Breezze.
3. Normalized title + primary artist + duration tolerance, with conservative confidence threshold.
4. Manual/admin review for ambiguous matches.

Never silently substitute:
- a remix for an original;
- a live recording for a studio recording;
- a cover for the original;
- clean/explicit variants when the user requested the other;
- a music video for an audio track;
- a different master/version when the source is uncertain.

## 6. Flutter application contract

Flutter calls only Breezze API endpoints. It receives normalized catalogue objects and opaque canonical IDs. It never scrapes YouTube, resolves provider stream URLs, stores provider cookies, or decides whether content is licensed.

The global PlayerController accepts only:
- an authorized, expiring playback grant from the backend; or
- a user-selected local file URI.

The queue stores canonical track IDs plus source context, not raw provider stream URLs. When a queued track reaches the front, the backend resolves a fresh grant. This avoids expired URLs sitting in long-lived queues.

The UI displays capability-aware actions:
- Play is enabled only when Breezze can obtain a playable source.
- Download is enabled only when download rights and platform storage support exist.
- Lyrics, radio, AirPlay/casting, lyrics translation, karaoke and crossfade are shown only when implemented and supported by the platform.
- Music-video playback is clearly separate from the audio queue.

## 7. Backend and scale

- Cloudflare: DNS, TLS, WAF, bot controls, route limits and explicit public metadata cache.
- NestJS: authentication, canonical catalogue, provider registry, matching, rights, playback grants and user APIs.
- Python ytmusicapi sidecar: isolated metadata adapter only.
- PostgreSQL: canonical data, user library, playlists, provider mappings, rights, takedowns and audit records.
- Redis: bounded metadata cache, provider health, request coalescing and short-lived coordination.
- Audio: direct from approved provider/CDN to client; do not proxy audio segments through Workers or NestJS by default.

Cache only public deterministic metadata. Never shared-cache user libraries, credentials, cookies, rights decisions, playback grants or signed URLs. Include locale, territory, filters, pagination and schema version in public cache keys.

Cloudflare does not itself guarantee a million concurrent listeners. Capacity remains subject to provider quotas, origin/database budgets, geographic load tests and playback-start SLOs.

## 8. Free listener model

Breezze has no subscriptions, tiers, payment flows or artist portal in this release. Free describes the listener-facing product model; it does not grant Breezze rights to stream third-party recordings for free. Every provider still needs an appropriate license or permitted use.

## 9. Delivery phases

### Phase 0 — Remove architectural contradictions
- [x] Keep ytmusicapi metadata-only.
- [x] Keep one global PlayerController and native audio engine.
- [ ] Remove dormant client-side YouTube/InnerTube adapters and their dependencies.
- [ ] Remove Liner-specific and external-player fallback assumptions from generic source-chain code.
- [ ] Ensure all provider access is backend-owned.

### Phase 1 — Provider foundation
- [ ] Extend backend provider contract with capabilities, manifests, typed results, health and playback-source schema.
- [ ] Add server-controlled registry and provider enable/priority configuration.
- [ ] Add contract tests for every capability and unsupported operation.
- [ ] Add provider-specific recording mappings and source provenance.
- [ ] Keep actual playback provider roster empty until a rights-cleared provider is configured.

### Phase 2 — Catalogue
- [ ] Complete typed search across songs, artists, albums, playlists and videos.
- [ ] Add metadata adapters for releases, charts, genres and moods where available.
- [ ] Remove remaining Apple RSS/iTunes hidden dependencies or explicitly disable unsupported feeds.
- [ ] Build a normalized merged search response with de-duplication and source attribution.

### Phase 3 — Playback
- [ ] Add one backend playback resolver over approved provider adapters and Breezze licensed CDN.
- [ ] Return short-lived, typed playback grants, never provider-specific secrets.
- [ ] Resolve queue entries when they reach the front.
- [ ] Implement bounded failover only for the same recording and same rights scope.
- [ ] Validate background, lock-screen, seek, queue, repeat, shuffle and interruptions on each OS.

### Phase 4 — Optional capabilities
- [ ] Radio, lyrics, offline downloads, casting, group sessions, recommendations and social integrations each require their own adapter/capability and acceptance tests.

## 10. Release gates

A provider cannot be enabled for production playback until:
- Its identity, contract, terms and permitted territories are recorded.
- Rights for full streaming are documented.
- Its adapter passes source validation and security tests.
- URL expiry/refresh and error mapping are tested.
- The same recording/version is verified.
- Playback start, background behavior, seek and failover pass on supported platforms.

No UI or documentation may claim native streaming, offline downloads, lossless audio or a provider capability until the corresponding end-to-end release gate passes.
