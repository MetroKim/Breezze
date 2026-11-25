# Breezze provider decision — Spotify MUSIC + YouTube VIDEO

**Decision:** 2026-11-26. This supersedes the old YouTube-native-audio and Deezer-preview approach. This is an implementation record, not a claim of production Spotify approval.

## Source ownership and user experience

| User action | Correct provider | Implementation |
|---|---|---|
| Music search, album/track metadata | Spotify Web API | `SpotifyAdapter` server-side client-credentials OAuth; 2026 development-mode search limit 10 |
| Tap a Spotify song | Spotify application / website | HTTPS Universal/App Link, with Spotify doing the streaming |
| Full playback controls in Breezze | Spotify App Remote/Connect **when separately configured** | Not yet activated; requires authorized Spotify developer app, user OAuth and SDK setup |
| Music Videos tab | Official YouTube player | Visible YouTube IFrame, no media extraction |
| Google YouTube Data API | YouTube public video metadata | Video search and metadata ONLY |
| Existing Deezer / YT Music saved items | Historical bookmarks, **not music streams** | Keep metadata and avoid destructive database deletes. New song search goes to Spotify only |
| Spotify downloads | The official Spotify app alone | No Spotify CDN proxy, download grant, R2 ingest or Breezze offline copy |
| Spotify mixing / lossless enhancement | Not available through Spotify APIs | Never transcode, B-Mix, separate stems, inspect PCM, or modify Spotify content |

**Note:** Spotify does not expose raw third-party audio URLs to Breezze's `just_audio` engine. Its mobile App Remote SDK controls the installed Spotify app; on-demand listening through that integration requires Spotify Premium. Spotify's Web Playback SDK is browser-oriented and similarly requires Premium. Breezze's own free-app requirement does not grant any Spotify subscription.

## Implementation on main

- `backend/api/src/providers/spotify.adapter.ts`: Spotify metadata via official OAuth client-credentials flow, safely bounded search, typed validation, short Redis cache and explicit unavailable states. Never forwards any credential or audio bytes.
- `provider-registry.service.ts`: only Spotify and Breezze internal rights catalog registered for MUSIC discovery. YouTube Music is not a song backend. The separate YouTube metadata/controller stays available for VIDEO use.
- `apps/mobile/lib/app/bootstrap.dart`: songs discovered from Spotify only; the playback resolver refuses Spotify and YouTube IDs as raw native media. Legacy Deezer preview playback disabled.
- `apps/mobile/lib/core/audio/spotify_playback_handoff.dart`: validates Spotify IDs and launches the official Spotify app/web link. A successful app launch is **not** proof of started playback.
- Search and Browse source-aware UI: Spotify tracks lead to Spotify playback and display source attribution. YouTube video IDs open visible official player. Spotify IDs are blocked from native queues, Breezze downloads and mixed playback lists.
- Retired `youtube_explode_dart`, the native YouTube audio resolver, audio-range probe and the old real-YouTube-audio acceptance workflow. No raw YouTube audio code in production Flutter source.

## Spotify Developer setup required before production activation

1. Create the Spotify application at <https://developer.spotify.com/dashboard> and enable Web API. Add the appropriate API products. Keep **Client Secret server-side**, never in Flutter, GitHub or screenshots.
2. Store `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` as encrypted Railway backend variables. `SPOTIFY_ENABLED=true` alone cannot activate the provider without both credentials. Do not reuse the Google/YouTube key.
3. Spotify's February 2026 development-mode changes require the *developer/app owner* to have Premium and restrict authorized users to five. Its July 2026 change pools quota across developer-account Client IDs. Public release requires Spotify's extended-access review/approval and compliance; adding more client IDs does not bypass this limit.
4. For in-Breezze Spotify App Remote transport and controls, register Android package/SHA-1, iOS bundle ID and HTTPS/universal redirect. Implement and test user authorization and actual Spotify SDK connection separately. The current code uses a safe official-app handoff, **not an embedded native Spotify decoder**.
5. Verify Spotify user plan, consent, region, playback restrictions, explicit attribution, accessibility, disconnection and privacy requirements. Do not mix Spotify audio with YouTube video streams, add DSP mixing, or compute Spotify-derived audio metrics.
6. Keep production release/deployment freeze until after a reviewed Railway deployment, Spotify credentials configuration, CI success and real-device Spotify-app playback verification.

## Verification gates

- Backend: `cd backend/api && npx prisma generate && npm run typecheck && npx jest --runInBand src/providers/spotify.adapter.spec.ts src/providers/provider-registry.service.spec.ts`.
- Flutter: `cd apps/mobile && flutter pub get && flutter test test/spotify_playback_handoff_test.dart test/core/audio/playback_source_policy_test.dart test/features/player/unified_media_handoff_test.dart`.
- Automated workflow: `.github/workflows/spotify-integration-verify.yml`; this does not require real Spotify credentials and **cannot** certify commercial playback.
- Android + iOS native simulator acceptance must pass on the same latest commit. Physical Spotify mobile app and Premium account are needed to validate official App Remote playback.

## Policy references

- Spotify Developer Policy: <https://developer.spotify.com/policy>
- Spotify Android App Remote: <https://developer.spotify.com/documentation/android>
- Spotify iOS App Remote: <https://developer.spotify.com/documentation/ios>
- Spotify Development Mode quotas: <https://developer.spotify.com/documentation/web-api/concepts/quota-modes>
- February 2026 migration: <https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide>
- July 2026 quota update: <https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates>
