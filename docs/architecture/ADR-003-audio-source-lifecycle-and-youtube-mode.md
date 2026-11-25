# ADR-003 — Provider audio source lifecycle and YouTube playback separation

Status: Adopted (2026-11-25). Implemented on main as transport hardening; full YouTube Music audio licensing remains **open**.

## External architecture researched

The Liner desktop repository at https://github.com/tryliner/desktop was inspected to understand its high-level separation of source resolution from playback. Its published source advertises several playback source types (Liner API / R2, YouTube-family direct and TV paths, SoundCloud and local files), stream metadata and expiry, client-profile fallback and native audio handling. See:
- `src/features/player/engine/playbackStream.ts`
- `src/features/player/engine/streamResolver.ts`
- `src/shared/youtube/innertube/innertubeAudio.ts`
- `electron/youtube/`
- `LICENSE`

**Licensing boundary:** Liner's published source-available, non-commercial license expressly prohibits extracting its core algorithms into independent apps. No Liner code, signing logic, proof-of-origin token logic, playback-profile impersonation, decryption, or proprietary assets are incorporated here. Discovering how a client technically obtains streams does not establish an upstream right for Breezze to do the same.

## Breezze architecture decision

1. Deezer is the main chart/search/catalog metadata source and public preview source. Its standard API does not license complete songs.
2. `ytmusicapi` is a YouTube Music discovery and metadata integration. Its results do not become native audio stream URLs.
3. Full YouTube videos use Breezze's **visible** official YouTube player. Embedded playback must honor provider ads, branding, uploader restrictions, foreground/lifecycle behavior and controls.
4. Licensed full-song audio uses one global Flutter player, but **only** after an independently verified upstream stream grant and an active Breezze rights decision for the recording, user and territory.
5. Playlist matching, track identity, and source routing remain distinct from playback authorization. A metadata match must never create a playback grant or download entitlement.
6. Never persist bearer media URLs or authorization secrets in queue snapshots, analytics, or logs.

## Implemented reliability engineering

- `backend/api/src/playback/provider-stream-guard.ts`: validates provider-issued HTTPS audio/HLS/DASH URLs; rejects URL credentials, fragments, local/IP address destinations, malformed expiry, expiring streams (15-second safety margin), non-audio MIME types, and grants extending beyond explicit rights expiry. The guard is called by `PlaybackResolveService.resolveProvider` **after** territory/rights/availability checks.
- `apps/mobile/lib/core/audio/remote_audio_grant.dart`: applies a corresponding defensive source-origin and lease check before native player preparation. Invalid sessions are stopped rather than played.
- `packages/audio_contracts/lib/src/audio_engine_adapter.dart`: treats remotely signed media as expired **15 seconds before** its deadline. The app's existing resume flow re-resolves expired sources while retaining the current position. Local media is exempt.
- Contract tests cover invalid URL classes, MIME restrictions, territory-independent grant integrity, expiry edges, and local media behavior.

The margin is a *pre-start/resume* safeguard. It does not promise seamless token rotation for long-playing songs; every provider must document its URL's streaming behavior and any requirement to resolve a fresh URL during playback.

## Not implemented / release gates

No production native YouTube Music full-track resolver or offline download source is claimed. YouTube API rules disallow using its API service to split YouTube audiovisual content into independent audio and prohibit undisplayed/background player access:
https://developers.google.com/youtube/terms/developer-policies

To enable an authorized new native full-track provider:
1. Obtain contractual/SDK authorization for this app's audio-only, background, geographical and account use, with separate offline/caching rights where required.
2. Implement a provider adapter under `backend/api/src/providers/` that verifies availability and returns a bounded upstream-approved media URL. Never enable `youtube_music.capabilities.playback` solely because a technical extraction succeeds.
3. Keep `/playback/provider/resolve`, canonical ID checks, content-takedown checks, origin validation, signed session expiration, and grant rejection as independent gates.
4. Verify a known licensed song end-to-end on Android and iOS emulators: complete duration, seek, pause/resume after expiry, network loss, playback continuity, OS audio focus, switch-account isolation, authorization revocation and account-specific territory.
5. Run the Jest and Flutter suites plus production edge and physical-device checks before any release.

This ADR is a factual engineering decision, not a report that full YouTube Music audio is unlocked.
