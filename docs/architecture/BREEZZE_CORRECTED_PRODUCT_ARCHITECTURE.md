# Breezze corrected product and provider architecture

Status: architecture correction for PR #7. This document supersedes any statement that ytmusicapi grants Breezze streaming or download rights.

## Product contract

Breezze is a free, listener-focused music discovery and playback app. It has no subscriptions, paid tiers, artist portal, or artist upload workflow in this release. Flutter is the single UI codebase for Android, iOS, Linux, Windows, macOS, and Web.

The product's primary experience is a single Breezze player: one current item, one queue, one transport state, and one history pipeline. Browse, Search, Home, Albums, Playlists, Library, and Radio must dispatch commands to this same player. A provider-specific external app launch must never be represented as native playback.

## Critical provider correction

`ytmusicapi` is an unofficial YouTube Music client interface. It is not an official YouTube API, a licence, a distribution agreement, a streaming entitlement, or a stable service-level contract.

Breezze may use it for best-effort catalogue discovery and metadata where permitted:
- Search songs, albums, artists, and videos.
- Read public metadata, artwork references, durations, and provider identifiers.
- Discover chart-like or related content only where the upstream method actually exposes it; do not invent unsupported editorial feeds.

Breezze must not assume that `get_song()`, `streamingData`, adaptive formats, cipher/signature handling, or temporary media URLs authorize extraction, proxying, caching, playback, or offline downloads. Do not build a stream resolver around those fields.

Provider capability truth:
- YouTube Music metadata/search: supported on a best-effort basis.
- Native Breezze audio playback from ytmusicapi: unsupported.
- Breezze background audio / lock-screen transport for ytmusicapi tracks: unsupported.
- Breezze queue, shuffle, repeat, crossfade, gapless and native Play Next for ytmusicapi tracks: unsupported.
- Offline downloads from ytmusicapi: unsupported.
- Licensed lyrics, credits, ISRC rights, lossless and spatial-audio claims: unsupported unless a separately reviewed provider supplies the data and rights.
- YouTube videos: may be opened or embedded only through official YouTube player integrations that preserve required player UI, attribution, and restrictions. This is a video viewing feature, not a native audio source.

The app must display these capabilities honestly. Do not show active Download, Play Next, Add to Queue, Lossless, or background-playback affordances for metadata-only items.

## Provider architecture

Use separate interfaces for discovery and playable media. A catalogue provider returns normalized metadata, never a playable URL. A playback provider must explicitly return a rights-cleared playback grant with:
- provider and asset identifiers;
- territory and rights/availability decision;
- allowed action (full stream or bounded preview);
- supported quality/codec;
- expiring signed media URL or provider SDK session;
- expiry and attribution;
- download permission as a separate capability.

The backend rights decision is authoritative. A client cannot turn a metadata record into a playable track by guessing an ID or URL. The playback resolver must reject unknown providers and assets without an active rights record. Preview URLs must be separately scoped, short-lived, and incapable of granting full-track access. Downloads require a separate download right and offline lease; they are never implied by stream permission.

Recommended source strategy:
1. Keep ytmusicapi as a discovery adapter only, behind a provider interface, Redis cache, request coalescing, circuit breaker, timeout, bounded concurrency, and rate limits.
2. Add one or more playback adapters for catalogues that explicitly permit free streaming, or accept user-imported local audio. Evaluate each provider's licence, territories, attribution, API terms, rate limits, and persistence rules before enabling it.
3. Resolve all playable sources through the existing rights-aware playback endpoint and existing Flutter audio engine.
4. Keep official YouTube video viewing as a separate feature and separate model from audio tracks. Do not route it into the native audio queue.

## Canonical data model

