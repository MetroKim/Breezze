# Breezze: fast Spotify + Deezer music discovery

Implementation (2026-11-26): the Flutter Songs tab debounces search by 300 ms and calls a single authenticated endpoint GET /api/v1/providers/music/search?q=<query>. The NestJS API queries Spotify and Deezer concurrently with a 3.8-second wait bound per provider, in-flight query coalescing, and adapter Redis caches (90-second search TTL). Results display in separate attributed Spotify and Deezer sections, each with title, artist, artwork, duration and stable provider-scoped ID. The Music Videos tab uses YouTube independently.

Spotify uses its official Web API search with a maximum 10 results per Development Mode request; SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET must be present in the backend secret environment, not in Flutter or git. Developer access and applicable branding/approval obligations must be satisfied for public launch. Deezer searches its public track catalog and may provide preview metadata, but discovery APIs are not full-track streaming rights.

Spotify metadata is not merged into Deezer metadata or used to create a replacement licensed audio source. Tapping a track opens Breezze track details for user selection. No external music applications are opened as a search requirement. The backend reports a partial outage when a source fails, and the client retains the other source's results. Underlying native full-track playback and offline downloads are separate rights-gated integrations and must not be claimed working from metadata access.

Tests: backend src/providers/provider-registry.service.spec.ts; Flutter test/music_catalog_search_api_test.dart. GitHub workflow .github/workflows/spotify-integration-verify.yml. Do not promote production until Railway runs the reviewed commit, Spotify keys are securely configured and same-SHA CI plus real authenticated search tests pass.

## Zero Spotify credentials: supported keyless behavior

- Spotify Web API cannot return official Spotify search results without authorized app credentials. Do **not** scrape unofficial Spotify sessions or disguise Deezer/MusicBrainz results as Spotify.
- Deezer public API is the default keyless music catalog and returns actual song titles, artists, covers and duration; it requires no Spotify credentials.
- If Deezer has no results or is unavailable, a **separately labeled MusicBrainz metadata-only shelf** can be enabled as backup with `MUSICBRAINZ_NONCOMMERCIAL_ACK=true` when its web-service license applies. MusicBrainz rate limiting is enforced across replicas in Redis at one request per 1.25 seconds; no traffic is sent if that budget cannot be reserved.
- Search results remain selectable inside Breezze; neither Deezer nor MusicBrainz grants access to licensed commercial full-track audio. Spotify is automatically omitted from the response when it is not configured.
- Free MusicBrainz Web Service access is limited to non-commercial use. A future commercial deployment requires suitable authorization or self-hosted CC0 core metadata with proper data-license handling.
- No provider credentials are committed to the repository or bundled into Flutter.
