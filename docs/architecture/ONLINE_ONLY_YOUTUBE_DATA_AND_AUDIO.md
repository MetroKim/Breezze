# Breezze — online-only music/video integration and credential operations

**Last inspected:** 2026-11-26. This is the implementation contract, not a claim that commercial YouTube Music audio is licensed or playing.

## No local audio or video files required for discovery and YouTube video playback

- **YouTube Music metadata:** existing private `ytmusicapi` sidecar; music search, artists, albums, charts and playlists. It never supplies a public authorized full-audio entitlement.
- **Deezer:** public catalog metadata, search, charts and official **preview** streams where the Deezer API exposes them. A Deezer preview is not a full-track license.
- **Official YouTube Data API:** public **music-video** search and video metadata. The server calls `youtube/v3/search` and `youtube/v3/videos` with `YOUTUBE_DATA_API_KEY`. Restrict searches to embeddable, syndicated music videos. Metadata responses provide a watch URL and explicit `playbackAvailable: false` for the native audio path.
- **Official YouTube visible player:** the existing `OfficialMusicVideoScreen` plays supported video via the documented YouTube embedded player, respecting ads, visibility, restrictions and creator settings. If a video cannot be embedded, offer the external official watch page.
- **Native audio:** a separate, rights-cleared full recording can be delivered from approved upstream streaming APIs or the signed Cloudflare R2 pipeline. This requires track-level playback rights; it is **not** supplied by the Data API. A bare YouTube Music track ID never authorizes offline downloads or native audio.
- **Offline:** only a verified separately licensed full recording with a valid download grant, client-side encryption and revocation checks.

## Server-side Google API key setup

1. In <https://console.cloud.google.com/apis/credentials>, **rotate the previously pasted key** and, preferably, create a **dedicated new key** for Breezze YouTube Data API. Do not reuse it for unrelated Google services.
2. Enable `YouTube Data API v3` in the intended Breezze Google Cloud project. Under API restrictions, allow **only YouTube Data API v3** for the dedicated key. Add an application restriction appropriate for the actual egress platform; if server egress IPs are not stable, do not guess fake IP ranges. Use restricted quota, alerting, backend request gating and consider stable egress infrastructure.
3. Place the replacement key in the Railway NestJS API service variable `YOUTUBE_DATA_API_KEY`. **Never** put it in Flutter `--dart-define`, `pubspec.yaml`, a repository file, GitHub Actions output, source maps or `CLOUDFLARE_API_TOKEN`.
4. The current Railway deployment is older than GitHub `main`. A **staged** variable alone does not activate the new provider. Only a reviewed, backed-up backend deployment with working auth, migrations, /health/ready and rollback may do so.
5. Validate the protected endpoints through the Cloudflare API edge with a real signed-in user:
    - `GET /api/v1/providers/youtube/videos/search?q=beethoven&limit=5`
    - `GET /api/v1/providers/youtube/videos/{videoId}`
   The response must **never** contain the API key or an audio source URL. The Music Videos tab can use those endpoints when the existing discovery provider is down.
6. Google revised YouTube Data API search quotas in 2026. `search.list` now has a separate default daily budget of 100 calls, while other API operations have a separate quota; see <https://developers.google.com/youtube/data/determine_quota_cost>. Breezze caches successful queries in Redis and reserves at most 80 official search calls per Pacific-day per API deployment. Redis being unavailable makes new official searches fail closed rather than exhausting the project's key. Validate actual Google quotas in your project console.

## Native audio realism

The private R2 media delivery Worker and NestJS rights checks passed dedicated local integration tests, but that is **infrastructure**, not a commercial catalog. The production R2 bucket contains no recordings; the existing embedded YouTube player is what can play real videos today (subject to availability and the user's controls). The YouTube Data API cannot grant a license to rip, isolate, cache or download the audio of those videos.

To ship **full native songs without owning audio files**, negotiate an approved full-track stream partner capable of returning a per-user, per-territory playback URL, or license recordings from rights holders and ingest them via Breezze's protected internal media pipeline. Free/open-licensed audio (CC0, public domain, some Creative Commons licenses) can supply a smaller separate source if each file's license, source, attribution and availability are verified; it cannot be mislabeled as YouTube Music or assumed to include popular commercial music.

The optional developer-only device YouTube audio probe is disabled in release builds. The stable source-aware handoff instead opens the official visible YouTube video player promptly when no licensed native recording is resolved.

## Acceptance gates

- Backend: `npx prisma generate && npm run typecheck && npx jest --runInBand src/providers/official-youtube-data.service.spec.ts src/providers/ytmusic.adapter.spec.ts`.
- Media pipeline: GitHub `media-delivery-verify.yml` on each relevant commit; check both NestJS and real Wrangler/R2 plus PostgreSQL gates.
- App: `breezze-android-playlist-acceptance.yml` and `breezze-ios-playlist-acceptance.yml` must pass on the **same reviewed SHA** after boot and native player fixes. Native full-track acceptance cannot be substituted by a 30-second Deezer preview.
- Production: confirm Railway API commit parity, media Worker commit parity, test signed byte ranges against a licensed audio asset, storage encryption and real-device playback where available. Preserve release freeze until those gates pass.
