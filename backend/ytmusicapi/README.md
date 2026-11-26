# Breezze YouTube Music metadata adapter

This isolated service uses the MIT-licensed [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) Python library for public YouTube Music search and track metadata. It is **not** an audio streaming proxy.

## Endpoints

- `GET /health`
- `GET /search?q={query}&limit=20` — public music search metadata
- `GET /videos?q={query}&limit=20` — only YouTube Music `MUSIC_VIDEO_TYPE_OMV` results
- `GET /tracks/{videoId}` — track metadata
- `GET /tracks/{videoId}/music-video` — official music-video counterpart when available
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

The catalog routes deliberately discard YouTube's `streamingData`, adaptive
formats, bearer credentials and signed media URLs. The previously experimental
audio-candidate endpoint and its URL selection helper have been removed. A
feature flag must never turn this metadata service into a media URL dispenser.
Music metadata is not an audio entitlement: native streaming and offline
downloads require a separate authorized catalog and a rights-aware delivery path.

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
