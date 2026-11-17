# Breezze 🎵

**An open-source music platform.** One Flutter codebase, every platform. Discovery, lossless streaming, and offline downloads.

> Breezze is an independent, original product. It is not affiliated with YouTube, Google, Spotify, or Apple. Capability categories familiar from major music services are used as functional reference only — Breezze uses its own brand, tokens, components, and design language. No proprietary assets, source code, private APIs, or trade dress from any other product are used.

## What is Breezze?

Breezze mixes the strongest ideas of two open music clients — [BitChord](https://github.com/kushagrasinghx/BitChord) (Kotlin, Android) and [Liner](https://github.com/tryliner/desktop) (Electron, desktop) — rebuilt from scratch as one shared-codebase Flutter app:

| Idea | Origin | In Breezze |
|---|---|---|
| Pluggable module sources, lossless FLAC/ALAC, crossfade, Automix, downloads, scrobbling | BitChord | `packages/audio_contracts` |
| Cross-platform shell, fallback playback, syllable-synced lyrics, local tracks | Liner | `packages/api_client` source chain |
| One codebase across OSes | Both | ADR-001 (Flutter-first) |

**No code was copied from either repository.** All Breezze code is original; both projects are credited as inspiration.

## Architecture

```
breezze/
├── apps/mobile          # Flutter app (Android, iOS, + desktop/web targets)
├── packages/
│   ├── design_system    # Tokens, Atmosphere materials, theme
│   ├── audio_contracts  # Player, queue, lyrics, crossfade, AutoMix, quality
│   └── api_client       # Source chain, downloads, membership, provider adapters
└── docs/                # ADRs, audit gap register
```

**Source chain (how music is fetched):** a BitChord-style pluggable module source is primary; a Liner-style local/handoff source is the fallback (spec §52.7). If no licensed source exists, Breezze shows an unavailable state — it never fakes a stream.

## Features

- **Lossless + Hi-Res quality tiers** — AAC → Lossless FLAC → Hi-Res, honest labels only (never upsampled)
- **Offline downloads** — eligibility-checked, resumable, app-private storage
- **Premium tiers** — free/premium/family/student; lossless, Hi-Res, downloads, AutoMix are server-gated entitlements
- **Automix** — DJ transitions with beat-matching (±10% BPM, double-time folding)
- **Word-synced lyrics** — enhanced-LRC engine with binary-search lookup
- **Scrobbling** — Last.fm/ListenBrainz-style sink with the 30-second rule
- **Monochrome Atmosphere design system** — your tokens, light + dark

## Getting started

Requires Flutter 3.22+.

```bash
git clone -b breezze https://github.com/MetroKim/MetroMusic.git
cd MetroMusic/apps/mobile
flutter pub get
flutter run
flutter test ../../packages
```

## Downloads & rights

Offline downloads are entitlement- and rights-checked on the server side before any job starts (spec §54.2). Breezze never proxies or re-hosts streams it isn't authorized to serve.

## License

Open source — see the repository LICENSE. Breezze's original code is released to the community for study, modification, and contribution.

## Contributing

PRs welcome. See `docs/audit/gap-register.md` for the honest per-requirement status — pick any NOT STARTED line and go.
