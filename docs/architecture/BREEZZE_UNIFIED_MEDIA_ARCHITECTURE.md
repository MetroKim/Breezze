# ADR-004 — Breezze unified media search and playback (2026-11-26)

**Decision status:** Product architecture approved; full commercial audio distribution NOT yet authorized or operationally verified. This document supersedes any older advice to open Spotify or Deezer applications from Breezze.

## Product intent

Breezze is the only listener-facing app: one search field, one library, one queue coordinator, and one Now Playing experience. Spotify and Deezer are candidate AUDIO catalogue backends (Spotify primary; Deezer secondary). YouTube Data API supplies VIDEO discovery, and the official visible YouTube embedded player plays embeddable videos in Breezze. LOCAL means user-selected device files; LIBRARY means the signed-in user's saved tracks and playlists. A provider app handoff is **not** the requested product. The user should choose only **Audio, Video, Library or Local**; no Spotify/Deezer picker or separate source shelf is part of the interaction.

**Critical distinction:** a catalogue API token, track ID, title, album cover, preview URL or signed-in account does not provide full audio bytes or grant distribution rights. The database's lack of stored audio is fine, but real streaming still needs an authorized delivery integration. NEVER relabel 30-second previews as whole songs.

## Search-first progressive disclosure (implemented in Flutter)

**UI rule (2026-11-26):** On initial entry to Search, show only Breezze's search field, suggested queries, and history. Do **not** show Audio / Video / Library / Local filters. A typed query first runs the Audio search (Spotify primary, Deezer secondary) and displays its results or an honest empty/error state. **Only after that request resolves**, reveal a sticky, horizontally scrollable source selector directly under the search field:

```text
BREEZZE SEARCH
[ Search a song or artist                         ]
     (no media-source choices before the first response)

After results arrive:
[ Search a song or artist                         ]
[ AUDIO ] [ VIDEO ] [ LIBRARY ] [ LOCAL ]     <- chosen source is highlighted
  One deduplicated song list (provider is not a user-selectable filter)
  ...
```

Selecting a media kind retains the exact same search text. Spotify and Deezer are internal audio catalog backends, **not user-selectable music apps or source filters**. **Audio** queries the existing Spotify/Deezer endpoint; **Video** switches to YouTube music-video results and opens the official visible YouTube player; **Library** searches only the signed-in account's library; **Local** never contacts the backend and searches only explicitly selected device audio files. The Local button reveals an opt-in **Choose audio files** picker; it is not a blanket permission to enumerate a user's storage. Switching categories must cancel/discard stale requests. The four choices remain accessible even if the selected source returns zero matches. On clearing the query, hide the choices again and show recent/suggested searches.

**Design reference:** BitChord's *post-results filtering and persistent search field* interaction inspired the structure. Breezze's Flutter layout, styling, and components are independently implemented; no GPL-3.0 BitChord source code, assets, or UI component implementations are copied.

**Repository implementation:** `apps/mobile/lib/features/search/search_screen.dart`; coverage `apps/mobile/test/search_typeahead_test.dart`. This is a UI/source-scope feature, **not evidence that Spotify or Deezer full commercial audio streams work**.

## Artist-first search and Spotify-primary artist pages (2026-11-26)

**Search UX:** The user types an artist name; Breezze queries `GET /api/v1/providers/spotify/artists/search?q=...` alongside the existing unified audio catalog. Matching Spotify artist portraits + names appear first as clickable rows, then Spotify/Deezer audio song results ranked with exact artist credit before partial credit, and finally Spotify-genre-derived similar-search chips. No provider picker appears. Existing Audio / Video / Library / Local filters still appear only after the first search.

**Artist identity:** `GET /api/v1/providers/spotify/artists/:artistId` uses Spotify `GET /artists/{id}`; artist pictures, name, genres and followers are displayed when Spotify provides them. Identity is always Spotify-first. Saved legacy Breezze artist references resolve by exact Spotify name rather than silently reassigning a different artist's catalog ID. Spotify artists' top-tracks, browse-new-releases and related-artists endpoints are not assumed available after the 2026 API changes; tracks are artist-ID-verified `GET /search?type=track` results with lead credit ranked first, albums/singles come from `GET /artists/{id}/albums`, and newest releases from verified release dates. Spotify album pages use `GET /albums/{id}` and `GET /albums/{id}/tracks`.

