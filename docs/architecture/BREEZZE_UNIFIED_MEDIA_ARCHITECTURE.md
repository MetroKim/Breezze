# ADR-004 — Breezze unified media search and playback (2026-11-26)

**Decision status:** Product architecture approved; full commercial audio distribution NOT yet authorized or operationally verified. This document supersedes any older advice to open Spotify or Deezer applications from Breezze.

## Product intent

Breezze is the only listener-facing app: one search field, one library, one queue coordinator, and one Now Playing experience. Spotify and Deezer are candidate AUDIO catalogue backends (Spotify primary; Deezer secondary). YouTube Data API supplies VIDEO discovery, and the official visible YouTube embedded player plays embeddable videos in Breezze. LOCAL means user-selected device files; LIBRARY means the signed-in user's saved tracks and playlists. A provider app handoff is **not** the requested product.

**Critical distinction:** a catalogue API token, track ID, title, album cover, preview URL or signed-in account does not provide full audio bytes or grant distribution rights. The database's lack of stored audio is fine, but real streaming still needs an authorized delivery integration. NEVER relabel 30-second previews as whole songs.

## Four search scopes

| Scope | Discovery / data access | Selection behavior | Status |
| --- | --- | --- | --- |
| **Audio** | Breezze API -> Spotify Web API first, Deezer catalogue fallback; separately attributed, provider-scoped results | Queue *only* after exact recording and current playback entitlement are verified; metadata-only results show availability honestly | Backend parallel search exists; full Spotify/Deezer songs not authorized |
| **Video** | Breezze API -> official YouTube Data API | Open official visible embedded YouTube IFrame player inside Breezze, no audio extraction, background-only hidden player or caching | Backend and in-app video integration exist; live acceptance remains required |
| **Local** | On-device file picker and future permission-scoped indexed local media | Native decoder via Breezze audio/video control surface; never upload the file merely to search | File pickers exist; full local indexing/search is future work |
| **Library** | Authenticated Breezze saved-item references, account-scoped local cache and durable backend sync | Resolve fresh playback permission when played; preserve previously saved provider IDs | Existing user-owned data; verify complete sync and restore |

Search with less than two characters skips remote provider requests. Preserve typed source IDs (`bz:spotify:<id>`, `bz:deezer:<id>`, `bzv:<youtubeId>`), separate attribution, timeouts, rate limits, request coalescing, and partial-failure behavior. Do not silently rewrite Spotify attribution as Deezer or blend provider catalogues to circumvent restrictions.

## One user experience, multiple authorized rendering paths

```text
Breezze Search: Audio | Video | Local | Library
        |
Breezze UI + unified coordinator (identity, queue, state, focus, interruptions)
        |
Breezze NestJS API (auth, rights, recording matching, territory, providers)
        |
        +-- AUDIO CATALOGUE: Spotify primary -> Deezer secondary [metadata today]
        |      |
        |      +-- FULL AUDIO: only if partner grants embedded playback / raw
        |          delivery for this exact recording and user; otherwise BLOCK
        |
        +-- VIDEO: official YouTube metadata -> visible YouTube embedded player
        |
        +-- LOCAL: user file picker -> device-native audio/video engine
        |
        +-- LIBRARY: Supabase / local user references -> fresh playable source
        |
        +-- LYRICS: permitted third-party lyrics endpoint, attribution and
               territory/display rights; synced text if actually available
```

The coordinator exposes a consistent Now Playing UI, play/pause intent, queue/selection and error state. It delegates to **the correct underlying renderer**; a YouTube IFrame is not an arbitrary AVPlayer/ExoPlayer stream. Provider DRM, media-session controls, ads, Premium restrictions and player branding must remain intact. Only one renderer has audio focus. Switching audio/video must pause the previous renderer and may require a new entitlement and synchronization state; do not promise seamless same-recording switching without a verified association.

### Provider integration matrix

| Provider capability | Spotify | Deezer | YouTube |
| --- | --- | --- | --- |
| Catalogue / search | Official Web API with server-only app credentials | Public API catalogue | Official Data API v3 |
| Full-track **raw audio** to Breezze native decoder | **No** under ordinary Web API / client credentials | **No** under public catalogue API | **No** under standard YouTube API |
| In-app full-track playback path | Web Playback SDK on eligible web clients for Spotify Premium, subject to Spotify policy/approval. Android/iOS App Remote controls Spotify's own app and is **not** an embedded decoder | Only if Deezer supplies an appropriate approved commercial in-app playback agreement/SDK | Visible official embedded player for embeddable videos, subject to YouTube rules |
| Offline downloads into Breezze | Not authorized by ordinary API | Not authorized by public API | Not authorized by standard embedded API |
| Ads API | Spotify advertising campaign APIs are not music-stream APIs | Not a media delivery path | Not a media delivery path |

