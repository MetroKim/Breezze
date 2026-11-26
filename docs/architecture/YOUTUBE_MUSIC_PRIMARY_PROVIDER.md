# YouTube Music — discovery and official video only

**Current status:** Breezze selects **Deezer as its primary public catalog and external native-audio preview source** (up to 30 seconds). YouTube Music provides supplementary catalog discovery and foreground official music video playback. Audius is not an active provider.

## What Breezze enables

The private Python `ytmusicapi` service supports catalog search, song metadata, artist search and profiles, album metadata, playlists, watch queues, mood playlists, explore content, music-video discovery and available chart metadata. NestJS exposes those through the `youtube_music` provider routes. The Flutter client uses them for discovery and opens official music videos in a visible YouTube player; it no longer calls the non-production audio probe.

```ts
{
  search: true,
  metadata: true,
  availability: false,
  playback: false,
  download: false,
  albums: true,
  artists: true,
  playlists: true,
  videos: true,
  charts: true,
  moods: true
}
```

`availability`, `playback` and `download` describe **authorized, production-capable media delivery**, not merely an upstream API method. No project-level capability flag can grant permission from YouTube.

## Historical experimental audio — not in the Flutter playback path

The existing `/tracks/{videoId}/audio-candidate` sidecar endpoint uses `ytmusicapi.get_song()` to inspect already-direct HTTPS `googlevideo.com` audio URLs. The authenticated NestJS `/api/v1/providers/youtube_music/audio-candidate/{videoId}` route validates the MIME type, hostname and expiration. Breezze's current Flutter code does **not** call this endpoint, including in development builds. YouTube song interactions open the visible official player.

This historical backend probe is **disabled unless** `BREEZZE_YTMUSIC_AUDIO_EXPERIMENT=true` is set on both the API and sidecar. Both services deliberately refuse this experiment in production. It does not support offline YouTube downloads, audio-byte proxying or cipher/DRM bypass. Source URL availability does not establish Google authorization, and direct URLs may not play on a device because of IP binding or expiry.

## Keep clear boundaries

- **Search/artist/album/chart/playlist/mood metadata:** available through `ytmusicapi`.
- **Official music videos:** playable using the visible YouTube integration, subject to its restrictions.
- **Native audio:** Deezer preview clips, resolved through the existing Breezze audio engine. YouTube Music audio candidates remain a disabled, unused backend experiment.
- **Offline downloads:** only Breezze-controlled/licensed media after a separate, explicit download rights decision. No automatic YouTube Music download permissions.
- **Single audio engine:** all legitimate native playback flows use Breezze's existing audio engine and queue. Never create an Audius adapter or a second player as a workaround.
- **No invented quality badges or chart rankings.** Only label metrics supplied by the source.

## Acceptance gates before production

Confirm upstream permission, successful stream retrieval on Android/iOS emulators, seek and background behavior, expired URL renewal, source integrity, territory handling and takedown behavior. Until these pass, production YouTube `playback` and `download` remain `false`. Deezer metadata and preview access likewise do not grant full-song playback or offline downloads.

See [provider contract](../providers/active-catalogue.md) and the sole [V8 implementation and acceptance plan](../BREEZZE_UNIFIED_ENGINE_V8_IMPLEMENTATION_PLAN.md).
