# Breezze music providers — YouTube Music and Deezer

**App data roles (24 November 2026):** YouTube Music powers broad song discovery, metadata and official music-video search. Deezer powers artist/album metadata, global charts, source-dated releases, and 30-second audio previews. Home trending, Browse charts, the discovery catalog, artist discographies and album track lists now draw from these backend sources. Deezer `chart/0` is global, never represented as an official country or daily ranking.



The only external music catalogue providers are **YouTube Music** and **Deezer**. 
The internal `breezze_internal` adapter reads the app's own canonical track
records; it is not an external music streaming provider.

## YouTube Music
- Adapter ID: `youtube_music`.
- `ytmusicapi` supplies track, album and artist discovery metadata.
- Metadata does **not** give Breezze permission to extract or redistribute
  full-track YouTube audio. An official, visible video embed is a separate
  permitted experience where supported, subject to YouTube's conditions.
- Any native full-track playback remains behind a separate licensed source
  and an explicit territory-aware authorization decision.

## Deezer
- Adapter ID: `deezer`.
- Public API supplies normalized metadata and eligible Deezer preview clips.
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
