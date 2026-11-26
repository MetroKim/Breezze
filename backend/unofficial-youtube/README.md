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
