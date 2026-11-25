# Breezze: in-app music only — provider and playback contract
**Decision:** 26 November 2026. Product owner explicitly rejects redirects into Spotify or Deezer applications.

## Non-negotiable user experience

Breezze must present **one owned playback screen** with audio play/pause, queue, seek, lock-screen controls and (where licensed) offline support. YouTube is visible music-video playback only. No "open the Spotify app", "open the Deezer app", background external-app bridge, unauthorized stream extraction, or confusing 30-second previews with complete songs.

Spotify and Deezer remain **music catalog identities** (track IDs, artist, title, album, attribution), not audio grants. The Android and iOS app must not enqueue `bz:spotify:<id>` or `bz:deezer:<id>` for native full-song playback until the backend has proven a separate licensed, compliant in-app source for that exact recording. A Deezer `bz:deezer_preview:<id>` is an explicitly selected **up-to-30-second sample**, not the full track and never eligible for offline download.

The only way to enable full in-app playback from either provider is an **approved direct integration that expressly grants in-app streaming**, or rights-holder licenses for recordings that Breezze may independently deliver. Ordinary Spotify Web API client credentials, Deezer REST catalog metadata, access to a paid subscriber account, or a Google API key do **not** grant Breezze permission to extract audio or redistribute it through its own Cloudflare Worker.

## Technical pathway after an actual provider agreement

1. **Provider authorization and territory:** negotiate in-app playback rights, user entitlement, territory restrictions, royalties/usage reporting, expiry, permitted SDK APIs, codec delivery, and whether Deezer/Spotify content is allowed to appear in one combined application. Spotify's general developer policy prohibits integrating its content with another service without applicable permission, and restricts commercial streaming.
2. **Adapter contract:** add an approved `ProviderPlaybackSource` or secure SDK-backed play engine only after obtaining the contract and real partner implementation documentation. Never set `capabilities.playback=true` merely because search or an API token works.
3. **Native resolver:** match canonical track, verify `RightsUsagePermission` and current entitlement and takedowns, and return a short-lived playback grant only from the authorized API/asset. Keep provider-native DRM and SDK restrictions intact. Do not proxy, cache, modify, or mix provider streams unless the agreement expressly permits it.
4. **Single player:** bridge authorized playback status into the existing Breezze queue, mini-player, Now Playing and platform media session. Show a clear blocked state when a recording cannot be played. Test seek, background, focus, skip, expiry, interruption, revocation, region, and app restart.
5. **Offline:** implement only where an explicit download grant and SDK contract permit it. Both Spotify and Deezer full songs are currently download-disabled within Breezze. Never treat 30-second Deezer previews as offline songs.
6. **Release:** run backend CI, Flutter unit tests, Android/iOS emulator acceptance, then staging with real contract-provided test assets before production. The previous production deployment/release freeze remains unchanged.

## Current engineering evidence

- Spotify and Deezer metadata adapters are registered in NestJS. YouTube music content is excluded from the audio registry and remains video-only.
- The Flutter Search, Browse and song/album detail screens no longer call external Spotify or Deezer apps for song playback.
- Legacy `SpotifyPlaybackHandoff`, `DeezerPlaybackHandoff`, and `OfficialMusicPlayback` app launch modules and associated tests were deleted.
- The player policy prevents both Spotify and Deezer full-song catalog IDs from entering the native queue. New tests reject false full-song play actions and unauthorized offline downloads.
- No supplier authorization, licensed full-track recording catalog, or Spotify Premium Web Playback SDK authorization has been provided for public Breezze playback. Consequently **full commercial songs are still a release blocker**. Do not mark them PASS in Notion, GitHub or production checkpoints.

## Official references

- Spotify Developer Policy: https://developer.spotify.com/policy
- Spotify Web Playback SDK (requires Premium and is browser-specific): https://developer.spotify.com/documentation/web-playback-sdk/tutorials/getting-started
- Deezer 2022 Universal Registration Document §1.7.2.3 (partner SDKs and contracted in-app streaming): https://www.deezer-investors.com/wp-content/uploads/2023/04/DZR2022_DEEZER_URD_EN_MEL_230428.pdf
