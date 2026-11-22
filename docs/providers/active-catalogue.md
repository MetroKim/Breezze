# Breezze active music catalogue providers

Breezze's federated search currently includes its internal catalogue, YouTube Music metadata and Deezer metadata. Jamendo appears only after a real client ID, API terms acceptance and explicit written approval for Breezze's use case are configured.

## Internal Breezze catalogue

- Adapter ID: `breezze_internal`
- Returns existing canonical track IDs from Breezze's database.
- Playback is resolved independently through the authorized backend media/session flow and territory rights checks.

## YouTube Music

- Adapter ID: `youtube_music`
- ytmusicapi sidecar supplies metadata for discovery only.
- This adapter must not expose native audio stream URLs or downloads from undocumented endpoints.
- A dedicated official video-player pathway may use supported embedded playback subject to YouTube's rules. Video metadata is never a native audio playback grant.

## Deezer

- Adapter ID: `deezer`
- Public API: `https://api.deezer.com`
- Environment: `DEEZER_ENABLED` and `DEEZER_API_URL`
- Search/track metadata is normalized into Breezze's federated provider result format.
- Declares `playback: false`, `availability: false`, `download: false`. Metadata and preview URLs are not full-track streaming permissions.
- Any Deezer playback requires a separately approved integration and its required authorization.

## Optional Jamendo

- Adapter ID: `jamendo`
- Disabled without `JAMENDO_CLIENT_ID`, `JAMENDO_API_TERMS_ACCEPTED=true`, and `JAMENDO_BREEZZE_APPROVED=true`.
- Streaming requires an individual rights/license check and a supported Jamendo resolver; offline downloads remain disabled.

## Operational rules

1. Provider search failures are isolated and cannot discard results returned by another provider.
2. An empty result from a working provider is displayed as no results, not as an infrastructure failure.
3. Only explicit playback/availability-capable sources enter the backend playback resolver; metadata-only results never enter a native playback queue.
4. User-visible catalogue IDs remain namespaced to avoid collisions.
5. No SoundCloud account or API credentials are required or used.