**Optional Deezer fallback:** The artist composer `ArtistCatalogService` queries Deezer `GET /search/artist` only after a successful Spotify artist profile and requires exactly ONE unique Deezer artist ID with the same normalized full name. Ambiguous names return no supplement. Deezer `GET /artist/{id}/top`, `/albums`, and `/related` can fill an **entire missing** songs or albums section, plus separately labeled related artist suggestions. A populated Spotify section is never mixed with Deezer tracks/albums. Every fallback record retains `providerId:'deezer'` and its Deezer URL; a Deezer ID must not be treated as Spotify or a streaming license. Supplemental metadata is source-labeled in Flutter and cannot silently replace the primary artist portrait or identity. Deezer's partial endpoint outages do not hide Spotify data.

Spotify's official [developer policies](https://developer.spotify.com/policy) and [design guidance](https://developer.spotify.com/documentation/design) limit placing Spotify content next to content from competing services, and require attributable source links/branding. Accordingly **mixed Spotify + Deezer artist-page fallback is disabled in production unless `ARTIST_DEEZER_FALLBACK_APPROVED=true`**, to be set only after documented partner/legal permission; development/test environments can validate the code path. This is an explicit release gate, not a claim that Spotify has approved a mixed catalog. Metadata never grants full-track streaming or download rights.

**Concerts and tours:** Neither provider's standard music-catalog artist endpoint supplies a reliable tour schedule. The existing separate `GET /api/v1/discovery/concerts` integration with JamBase Data is reused only for verified Spotify artist pages and a valid selected country. It retains only future events whose performer credit exactly matches the artist's name and shows venue, date, city, and source attribution. If the JamBase key/region is unavailable, the Tours section clearly reports that no verified listings are available rather than inventing concerts. These third-party events are not presented as Spotify/Deezer metadata.

**Library and privacy:** Follow/Pin uses the owner-scoped `catalog:sp_<SpotifyArtistId>` identity. Account switching invalidates pending requests. No Prisma migration, database reset, raw music files or global lyrics catalog is necessary for this feature. Existing user playlists and followed artists are preserved; older artist identities remain until a deliberate verified migration.

**Verification:** Unit tests cover exact-name/ambiguous matches, per-section Spotify preference, Spotify outages, Deezer partial failures and the production approval gate; Flutter tests cover artist-first navigation, query suggestions and Spotify-specific details. GitHub Actions remain the authoritative build/emulator acceptance gate and must pass before marking this release-ready.

## Four search scopes

| Scope | Discovery / data access | Selection behavior | Status |
| --- | --- | --- | --- |
| **Audio** | Breezze API -> Spotify Web API first, Deezer catalogue fallback; one deduplicated recording list while retaining legally required source provenance | Queue *only* after exact recording and current playback entitlement are verified; metadata-only results show availability honestly | Backend parallel search, ISRC/title/artist/duration dedup and fallback exist; full Spotify/Deezer songs not authorized |
| **Video** | Breezze API -> official YouTube Data API | Open official visible embedded YouTube IFrame player inside Breezze, no audio extraction, background-only hidden player or caching | Backend and in-app video integration exist; live acceptance remains required |
| **Local** | On-device file picker and future permission-scoped indexed local media | Native decoder via Breezze audio/video control surface; never upload the file merely to search | File pickers exist; full local indexing/search is future work |
| **Library** | Authenticated Breezze saved-item references, account-scoped local cache and durable backend sync | Resolve fresh playback permission when played; preserve previously saved provider IDs | Existing user-owned data; verify complete sync and restore |