Do not encode provider semantics only in a magic `bz:` string. Store:
- `id`: Breezze internal immutable ID;
- `providerId` and `providerAssetId`;
- `contentType`: `track | album | artist | playlist | music_video | radio_station`;
- `metadataStatus`: `available | stale | unavailable`;
- `playbackCapability`: `native_stream | preview | official_video_player | local_file | unavailable`;
- `downloadCapability`: explicit boolean from provider and rights decision;
- `territories`, `explicit`, `durationMs`, `discNumber`, `trackNumber`, `isrc` only when actually supplied and verified;
- `sourceAttribution` and `metadataFetchedAt`.

Keep catalogue entities distinct from playback assets. An album can contain tracks whose playback rights differ. A search result is not a playable object by default.

## Backend responsibilities

- Provider registry: capability declarations are enforced by controllers and services.
- Discovery service: normalized metadata only; source and fetchedAt included; cache keys include provider, query, locale/territory, and schema version.
- Catalog resolver: deduplicate using provider ID + provider asset ID; never claim a verified album/discography relationship from fuzzy search.
- Rights service: server-side entitlement checks for stream, preview, download, and territory.
- Playback resolver: only issues grants for explicitly enabled playback adapters. No fallback to YouTube extraction.
- Download service: only creates offline leases for explicitly downloadable rights-cleared assets.
- User data: playlists, favorites, library, history, preferences, and queue metadata belong to Breezze accounts and sync through Breezze APIs, not through ytmusicapi. Do not claim to sync the user's YouTube Music account.
- Radio: stations require a real linear-stream provider or a Breezze-generated queue of rights-cleared tracks. Metadata search alone is not radio.
- Lyrics: only show lyrics from a source with documented display/synchronization rights. ytmusicapi metadata does not establish lyric licensing.
- Recommendations: begin with transparent Breezze-side ranking from user library and listening events. Label recommendations as limited until sufficient events/catalogue coverage exist.
- Charts: use sources whose chart data and reuse are permitted; distinguish provider charts from Breezze listening charts.

## Flutter responsibilities

- One global PlayerController and AudioEngineAdapter for all native playable tracks.
- Every screen dispatches to PlayerController; no screen launches a separate audio session.
- Queue entries must reference playable asset IDs and retain source context. Reject unavailable/metadata-only tracks before insertion.
- Search and detail pages show a clear source/capability state. A metadata-only YouTube Music result may be saved as a catalogue bookmark, but must not be shown as a native-playable song.
- Music-video results use a distinct MusicVideo model and official player flow. Do not represent a video as an audio TrackInfo.
- Download controls are visible only when downloadCapability is true and the backend authorizes a download lease.
- Library saves metadata and Breezze playlists; it does not imply offline media possession or external-service account sync.
- The same layout adapts to mobile, tablet, desktop and web. Use a bottom tab bar on compact layouts and a navigation rail/sidebar on wide layouts; do not force a phone-only bottom bar onto desktop.
- Keyboard, pointer, remote/focus, screen-reader, reduced-motion, and scalable-text behavior must be implemented per platform rather than advertised as one universal interaction.

## Feature truth matrix

| Feature | Initial release rule |
|---|---|
| Home, Search, Browse, Library | Implement with real backend data and honest empty/loading/error states |
| Albums, artists, playlists | Metadata pages; native Play only for rights-cleared tracks |
| Favorites and user playlists | Breezze-owned data, persisted locally and synced when authenticated |
| Mini-player, Now Playing, queue | Operate only on the one native player session |
| Background playback and lock-screen controls | Native rights-cleared streams/local files only |
| Radio | Disabled until a real permitted live stream or rights-cleared generated queue exists |
| Music videos | Separate official YouTube player viewing; no native audio queue claim |
| Downloads/offline | Disabled until explicit download rights and offline lease are implemented |
| Lyrics/karaoke/translation | Disabled until licensed/supported source and synchronization are integrated |
| AirPlay/SharePlay/CarPlay/widgets | Platform-specific integrations; do not display controls until implemented and tested |
| Lossless/Hi-Res/Atmos/spatial audio | Never show without verified source format and a compatible playback path |
| Concerts | Optional event provider with territory coverage and source attribution |
| Social/group listening/family features | Later phases; require privacy, moderation, access-control, and synchronization design |
| Subscriptions/payments/artist portal | Out of scope; do not add billing or artist-facing surfaces |

