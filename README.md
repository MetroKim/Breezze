<div align="center">

# 🎵 Chordline

### One phantom music client, everywhere.

**"The line between platforms disappears."**

Hi-Res lossless playback, pluggable sources, syllable-synced lyrics and a
floating overlay player — on Android and desktop, from a single
Kotlin Multiplatform core.

_Kotlin Multiplatform · Compose Multiplatform · GPLv3_

</div>

> [!IMPORTANT]
> Chordline is not affiliated with, endorsed by, or connected to YouTube,
> Google, Spotify, or any streaming platform. Use at your own discretion.

---

## What is Chordline?

A phantom synthesis of two open music clients:

| Parent | Contributed |
|---|---|
| **[BitChord](https://github.com/kushagrasinghx/BitChord)** (Kotlin, Android, GPLv3) | Lossless FLAC/ALAC engine, bit-perfect USB DAC output, gapless playback + true crossfade, Automix beat-matching, sleep timer, per-network quality ceilings, offline downloads, pluggable module sources, Spotify/Google sign-in, Discord Rich Presence, Last.fm/ListenBrainz scrobbling, 13 lyrics providers, artwork-driven Material 3 frosted-glass UI |
| **[Liner](https://github.com/tryliner/desktop)** (Electron, Desktop) | Cross-platform desktop shell, floating always-on-top overlay player, syllable-synced lyrics, local library protocol (`chordline-local://`), Feature-Sliced Design, 11-language i18n |

**No code was copied from either repository.** Chordline re-implements the
merged feature set from scratch and credits both projects as inspiration.

### The core bet

Replace Electron with **Kotlin Multiplatform + Compose Multiplatform**, so both
surfaces share one logic core (`shared/`) and one design system (`sharedUi/`).

---

## Features (implemented core)

- **CrossfadeController** — true crossfade, 0–12 s, fires exactly `crossfadeMs` before track end
- **GaplessQueue** — preloads the next track, no silence between songs
- **Automix [Beta]** — beat-matching tempo-stretch (±10 % with double-time folding), energy-aware transition lengths
- **SleepTimer** — fixed presets or "stop after this track"
- **LyricsPipeline + LrcParser** — line- and word-synced enhanced LRC, 12-provider registry
- **SourcePlugin registry** — pluggable module sources with health checks (YouTube Music, Spotify, Local)
- **ScrobbleBus** — Last.fm / ListenBrainz with the 30-second minimum-play rule
- **DiscordRichPresence** — live track/artist/progress hook

### Roadmap

Per-network quality ceilings, bit-perfect USB exclusive output, WASM request
signer (`signer/`), Web (wasmJs), Wear OS, Android TV, WebGL lyrics backdrop,
offline downloads, 11-language i18n.

---

## Architecture

Feature-Sliced Design: imports only point down the layers
(`app → widgets → features → entities → shared`).

```
chordline/
├── shared/       # KMP core: playback, sources, lyrics, scrobbling
├── sharedUi/     # Compose design system (frosted-glass, artwork palette)
├── app/          # Android (Compose)
└── desktop/      # Compose Desktop (Windows/macOS/Linux) + overlay window
```

## Getting started

Requires JDK 17+, Gradle 8.9+, and the Android SDK (for `:app`).

```bash
git clone -b chordline https://github.com/MetroKim/MetroMusic.git
cd MetroMusic

./gradlew :shared:desktopTest    # run the core characterization tests
./gradlew :desktop:run          # desktop app (Windows/macOS/Linux)
./gradlew :app:assembleDebug    # Android APK
```

## Building desktop distributions

```bash
./gradlew :desktop:packageMsi   # Windows
./gradlew :desktop:packageDeb   # Linux
./gradlew :desktop:packageDmg   # macOS
```

## License

GPLv3 — see [LICENSE](LICENSE).
