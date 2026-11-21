# YouTube Music provider — corrected scope

> **Superseded:** This document previously described YouTube Music as the primary playback provider and documented external-player handoff for ordinary song results. That design does not satisfy Breezze's native-player product contract and must not be treated as the target architecture.

The corrected provider, product, backend, frontend, rights, caching, and acceptance architecture is maintained in:

- [BREEZZE_CORRECTED_PRODUCT_ARCHITECTURE.md](./BREEZZE_CORRECTED_PRODUCT_ARCHITECTURE.md)

## Current truthful capability

The `youtube_music` adapter is a best-effort metadata/discovery adapter using the unofficial `ytmusicapi` sidecar.

```ts
{
  search: true,
  metadata: true,
  availability: false,
  playback: false,
  download: false
}
```

This means the adapter can supply catalogue metadata. It does not grant Breezze permission or a technical entitlement to extract, proxy, cache, stream, or download YouTube media. A YouTube video may be viewed through an official YouTube player integration, separately from the Breezze audio player.

## Required behavior

- Do not put metadata-only YouTube tracks in the native queue.
- Do not show Download, Play Next, Add to Queue, background playback, or lossless controls for these items.
- Keep Breezze favorites and playlists as Breezze-owned metadata records; do not imply YouTube Music account sync.
- Native playback must use a separately approved playback provider or user-owned local file through the single Breezze audio engine.
- Do not merge this provider into the playback resolver until it has a separately reviewed and explicitly permitted playback capability.

The existing external-player handoff code is transitional and is not the target UX. It must be removed from song playback entry points and retained, if needed, only for a dedicated music-video viewing flow using the official player.
