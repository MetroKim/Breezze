# Breezze experimental YouTube.js audio probe

This experiment **does not alter Breezze production playback, downloads, Supabase auth, or cloud media**. It tests whether an unofficial InnerTube library can resolve **actual audio bytes** for a publicly accessible Creative Commons video.

Run `npm install && npm run test:probe` with Node 22. The default sample is the Blender Foundation's Big Buck Bunny (CC BY 3.0). The probe requests at most 4 KiB of the audio representation; it never saves music files or prints signed media URLs. The result is JSON beginning with `BREEZZE_AUDIO_PROBE=` and independently shows:
- Metadata accessible
- Audio format resolved
- HTTP 200/206 response
- Recognized WebM/MP4/AAC header and first bytes
- Failure state (without bearer URLs)

No credentials or bypass techniques are used. **Passing this test for one CC example is not evidence of permission or reliable native playback of commercial music.** YouTube API developer policies restrict separation of audio and unauthorized download/cache. The user's request to experiment must not be misrepresented as a granted license.

Source https://github.com/LuanRT/YouTube.js
Blender licensing https://peach.blender.org/about/

## Optional isolated service

A private Node service at `src/server.mjs` adds `GET /health` and a strict, bearer-authenticated `GET /v1/audio/:videoId` for a **rights-cleared allowlist only**. It supports HTTP Range, streams in memory without writing content, strips bearer links from errors, and is disabled in production or when the experiment switch is off.

Run locally with a private 32+ byte token, `NODE_ENV=development`, `BREEZZE_INNERTUBE_AUDIO_EXPERIMENT=true`, `BREEZZE_AUDIO_TEST_ALLOWLIST=<approved-11-character-video-id>`, and `BREEZZE_INTERNAL_AUDIO_TEST_TOKEN=<secret>`. Start with `docker compose --profile experimental up --build unofficial-youtube` from `backend/`. The port is loopback-only and the service requires a Bearer token.

`npm run test:contract` tests authorization, allowlist, URL and Range guards. Real audio is evaluated by `npm run test:probe` and GitHub Actions workflow `Experimental InnerTube audio byte probe`.

**Known GitHub-hosted runner result, 27 Nov 2026**: on both the CC-BY Blender short and a CC-BY Scott Buckley music upload, upstream returned `LOGIN_REQUIRED` for WEB/MWEB; the existing Python YTMusic adapter returned `LOGIN_REQUIRED` for the music upload and `UNPLAYABLE` for the film. No playable media bytes were verified. This cannot be described as a working native music engine. Use official visible YouTube embed until a permitted source is verified.

## Verified real remote artist music (not YouTube)

In addition to the unrelated InnerTube experiment, the public-domain
recording **Promise — Keith Adler** (148 seconds) was independently verified
on GitHub Actions: original Ogg returned HTTP 206 and 256,000 decoded PCM
bytes over 8 seconds. Its Wikimedia-hosted MP3 transcode also returned HTTP
206 with MP3 header and decoded 256,000 PCM bytes. These are real external
audio bytes, not a generated tone, not a YouTube extraction and not Audius.

- Source/rights: https://commons.wikimedia.org/wiki/File:Promise.ogg
- Live acceptance workflow: `.github/workflows/real-open-song-probe.yml`
- Backend: `GET /api/v1/audio-proof/track` and `.../playback`, both
  Supabase/JWT-protected and OFF unless `BREEZZE_PUBLIC_AUDIO_PROOF=true`
  with a nonproduction NODE_ENV and Railway environment.
- Flutter: build only a development version with
  `--dart-define=BREEZZE_PUBLIC_AUDIO_PROOF=true`. The New tab then shows
  **Full-song playback proof**, which uses Breezze's existing single global
  player. No local audio storage or playlist-content substitution.
- Backend and Flutter flags must BOTH be enabled for the demo.
- Production stays disabled even with the flag. This is a real open-licensed
  acceptance fixture, **not** a solution for YouTube Music commercial tracks.
- MP3 offers broader device compatibility than the Ogg original. Native
  emulator verification remains required for acceptance.
