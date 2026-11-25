# Breezze YouTube Music metadata adapter

This isolated service uses the MIT-licensed [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) Python library for public YouTube Music search and track metadata. It is **not** an audio streaming proxy.

## Endpoints

- `GET /health`
- `GET /search?q={query}&limit=20` — public music search metadata
- `GET /videos?q={query}&limit=20` — only YouTube Music `MUSIC_VIDEO_TYPE_OMV` results
- `GET /tracks/{videoId}` — track metadata
- `GET /tracks/{videoId}/music-video` — official music-video counterpart when available
- `GET /tracks/{videoId}/audio-candidate` — **non-production experimental** direct audio URL from `YTMusic.get_song()`; disabled by default and not a playback entitlement
- `GET /artists/search?q={query}&limit=20` — YouTube Music artist discovery
- `GET /artists/{artistId}` — public artist profile, songs and albums metadata
- `GET /charts?country=ZZ` — YouTube Music artist charts and music-video chart playlists; `ZZ` means global
- `GET /watch-queue/{videoId}?limit=20` — unofficial next-track suggestions from `get_watch_playlist`; IDs/metadata only, **not playable audio**
- `GET /suggestions?q={query}&limit=10` — YouTube Music typeahead suggestions
- `GET /albums/{MPRE...}` — album details, credited artists and up to 100 tracks
- `GET /playlists/{playlistId}?limit=50` — public playlist details and up to 100 tracks
- `GET /moods` — categories and safe category tokens from `get_mood_categories`
- `GET /moods/playlists?params={token}&limit=20` — matching public mood playlists
- `GET /explore` — YouTube Music new releases, trending, new official videos, and Top Songs only when actually present

The standard catalog routes deliberately drop YouTube's `streamingData`, adaptive formats and signed URLs. A separate **non-production opt-in experiment** exposes only an already-direct HTTPS `googlevideo.com` audio candidate from `YTMusic.get_song()` without signature deciphering, DRM bypass or a download endpoint. The primary NestJS provider still advertises metadata-only capabilities; rights-aware playback resolution, downloads and production availability remain disabled. Experimental audio is **not** an approved distribution or offline entitlement.

## Experimental native-audio feasibility

This probe is **off by default** and blocked when `RAILWAY_ENVIRONMENT_NAME=production` (sidecar), or when `NODE_ENV=production` / Railway environment is production (API). Set `BREEZZE_YTMUSIC_AUDIO_EXPERIMENT=true` on **both** the private Python sidecar and the NestJS API in a dedicated, nonproduction test environment. The private sidecar validates Googlevideo HTTPS hostnames, direct audio MIME types and URL expiration. The NestJS route `GET /api/v1/providers/youtube_music/audio-candidate/{videoId}` requires Supabase JWT auth and independently validates the result. Flutter's existing `LiveResolver` hands a valid candidate to `just_audio`, otherwise it falls through to normal resolver and preview handling. **Flutter build switch:** opt in with `--dart-define=BREEZZE_YTMUSIC_AUDIO_EXPERIMENT=true`. This makes song taps in Home, Browse, Search and catalog screens try the candidate first, then fall back to the visible official YouTube player if absent or unplayable; music-video-only actions remain video. The switch defaults to disabled in ordinary builds. No new native player or extra playlist controller is created.

**Acceptance evidence required before claiming playback works:** (1) stubbed Python, API and Flutter tests pass; (2) the test environment returns a real direct format for the selected public song; (3) playback, range seeks and expiry refresh actually work on an emulator; (4) measure whether media URLs are tied to the sidecar egress IP and fail from the device; (5) confirm permission for any eventual distribution. A signed URL working inside the container does not prove a device can stream it. Do not expose credentials or persistent signed media URLs; the experiment does not support offline downloads.

## Run locally

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

The backend Compose stack starts this service at `http://ytmusicapi:8000`. The API uses `YTMUSIC_API_URL` to connect to it.

## Operational and legal constraints

`ytmusicapi` is an unofficial client that emulates YouTube Music web requests; it is not an official Google API or a guarantee of service availability. Review YouTube's applicable terms, regional requirements, and usage rights before public production use. The sidecar admits at most eight concurrent upstream requests per container replica and returns HTTP 503 with `Retry-After: 2` when full. The NestJS adapter coalesces identical in-flight searches and metadata lookups per API process, and opens a 30-second circuit after five consecutive retryable upstream failures (with a single half-open recovery probe). Redis caches successful results across API replicas. Set replica counts and provider request budgets conservatively, and add provider-specific monitoring before increasing traffic. Never put browser cookies or account credentials in this service unless separately approved and secured.

The supplemental artist and chart routes only expose sanitized metadata. Unauthenticated `get_charts` results can contain artists without numeric ranks and video chart playlists without song rankings; `songRankingAvailable=false` states that limitation instead of inventing a Top Songs chart. The API caches chart results briefly and shares the same upstream concurrency/circuit protections. Deezer remains the primary source for normal song charts, artist pages and release metadata, while YouTube Music adds its own chart and artist context. Neither metadata service grants full-track audio rights.

The video endpoint filters to YouTube Music's `OMV` classification (Original Music Video), which the upstream project describes as video content uploaded by the original artist. It excludes UGC and audio tracks with static artwork from the Music Videos surface. This classification is useful provenance, not a legal licence verification.

This adapter supplies discovery metadata only. It does not grant rights to stream, download, re-host, or redistribute any recording.
