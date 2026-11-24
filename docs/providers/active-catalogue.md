# Breezze music providers — YouTube Music and Deezer

**Authoritative three-source-role contract (24 November 2026):**

| Breezze feature | Assigned upstream | Implemented availability |
| --- | --- | --- |
| Charts, artists, albums, song titles, search, catalog metadata, release data | **Deezer** | Implemented for public catalog metadata. Official Deezer clips are **30-second previews only**, not the full-song backend. |
| Native **full-song music audio**, queue, seek and background audio | **YouTube Music** (product target) | **BLOCKED, not implemented**: the existing [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) service supports metadata and matching, not authorized full-song audio streaming. Requires an explicitly permitted third-party audio integration and passing native tests. |
| Official music videos | **YouTube official player** | Visible official video playback path, distinct from Breezze's native audio player; no audio extraction. |

Deezer remains primary for discovery data and charts; YouTube Music metadata may be used to match the desired audio recording and locate its official video. Deezer `chart/0` is global, never a regional or guaranteed daily ranking. **Audius is forbidden** as an active source. Do not mislabel Deezer previews as the product's desired music-audio backend, or label YouTube Music audio as delivered before rights and playback QA pass.


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