**Compliance gate:** Spotify's published Developer Policy restricts integrating Spotify content or streams with another service, crossfading/mixing/re-processing Spotify media, and commercial streaming. Even if individual playback SDKs work, a dual-source Spotify+Deezer commercial player cannot be advertised as authorized without applicable partner permissions. Keep provider search sources distinctly identified and do not turn Spotify metadata into an alternate provider playback URL. Spotify Web Playback SDK is **browser-specific** and requires eligible Premium authorization. These restrictions must be resolved before consumer release, not hidden in code.

## Backend and API contracts (current paths versus proposed work)

**Exists:**
- `GET /api/v1/providers/music/search?q=...`: NestJS searches Spotify and Deezer independently; results are source-attributed and Spotify is first.
- `GET /api/v1/providers/youtube/videos/search?q=...`: official YouTube video discovery.
- Rights-gated canonical/internal media resolver and separate provider resolver; metadata-only adapter capabilities are `playback=false`.
- Flutter Audio and Video discovery, Library search, local file pickers and an in-app visible YouTube player.
- LRCLIB client lookup via `HttpLyrics`; server's own lyrics endpoint currently reads stored rights-gated rows. Neither proves every recording has licensed lyrics.

**Needed:**
1. Four explicit source tabs and a permissions-respecting local catalogue/search index (the picker is an interim Local action).
2. A provider-agnostic `MediaIntent` envelope: `mediaKind` (audio, video, local), `catalogueProvider`, `providerTrackId`, `canonicalId`, `authorizationMode`, `playbackStatus`, `expiresAt`, `attribution`; user/library ID cannot act as an audio grant.
3. Rights/entitlement/territory-aware full audio partner integration, tested on each OS, **before** advertising commercial full songs. If unavailable, return `FULL_TRACK_NOT_AUTHORIZED` and preserve the metadata item.
4. Exact-match audio/video association (recording ID, ISRC where available, version and user confirmation), no silent remix/cover substitutions.
5. Lyrics API authorization/attribution/availability checks and synched-versus-unsynched UI states. Do not scrape or silently persist restricted lyric text.
6. Signed-out/signed-in auth and account isolation tests, emulator media focus and queue switching tests, real authorized media start/seek/pause tests, recovery, CI on current commit, staged deployment review.

## Durable data: preserve, do not rebuild

No catalog MP3, FLAC, music video, lyric text or provider credential is required in the user's application database simply to enable search. The database stores references, playback/audit state and user-generated data. **Do not reset data** to switch catalogue provider priorities.

- **Supabase** stays the user identity and existing `public.profiles`, `public.user_library`, `public.pinned_playlists` system. Maintain RLS/account ownership.
- **Railway Postgres** remains the existing persistent service used by the NestJS/Prisma stack until ownership and migration history are fully audited; do not assume its rows are a replica of Supabase.
- **Railway Redis** stays cache/coordination; never treat it as a durable library source of truth.
- Keep existing provider IDs and saved-item links intact. Any migrations must be additive, backwards compatible, with tested rollback and a restorable backup.
- Verify backup/PITR coverage on the actual Supabase plan and Railway Postgres volume/snapshot policy; **a healthy deployment is not proof of backup or recovery**.
- Keep Spotify/Deezer/YouTube tokens and any provider-specific grants out of Flutter binaries, git, logs and shared caches. Rotate any client secret already pasted into chat before production use.

## Release gates (must be evidence-backed)

- [x] Architecture acknowledges one Breezze UI with separate authorized rendering paths.
- [x] Spotify-first / Deezer-second metadata discovery and official in-app YouTube videos have implementation paths.
- [ ] Verify live authenticated Spotify search with rotated credentials and provider quotas.
- [ ] Validate commercial Spotify+Deezer combination permission / approval, not just technical API connectivity.
- [ ] Obtain approved full-song in-app audio licensing/delivery, and test full-length tracks end-to-end.
- [ ] Implement/index Local search and finish four-scope UI acceptance.
- [ ] Verify complete lyric availability, display grants and attribution per recording.
- [ ] Demonstrate restorable database backups, account isolation, queue switching and current-SHA green CI.

## Official integration sources

- Spotify Developer Policy: https://developer.spotify.com/policy
- Spotify Web Playback SDK: https://developer.spotify.com/documentation/web-playback-sdk
- Spotify mobile SDK overview: https://developer.spotify.com/documentation/android
- YouTube IFrame API: https://developers.google.com/youtube/iframe_api_reference
- YouTube Data API: https://developers.google.com/youtube/v3
- Supabase backups: https://supabase.com/docs/guides/platform/backups
