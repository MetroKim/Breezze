# Breezze music catalogue providers

Breezze uses provider adapters for catalogue discovery. Discovery metadata is
not a playback grant.

## Deezer

- Adapter ID: `deezer`
- API: `https://api.deezer.com`
- Configuration: `DEEZER_ENABLED`, `DEEZER_API_URL`
- Public track search and track metadata are normalized into Breezze's
  federated provider result format.
- The public catalogue API does not authorize unrestricted full-track
  streaming. The adapter therefore declares `playback: false` and
  `availability: false`. Do not enable native streaming based on a preview
  URL or metadata response. A separate approved Deezer player/SDK integration
  and its user authorization requirements must be implemented first.

## SoundCloud

- Adapter ID: `soundcloud`
- API: `https://api-v2.soundcloud.com`
- Configuration: `SOUNDCLOUD_ENABLED`, `SOUNDCLOUD_API_URL`,
  `SOUNDCLOUD_CLIENT_ID`
- The adapter is disabled until a developer client ID is configured.
- Search and track metadata use SoundCloud's API v2 endpoints. The adapter
  does not extract media URLs or treat a track's streamable flag as a grant
  for Breezze playback.
- It declares `playback: false` and `availability: false` until an approved
  SoundCloud embed/OAuth playback flow is implemented and tested.

## Provider integration rules

1. Keep provider IDs stable: `deezer` and `soundcloud`.
2. Cache catalogue metadata only; never cache signed playback URLs as track
   metadata.
3. A provider may enter the native playback resolver only when it implements
   a supported authorization/availability check and a real playback resolver.
4. Embedded playback must use the provider's official player and honor its
   controls, attribution, restrictions, and terms.
5. A provider outage must not hide results from other enabled providers.
