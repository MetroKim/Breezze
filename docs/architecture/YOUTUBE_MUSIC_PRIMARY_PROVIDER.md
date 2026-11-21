# YouTube Music as Breezze's primary discovery source

## What is implemented

- The NestJS `youtube_music` provider uses the existing FastAPI `ytmusicapi` sidecar for catalogue search and track metadata.
- Flutter unified search prioritizes YouTube Music results, then appends Breezze's own catalogue results without duplicating IDs.
- Search and track-detail Play actions request a provider playback-launch descriptor from `GET /api/v1/providers/youtube_music/playback/:trackId`.
- The descriptor contains the official YouTube watch URL and privacy-enhanced embed URL. The Flutter app validates the returned watch URL and opens it through the operating system using `url_launcher`.
- The same handoff works through the platform's registered browser/YouTube app on Android, iOS, web, Windows, macOS and Linux, subject to each platform having a URL handler.

## What this deliberately does not do

YouTube Music metadata is not a licence or a direct-stream entitlement. Breezze does not extract, proxy, cache, sign, or distribute YouTube audio/video stream URLs. The official YouTube player owns playback.

Consequences of this integration:

- YouTube-sourced playback leaves Breezze and opens the official YouTube player (or the user's configured browser/app).
- Playback controls, advertisements, account prompts, availability restrictions and playback behaviour are controlled by YouTube.
- Breezze's `just_audio` engine, mini-player, background playback, native queue controls, crossfade and gapless playback do not control an externally launched YouTube session.
- The launch endpoint sets no autoplay flag. The user initiates playback in the official player.
- A failed launch is reported to the user; Breezze must not fall back to extracted media URLs.

This is the reliable cross-platform baseline without a paid music-platform API key. An in-app embedded player can be added only on platforms where the official YouTube embed is supported and must retain YouTube's player UI and restrictions. It cannot be represented as native background audio.

## Provider service

The sidecar is configured with `YTMUSIC_API_URL` (defaults to `http://127.0.0.1:8000`). It does not require an official YouTube Data API key for the current ytmusicapi metadata search path. The optional YouTube Data API fallback remains optional and is not needed for this handoff.

Because `ytmusicapi` is an unofficial interface, it can change or be rate-limited. Keep the existing Redis cache, request coalescing, timeout, circuit breaker and bounded sidecar concurrency. Treat provider errors as temporary discovery failures, not as permission to use another provider's stream.

## API contract

`GET /api/v1/providers/youtube_music/playback/:trackId`

Success result:

```json
{
  "kind": "ok",
  "value": {
    "mode": "external_official_player",
    "providerId": "youtube_music",
    "providerTrackId": "VIDEO_ID",
    "watchUrl": "https://www.youtube.com/watch?v=VIDEO_ID",
    "embedUrl": "https://www.youtube-nocookie.com/embed/VIDEO_ID?playsinline=1&rel=0",
    "requiresUserGesture": true,
    "supportsBackgroundAudio": false,
    "supportsNativeQueueControls": false
  },
  "attribution": "Playback is handled by the official YouTube player"
}
```

Only validated YouTube video IDs are accepted. The response is a launch descriptor, never a playable stream URL.

## Playback entry-point coverage

All app surfaces that can start a YouTube Music-backed track now use the same
validated official-player handoff:

- Unified Search and Track details.
- Browse genre feeds and Browse collection feeds.
- Verified canonical album detail track rows and Play action, when their track
  IDs are YouTube Music-backed.
- User playlist Play and individual song selection.
- Library saved-song Play All and individual song selection.

Non-YouTube tracks continue through Breezze's native, rights-checked playback
resolver. The handoff helper obtains the descriptor from the backend, checks
that it is an official YouTube watch URL for the requested provider ID, and
then launches it externally.

### Queue limitation (intentional)

An external YouTube player session is not part of Breezze's native audio
session. Therefore, a YouTube Music item cannot be promised as a playable item
inside Breezze's native queue. Selecting a YouTube-backed song opens YouTube
directly; it does not provide background playback, native next/previous,
crossfade, gapless playback, or queue synchronization. Mixed playlists do not
gain those capabilities merely because the metadata is stored in Breezze.

## Web database support

The local Drift database now selects its executor using a conditional import:
native targets use NativeDatabase, while Flutter Web uses Drift's
WasmDatabase backed by browser storage. Before a Web build, run
'bash tool/prepare_web_database.sh' from 'apps/mobile' to fetch the pinned Drift
WebAssembly module and worker into 'web/'. CI runs this preparation before
'flutter build web --release'.
