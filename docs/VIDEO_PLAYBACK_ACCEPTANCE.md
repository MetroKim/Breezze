# Breezze video playback — acceptance evidence and safe configuration

This applies to the original Breezze Flutter player; it does not change YouTube
terms, create unauthorized streams, or give us rights to third-party recordings.

## Supported paths

1. **Official YouTube**: visible `youtube_player_iframe` on Android, iOS,
   macOS and web; on Linux and Windows, the explicit official YouTube watch
   page is used. Uploader embedding settings and YouTube restrictions apply.
   Video watch queues are foreground-only; no detached/background audio.
2. **User-picked MP4**: `video_player` on Android/iOS/macOS and web.
   Windows/Linux device file video remains unsupported until a tested native
   implementation is added; use the official YouTube watch page for YouTube.
3. **Licensed Breezze MP4**: only accept a short-lived, purpose-bound signed
   `/video/{UUID}/stream` grant from the configured media origin.
   The Cloudflare Worker must validate the HMAC and check asset presence.
4. **Offline MP4**: only native device files with an active rights lease;
   offline file paths are not opened on web or unsupported desktop platforms.

## Secure media origin

Set the Flutter build-time option `--dart-define=BREEZZE_VIDEO_CDN_ORIGIN=https://breezze-media.ykw8vmq7ph.workers.dev`.
The app defaults to that production hostname. In a private staging build, set
this to the isolated trusted **HTTPS origin only** for the QA media Worker, e.g.
`https://breezze-media-qa.ykw8vmq7ph.workers.dev`. Never point an
untrusted user-provided URL here. The server's `CDN_BASE_URL` must match.
The client rejects expired grants, malformed UUIDs, wrong `download`
purpose, malformed HMAC signature encoding and URL host/userinfo/fragment
tricks. Client URL shape validation is not a replacement for Worker signing.

## Audio/video handoff

The current global player is paused before entering any video surface.
When video closes, native audio is resumed **only** if it was playing before,
the same queue entry and recording are still selected, and the app is resumed.
An OS pause, account switch, queue replacement or route replacement must not
start unexpected audio playback.

## Device test matrix required before release

- Android emulator: official visible YouTube video; skip previous/next while
  visible; fullscreen; background pause; open-on-YouTube fallback.
- iOS simulator: same plus app-interruption and native WebView lifecycle.
- macOS/web: embedded YouTube functionality, fixed playlist watch queue.
- Windows/Linux: explicit YouTube watch page handoff, no fake embed.
- User-picked MP4: decode a real authorized file, pause/resume, seek ±10s,
  replay without closing the screen, scrubbing, fill/fit, and background pause.
- Licensed signed MP4: Worker returns 206 Range and rejects expired/forged
  signatures and wrong upload/download purpose; verify stream and expiry.
- Offline: owner-bound lease expiry, file-not-found, account switching and
  unsupported-platform rejection.

## What CI certifies

The isolated `video-reliability-qa.yml` workflow checks Flutter analysis
and pure tests for origin/lease enforcement, seek boundaries, timer formatting,
foreground YouTube watch queue and native audio restoration policy.

**Flutter compile and unit tests are not evidence of actual video decoding.**
Device player, YouTube embed restrictions and signed-production media delivery
require separate recorded acceptance evidence.
