# YouTube Music — Breezze provider capability contract

**Current status:** YouTube Music is connected as a primary music-discovery source and the target of an **opt-in, non-production audio feasibility experiment**. Deezer supplies official public catalog, artist, release, and chart metadata. Audius is not an active provider.

## What Breezze enables

The private Python `ytmusicapi` service supports catalog search, song metadata, artist search and profiles, album metadata, playlists, watch queues, mood playlists, explore content, music-video discovery and available chart metadata. NestJS exposes those through the `youtube_music` provider routes. The Flutter client can use them for discovery and opens official music videos in a visible YouTube player.

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

## Experimental native audio — distinct from production capability

The existing `/tracks/{videoId}/audio-candidate` sidecar endpoint uses `ytmusicapi.get_song()` to inspect already-direct HTTPS `googlevideo.com` audio URLs. The authenticated NestJS `/api/v1/providers/youtube_music/audio-candidate/{videoId}` route validates the MIME type, hostname and expiration. A Flutter development build may probe it before falling back to visible YouTube playback.

This path is **disabled unless** `BREEZZE_YTMUSIC_AUDIO_EXPERIMENT=true` is set on both the API and sidecar and the development client is built with the corresponding Dart define. Both services deliberately refuse this experiment in production. It does not support offline YouTube downloads, audio-byte proxying or cipher/DRM bypass. Source URL availability does not establish Google authorization, and direct URLs may not play on a device because of IP binding or expiry.

## Keep clear boundaries

- **Search/artist/album/chart/playlist/mood metadata:** available through `ytmusicapi`.
- **Official music videos:** playable using the visible YouTube integration, subject to its restrictions.
- **Native audio candidate:** non-production experiment only; unverified end-to-end.
- **Offline downloads:** only Breezze-controlled/licensed media after a separate, explicit download rights decision. No automatic YouTube Music download permissions.
- **Single audio engine:** all legitimate native playback flows use Breezze's existing audio engine and queue. Never create an Audius adapter or a second player as a workaround.
- **No invented quality badges or chart rankings.** Only label metrics supplied by the source.

## Acceptance gates before production

Confirm upstream permission, successful stream retrieval on Android/iOS emulators, seek and background behavior, expired URL renewal, source integrity, territory handling and takedown behavior. Until these pass, production `playback` and `download` remain `false`.

See [provider contract](../providers/active-catalogue.md) and [Unified v6 architecture](./BREEZZE_V6_MAINLINE_INTEGRATION.md).