**Current unified music response:** `GET /api/v1/providers/music/search?q=...` returns `tracks: [{ providerId, providerTrackId, title, artist, durationSec, isrc?, alternateCatalogIds }]` together with the legacy `providers` array. Flutter uses `tracks` preferentially; during rolling deployments it conservatively deduplicates the older provider shelves. The first catalog's identity and artwork are never silently substituted with those of a competing catalog. `alternateCatalogIds` are **discovery-only** associations, not audio URLs or playback fallbacks. Exact ISRC takes precedence; without it title, artist and a duration difference within three seconds must match. Distinct ISRCs, remixes and differing lengths are not merged.

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
1. Expand the existing four post-results media-kind filters with permission-scoped device media indexing (the picker is the current Local action).
2. A provider-agnostic `MediaIntent` envelope: `mediaKind` (audio, video, local), `catalogueProvider`, `providerTrackId`, `canonicalId`, `authorizationMode`, `playbackStatus`, `expiresAt`, `attribution`; user/library ID cannot act as an audio grant.
3. Rights/entitlement/territory-aware full audio partner integration, tested on each OS, **before** advertising commercial full songs. If unavailable, return `FULL_TRACK_NOT_AUTHORIZED` and preserve the metadata item.
4. Exact-match audio/video association (recording ID, ISRC where available, version and user confirmation), no silent remix/cover substitutions.
5. Lyrics API authorization/attribution/availability checks and synched-versus-unsynched UI states. Do not scrape or silently persist restricted lyric text.
6. Signed-out/signed-in auth and account isolation tests, emulator media focus and queue switching tests, real authorized media start/seek/pause tests, recovery, CI on current commit, staged deployment review.

## Source visibility versus non-negotiable platform attribution

**User-facing preference:** Breezze is the only app, and search must not ask the user whether to choose Spotify, Deezer or YouTube. One search result represents a confidently matched recording; the selected media kind determines its behavior. This is independent of the external providers' commercial rights.

**Platform constraint:** Spotify's Developer Policy and Branding Guidelines require visible Spotify attribution and a link when Spotify metadata or artwork appears, and restrict mixed-source layouts. YouTube's API Services Developer Policies require YouTube attribution for official video results and prohibit hiding the official player's branding. Therefore the requested **completely unbranded** Spotify and YouTube results cannot be shipped with standard public API credentials. Keep legally required attribution, obtain written partner permission for a different treatment, or use an independently licensed catalogue with approved display rights. Removing the provider picker/shelf is a UX implementation, **not** approval to suppress mandatory brand marks.

Breezze's application databases need **no global audio/video/lyrics file library** for this design. Spotify/Deezer/YouTube API calls provide dynamic searchable metadata; the permitted YouTube embed supplies video playback; LRCLIB provides best-effort synced/plain lyrics under its own terms. Supabase/Railway persist user library references, access state, normalized ID mappings and optional lawful cache; they are **not** a substitute for licensed full-song streaming or lyrics reproduction rights.

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
- [x] Hide media-kind controls until search response; implement Audio / Video / Library / Local filters and explicitly selected local-file title matching.
- [x] Add one backend music `tracks` list (ISRC-first, safe title/artist/duration fallback) and remove per-provider headings from Flutter Search; preserve originating source IDs and mandatory attribution.
- [ ] Obtain written partner authorization for displaying Spotify and Deezer in the desired combined list and finalize required Spotify-brand logo/link treatment; today's metadata preview is not release-cleared.
- [ ] Verify Flutter search widget tests and emulator UI on the latest commit; extend Local beyond selected files only with explicit platform permission and indexing acceptance.
- [ ] Verify complete lyric availability, display grants and attribution per recording.
- [ ] Demonstrate restorable database backups, account isolation, queue switching and current-SHA green CI.

## Official integration sources

- Spotify Developer Policy: https://developer.spotify.com/policy
- Spotify Web Playback SDK: https://developer.spotify.com/documentation/web-playback-sdk
- Spotify mobile SDK overview: https://developer.spotify.com/documentation/android
- YouTube IFrame API: https://developers.google.com/youtube/iframe_api_reference
- YouTube Data API: https://developers.google.com/youtube/v3
- Supabase backups: https://supabase.com/docs/guides/platform/backups
