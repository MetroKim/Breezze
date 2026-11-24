# Breezze music providers — YouTube Music and Deezer

**Requested source ownership (24 November 2026):** YouTube provides official visible music-video playback. Deezer is the primary music metadata/search backend for tracks, charts, artists, albums and releases, with short official previews. YouTube Music is the **requested full-song audio backend** for the native Breezze player, but that role is **not yet authorized or live**: the public third-party audio-only playback API/license is unavailable. Its unofficial `ytmusicapi` adapter stays metadata-only and can supplement Deezer for track matching and YouTube official video discovery. Deezer `chart/0` is global, never a regional or guaranteed daily ranking.



The only external music catalogue providers are **YouTube Music** and **Deezer**. 
The internal `breezze_internal` adapter reads the app's own canonical track
records; it is not an external music streaming provider.

## YouTube Music (primary native audio target; not yet authorized)
- Adapter ID: `youtube_music`.
- `ytmusicapi` supplies track, album and artist discovery metadata.
- Metadata does **not** give Breezze permission to extract or redistribute
  full-track YouTube audio. An official, visible video embed is a separate
  permitted experience where supported, subject to YouTube's conditions.
- Native full-track playback from YouTube Music requires explicit Google-authorized third-party audio-only playback access, territories, stream lifecycle and background rights. No such public SDK or direct licensed API is currently configured. The adapter deliberately has `playback: false` until authorization is obtained and real sessions pass native/production tests.

## Deezer
- Adapter ID: `deezer`.
- Public API is Breezze's primary catalog/search source and supplies normalized metadata and eligible Deezer preview clips.
- Provider capability flags for full playback, availability and downloads
  are false. Deezer preview access does not authorize full-song delivery.
- ARL cookies or undocumented media retrieval are not acceptable replacements
  for an approved licensed integration.

## Internal catalogue, removal and rights enforcement
- Breezze's canonical track records can be used for saved music, favorites
  and playlists, but music files need their own legal `stream.full` grant.
- Audius and Jamendo adapters, configuration, and normal playback routes were
  removed at the user's direction.
- Old provider IDs are not queueable or automatically converted into songs
  from another recording.
- Do not claim YouTube/Deezer catalog-wide full playback until permissions and
  actual playable sources for those recordings have been validated.

## Release checks
1. Federated discovery returns only `breezze_internal`,
   `youtube_music`, and `deezer`, while isolating provider failures.
2. Retired provider lookups return `PROVIDER_NOT_FOUND`.
3. Metadata-only results and previews cannot bypass full-stream licensing.
4. Native emulator, production auth and queue tests are independent gates.
