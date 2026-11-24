# Breezze music providers — YouTube Music and Deezer

**Authoritative three-source-role contract (24 November 2026):**

| Breezze feature | Assigned upstream | Implemented availability |
| --- | --- | --- |
| Main charts, artist profiles, albums, song titles, search, catalog metadata and releases | **Deezer (primary data source)** | Implemented for public metadata. Official Deezer clips are **30-second previews only**, not the intended full-song backend. |
| Supplementary charts, ranked/unranked artists, artist search and artist releases | **YouTube Music via [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi)** | Artist search/profile and chart metadata routes are wired in source code. Public unauthenticated charts supply artist lists and music-video chart playlists where available; a Top Songs chart is **not guaranteed**. Production rollout and tests remain to verify. |
| Native **full-song music audio**, queue, seek and background audio | **YouTube Music** (product target) | **BLOCKED, not implemented**: the existing [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) service supports metadata and matching, not authorized full-song audio streaming. Requires an explicitly permitted third-party audio integration and passing native tests. |
| Official music videos | **YouTube official player** | Visible official video playback path, distinct from Breezze's native audio player; no audio extraction. |

Deezer remains the **primary** data provider for charts, artists, releases and metadata. YouTube Music is **also** a data source for its own charts, artist discovery and releases, and it is the intended full-song audio source only after an authorized audio integration exists. Both upstream catalogues must keep their attribution and chart semantics separate; never relabel one provider's chart as the other's. Deezer `chart/0` is global, never a regional or guaranteed daily ranking. **Audius is forbidden** as an active source. Do not mislabel Deezer previews as the product's desired music-audio backend, or label YouTube Music audio as delivered before rights and playback QA pass.


The only external music catalogue providers are **YouTube Music** and **Deezer**. 
The internal `breezze_internal` adapter reads the app's own canonical track
records; it is not an external music streaming provider.

## YouTube Music (primary native audio target; not yet authorized)
- Adapter ID: `youtube_music`.
- `ytmusicapi` supplies song search, artist search/profile and chart metadata, in addition to track lookup and official music-video matching.
- The sidecar now defines `/artists/search`, `/artists/{artistId}` and `/charts?country=ZZ`; NestJS exposes `/api/v1/providers/youtube_music/artists/search`, `/api/v1/providers/youtube_music/artists/{artistId}` and `/api/v1/providers/youtube_music/charts?country=ZZ`.
- Public chart results may contain artists and music-video chart playlists without a reliable Top Songs ranking. Never fabricate missing ranks or claim all charts are regional/daily. The app should use Deezer chart rows for its mainstream song-chart surface where appropriate and label supplemental YouTube Music chart content separately.
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

## Full-song YouTube Music audio — authorization handoff

**Do not self-grant.** Breezze can issue *its own* signed playback URLs only for media assets that it actually controls with valid rights; this is not authority to license tracks in YouTube Music's catalogue. The [YouTube API Developer Policies](https://developers.google.com/youtube/terms/developer-policies) prohibit using API services to split YouTube audiovisual components into independent audio or operate an undisplayed/background player. The [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) project is an unofficial metadata client, not a YouTube Music audio streaming SDK or distribution agreement.

To activate the intended native-player role, obtain and validate **a signed agreement or provider-issued SDK/API entitlement** explicitly covering each requested use: third-party in-app audio-only delivery, background playback and lock screen, territories (including Tanzania where relevant), user authentication/subscription terms, stream URL/session lifetime, seek/skip/queue, caching and offline rights if any, catalog identifiers/ISRC mapping, reporting, takedowns and revocation.

After an authorized integration is available, engineering must:
1. Implement a separate server-side playback adapter with an explicit capability flag, the approved endpoint/SDK, and expiry/territory/attribution checks. Keep `YtMusicAdapter.playback=false` until the licensed integration is proven; do not use `get_song().streamingData`, player ciphers, browser cookies or hidden video playback as substitutes.
2. Bind each track to a canonical ID and verified provider asset. Require an active `stream.full` permission and current territory grant, *as well as* the upstream provider's playback entitlement. A metadata-only permission or Deezer 30-second preview is not enough.
3. Return media only via the existing `/playback/provider/resolve` service and Breezze's one global player. The generic `/playback/resolve` must never mint Breezze-hosted audio URLs for records with `source=youtube_music` or `source=deezer`; such tracks must be handled by the provider resolver.
4. Validate expired grants, revocation, takedowns, territory denial, non-licensed account, wrong canonical asset, signed-URL expiration, seek/resume, background/lock-screen controls, and cross-account isolation. Run Android and iOS native acceptance and production smoke against a genuinely licensed recording.

**Current status:** Metadata, artist and chart discovery may operate; full-song native YouTube Music audio is **externally blocked**. No source code commit, account sign-in or self-added database rights row can replace the upstream licence.

## Release checks
1. Federated discovery returns only `breezze_internal`,
   `youtube_music`, and `deezer`, while isolating provider failures.
2. Retired provider lookups return `PROVIDER_NOT_FOUND`.
3. Metadata-only results and previews cannot bypass full-stream licensing.
4. Native emulator, production auth and queue tests are independent gates.