## Security, scale, and operations

- All provider calls are server-side; secrets and cookies never ship in Flutter.
- Validate and normalize all provider IDs and URLs; allowlist outbound hosts; protect against SSRF.
- Apply per-user and per-IP rate limits, provider concurrency caps, bounded retries with jitter, timeouts, circuit breakers, and request coalescing.
- Cache metadata only within provider terms. Never cache temporary signed media URLs beyond provider-authorized rules.
- Use Cloudflare for edge caching of public, non-user-specific metadata and static assets. Never shared-cache authenticated library, profile, queue, or playback-authorization responses.
- Enforce tenant isolation in every user-owned query using authenticated user ID. Authorization is checked server-side on every mutation.
- Instrument provider latency, cache hit ratio, upstream failures, rights denials, playback start failures, queue transitions, and download lease failures. Do not log tokens, cookies, or signed URLs.
- A target of hundreds of millions of users is a capacity objective, not a guarantee. Validate it with load tests, queue/backpressure design, database partitioning strategy, CDN budgets, and provider contractual limits.


## Repository audit: remaining implementation gaps

The current repository is not yet feature-complete against the product contract. These are explicit gaps, not completed features:

- `DiscoveryService` still calls Apple Music RSS and iTunes lookup for song charts, new releases, artist albums, and album tracks. `dailyTop100` still requires `APPLE_MUSIC_DEVELOPER_TOKEN`. This must be migrated to ytmusicapi metadata methods where they are actually available, or the corresponding feed must be disabled with an honest unavailable state. It must not silently remain an Apple-backed dependency in a YouTube-primary architecture.
- The Flutter search adapter currently searches songs; the dedicated music-video query is separate. Album, artist, playlist, lyric, and typed result search are not yet a unified search implementation.
- The current sidecar exposes song search, track metadata, and Original Music Video search. It does not yet expose validated album, artist, playlist, chart, mood, or home-feed metadata endpoints.
- Personal YouTube Music library/history synchronization is not implemented and must not be claimed. Breezze's own favorites, playlists, and history are separate first-party data.
- Radio, licensed lyrics, offline downloads, and personalized recommendations are not supplied by the current sidecar. These remain disabled or Breezze-owned features built from eligible data.
- The repository still contains other Apple catalog discovery code and legacy Apple-specific screen names/providers. Remove or rename those dependencies as part of the discovery migration; do not leave Apple as a hidden requirement.
- Search results that are YouTube Music song metadata now show an unavailable native-playback message instead of launching an unrelated external audio session. Dedicated music-video results are tagged separately and use the official YouTube watch player. The global player rejects metadata-only song and video IDs from its native queue.
- The Web Drift database CI build passed in the previous quality run. The database executor and asset pinning still need runtime browser persistence tests, not only compilation.

## Acceptance gates

1. A metadata-only ytmusicapi item cannot receive a native playback grant or download lease.
2. A native playable track can be played from Search, Browse, Album, Playlist, Library, and Radio through the same PlayerController.
3. Mini-player, Now Playing, lock-screen controls, queue, shuffle, repeat, next/previous, and history all reflect the same session.
4. A mixed playlist does not silently drop unsupported tracks or skip to a different first track. Unsupported entries are visibly marked and excluded only with user-visible explanation.
5. Music videos are not represented as audio tracks.
6. No screen advertises download, lyrics, lossless, background playback, AirPlay, SharePlay, CarPlay, widgets, or social functions before their corresponding provider/platform capability is live.
7. Android, iOS, Linux, Windows, macOS, and Web builds and behavior tests pass independently.
8. Search, playback, download, and library APIs have integration tests for unsupported providers, territory denial, expired grants, rate limits, and malformed provider responses.
