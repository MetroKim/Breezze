# Breezze discovery backends — YouTube Music + Deezer

**Current provider policy: 24 November 2026.** Only YouTube Music and Deezer are music discovery/preview sources. Breezze's internal canonical catalog is a data store, not another provider. Audius, Jamendo and Apple RSS/iTunes music catalog integrations are removed. Concert discovery uses a separate optional JamBase event-data feed, not as a music playback source.

## Responsibilities

| Surface | Source | Current delivery |
|---|---|---|
| Search songs and catalog matching | YouTube Music through `ytmusicapi` (primary), Deezer (fallback) | Server-side federated search and metadata |
| Artist search, discographies, album tracklists | Deezer public catalog API | Exact provider IDs, verified album relationships, artwork, track duration |
| Charts | Deezer global `/chart/0/tracks` | Global chart ranking; never represented as local or official daily Top 100 |
| New releases | Deezer global chart albums, hydrated via `/album/{id}` | Only albums with real `release_date` in last 30 days; not a complete new-release feed |
| Latest songs | Tracks drawn from verified recent Deezer chart albums | Explicitly labeled tracks from recent albums, not guaranteed individual recording release dates |
| Music videos | YouTube Music sidecar `/videos`; official YouTube video player | Visible embedded player only, with upstream controls |
| Audio previews | Deezer official `preview` field, rechecked per play | Short HTTPS `*.dzcdn.net` clip decoded by native Breezze audio engine |
| Home new-listener music | Deezer global chart | Source-attributed 30-second preview rail |

## Technical configuration

- `YTMUSIC_API_URL`: server-side Python `ytmusicapi` sidecar; no login cookies or secrets in Flutter.
- `YTMUSIC_ENABLED`: optional metadata provider toggle; enabled by default.
- `DEEZER_ENABLED=true`, `DEEZER_API_URL=https://api.deezer.com`: public Deezer metadata and preview API.
- `YOUTUBE_DATA_API_KEY` and `YOUTUBE_OFFICIAL_CHANNEL_IDS` are optional, server-only video discovery fallback variables. Both must be set before that fallback is active.
- `JAMBASE_DATA_API_KEY`: optional server-side live concert/event discovery; unrelated to music audio sourcing.

## Hard constraints

- YouTube Music via `ytmusicapi` does not grant native full-track playback or offline downloads. Never extract, rehost or hide playback via a YouTube player.
- Deezer catalog/search endpoints do not grant full-track delivery, ARL cookie decryption or offline downloads. When provided, a short preview remains a preview and must show source attribution.
- Only authorized first-party or properly licensed canonical recordings may receive a backend `stream.full` grant; a song appearing in search is not itself authorization.
- Provider outages remain isolated. Matching must not silently substitute live/remix/cover versions.
- Deezer `/chart/0` is a **global** ranking. The exact product label must disclose that global scope, including when the listener selects a country.
- For saved albums previously linked to Apple/iTunes numeric IDs, preserve the saved record but require re-search before associating with a Deezer numeric ID.

## Verification

- [x] Server API returns Deezer global charts, artist and album records with actual values, plus YouTube Music discovery (live production smoke).
- [x] Live `/discovery/releases/albums` returns only records with verified Deezer release dates.
- [x] Native search, Home, Browse and album playback routes are wired to Deezer preview IDs in the Flutter source.
- [ ] Flutter analyze + unit tests pass on current `main`.
- [ ] Android emulator decodes and seeks an actual official Deezer preview.
- [ ] iPhone simulator decodes and seeks an actual official Deezer preview.
- [ ] Separately licensed full commercial catalog streaming (not enabled by these metadata/preview APIs).
