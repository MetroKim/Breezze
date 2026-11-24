# Breezze music providers — YouTube Music and Deezer

**Current two-provider source-role contract (25 November 2026):**

| Breezze feature | Assigned upstream | Implemented availability |
| --- | --- | --- |
| Main charts, artist profiles, albums, song titles, search, catalog metadata and releases | **Deezer (primary data source)** | Implemented for public metadata. Official Deezer clips are **30-second previews only**, not the intended full-song backend. |
| Supplementary charts, ranked/unranked artists, artist search and artist releases | **YouTube Music via [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi)** | Artist search/profile and chart metadata routes are wired in source code. Public unauthenticated charts supply artist lists and music-video chart playlists where available; a Top Songs chart is **not guaranteed**. Production rollout and tests remain to verify. |
| Native external **audio previews** with queue/seek | **Deezer public previews** | Deezer track previews (up to 30 seconds) are fetched through the existing Deezer adapter and played by Breezze's one native audio engine. Previews are not full songs or offline entitlements. |
| Official music videos | **YouTube official player** | Visible official video playback path, distinct from Breezze's native audio player; no audio extraction. |
| YouTube Music playlists, albums, moods, artist profiles and music-video discovery | **ytmusicapi** | Implemented best-effort read-only discovery routes, with `albums`, `artists`, `playlists`, `videos`, `charts` and `moods` capabilities explicitly advertised. |

Deezer is the **primary catalog and external native-audio preview** provider for charts, artists, releases and metadata. YouTube Music remains an optional discovery and visible-video provider, **not a native-audio source** in Flutter. Authorized full-song playback remains separate from these public APIs. Both upstream catalogues must keep their attribution and chart semantics separate; never relabel one provider's chart as the other's. Deezer `chart/0` is global, never a regional or guaranteed daily ranking. **Audius is forbidden** as an active source. Do not mislabel Deezer previews as the product's desired music-audio backend, or label YouTube Music audio as delivered before rights and playback QA pass.


The only external music catalogue providers are **YouTube Music** and **Deezer**. 
The internal `breezze_internal` adapter reads the app's own canonical track
records; it is not an external music streaming provider.

## YouTube Music (discovery and official video only)
- Adapter ID: `youtube_music`.
- `ytmusicapi` supplies song search, artist search/profile and chart metadata, in addition to track lookup and official music-video matching.
- The sidecar now defines `/artists/search`, `/artists/{artistId}` and `/charts?country=ZZ`; NestJS exposes `/api/v1/providers/youtube_music/artists/search`, `/api/v1/providers/youtube_music/artists/{artistId}` and `/api/v1/providers/youtube_music/charts?country=ZZ`.
- Public chart results may contain artists and music-video chart playlists without a reliable Top Songs ranking. Never fabricate missing ranks or claim all charts are regional/daily. The app should use Deezer chart rows for its mainstream song-chart surface where appropriate and label supplemental YouTube Music chart content separately.
- Metadata does **not** give Breezze permission to extract or redistribute
  full-track YouTube audio. An official, visible video embed is a separate
  permitted experience where supported, subject to YouTube's conditions.
- Native full-track playback from YouTube Music requires explicit Google-authorized third-party audio-only playback access, territories, stream lifecycle and background rights. No such public SDK or direct licensed API is currently configured. The provider's **production playback and download capabilities remain `false`**. An older JWT-protected, non-production experimental audio-candidate backend may remain available behind service flags for isolated feasibility work, but the Flutter app **does not call it**. YouTube Music selection opens the visible YouTube player instead.

## Deezer — selected external audio provider
- Adapter ID: `deezer` (priority 110, ahead of YouTube Music's 100).
- Public API is Breezze's primary catalog/search source and supplies normalized metadata and eligible Deezer preview clips.
- Native playback uses only refreshed Deezer `previewUrl` clips of up to 30 seconds; preview tracks carry `bz:deezer_preview:{id}` IDs, must be labeled Preview, and cannot be downloaded by Breezze. Other Deezer catalog IDs must not masquerade as complete tracks.
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

## Full-song audio — authorization handoff (including Deezer)

**Do not self-grant.** Breezze can issue *its own* signed playback URLs only for assets it controls with valid rights. Deezer public API previews and YouTube Music metadata do not grant full-song distribution or downloads. The [YouTube API Developer Policies](https://developers.google.com/youtube/terms/developer-policies) prohibit using API services to split YouTube audiovisual components into independent audio or operate an undisplayed/background player. The [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) project is an unofficial metadata client, not a YouTube Music audio streaming SDK or distribution agreement.

To activate full-song delivery from Deezer or another music provider, obtain and validate **a signed agreement or provider-issued SDK/API entitlement** explicitly covering each requested use: third-party in-app audio-only delivery, background playback and lock screen, territories (including Tanzania where relevant), user authentication/subscription terms, stream URL/session lifetime, seek/skip/queue, caching and offline rights if any, catalog identifiers/ISRC mapping, reporting, takedowns and revocation.

After an authorized integration is available, engineering must:
1. Upgrade the existing isolated experimental proof of concept into an authorized production resolver only after obtaining the required upstream entitlement and establishing expiry, territory and attribution checks. Keep `YtMusicAdapter.playback=false` for production until then. The proof of concept reads only already-direct, unexpired `get_song()` audio candidates without deciphering signatures, and must not be presented as licensed playback.
2. Bind each track to a canonical ID and verified provider asset. Require an active `stream.full` permission and current territory grant, *as well as* the upstream provider's playback entitlement. A metadata-only permission or Deezer 30-second preview is not enough.
3. Return media only via the existing `/playback/provider/resolve` service and Breezze's one global player. The generic `/playback/resolve` must never mint Breezze-hosted audio URLs for records with `source=youtube_music` or `source=deezer`; such tracks must be handled by the provider resolver.
4. Validate expired grants, revocation, takedowns, territory denial, non-licensed account, wrong canonical asset, signed-URL expiration, seek/resume, background/lock-screen controls, and cross-account isolation. Run Android and iOS native acceptance and production smoke against a genuinely licensed recording.

**Current status:** Deezer is the native external preview provider; YouTube Music supplies optional discovery and official foreground video only. Full-song delivery and offline rights for Deezer are **not authorized** by public API access. A historical non-production YouTube Music probe remains isolated from Flutter. No source code commit, account sign-in or self-added database rights row can replace the upstream licence.

## Release checks
1. Federated discovery returns only `breezze_internal`,
   `youtube_music`, and `deezer`, while isolating provider failures.
2. Retired provider lookups return `PROVIDER_NOT_FOUND`.
3. Metadata-only results and previews cannot bypass full-stream licensing.
4. Native emulator, production auth and queue tests are independent gates.
