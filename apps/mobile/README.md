# Breezze 🎵

**Music discovery, streaming, downloads and word-synced lyrics — one Flutter codebase, every platform.**

## Features

- **Search** — live results, keyless, with artwork
- **Stream** — highest-bitrate audio via native engine (ExoPlayer / AVFoundation)
- **Now Playing** — breathing artwork, transport controls, seek, **word-synced karaoke lyrics**
- **Download** — offline library: `audio.m4a` + `cover.jpg` + `lyrics.lrc` per track
- **Favorites** — persisted locally, play-all queue
- **Design** — monochrome token system, light + dark, Atmosphere materials

## Run it

Requires Flutter 3.22+.

```bash
git clone -b breezze https://github.com/MetroKim/MetroMusic.git
cd MetroMusic/apps/mobile

flutter create .        # generates android/, ios/, web/ runners
flutter pub get
flutter analyze         # should be clean
flutter test            # runs the package test suites
flutter run             # no keys, no defines — works out of the box
```

## Architecture

```
apps/mobile                  # Flutter app
packages/
  design_system/             # tokens, Atmosphere materials, theme
  audio_contracts/           # player state machine, queue, lyrics, crossfade,
                             # AutoMix, scrobbling, quality tiers (+ tests)
  api_client/                # playback source, LRCLIB lyrics, downloads
                             # library, favorites, provider contracts
docs/
  architecture/              # ADR-001
  audit/                     # gap register (honest per-requirement status)
```

**Keyless by design:** search + playback run through `youtube_explode_dart` (no API key, no quota); lyrics through LRCLIB (free, community). No credentials to configure.

## Notes

- Breezze is an independent product, not affiliated with any streaming platform.
- Streams are resolved per-play; downloads store the highest-bitrate audio rendition available at download time.
