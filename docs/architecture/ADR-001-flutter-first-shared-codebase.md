# ADR-001: Flutter-First Shared Codebase

- **Status:** Accepted
- **Date:** 2026-11-17
- **Deciders:** MetroKim
- **Supersedes:** Chordline KMP + Compose client direction

## Context

Breezze must ship one consumer product across many operating systems
(Android, iOS, web, Windows, macOS, Linux, and later TV/car) from a single
codebase (spec §25). The inherited Chordline project uses Kotlin
Multiplatform + Compose Multiplatform, which shares logic well but splits
UI effort across platforms and does not match the product spec's mandated
client direction (Flutter + Dart, Riverpod, go_router, §25/§37.3).

## Decision

1. **The Breezze consumer client is a Flutter app.** One Dart codebase
   organized by feature (§26.2), one state approach (Riverpod, §51.3),
   typed navigation via go_router, and a single global `PlayerController`
   owning playback state.
2. **The Chordline KMP `shared` core is the reference implementation and
   test oracle, not the shipped client core.** Its proven logic —
   crossfade controller, gapless queue, Automix beat-matching, LRC
   parsing, scrobble bus (30s rule) — is ported to Dart with the 13
   existing characterization tests translated alongside.
3. **Platform divergence is confined to adapters behind Dart interfaces**
   (`AudioEngineAdapter`, secure storage, background audio), per §37.3:
   native code only where Flutter packages don't expose the capability.
4. **Compose UI code is retired as Flutter screens land.** The KMP
   `shared` module is fully ported to Dart (`packages/audio_contracts`,
   `apps/mobile/.../core/audio`); the Compose `sharedUi`/`desktop`/`app`
   modules remain on the `chordline` branch for reference until the
   Flutter app reaches feature parity, then are removed.
5. **Design tokens are the single source of truth.** The tokens in
   `packages/design_system` (spec §21.1) are consumed by both the Flutter
   theme and any web/admin surfaces; no literal colors outside tokens.

## Consequences

**Positive**
- ~90–95 % shared code across all target platforms; one release train.
- Matches the Breezze spec exactly (§25, §26, §51).
- Proven playback algorithms carry over with their tests — no re-derivation.

**Negative / costs**
- Porting effort for the KMP core (bounded: ~6 small modules, all with tests).
- KMP `shared` and Flutter coexist until parity; tracked in the gap register.
- iOS/macOS audio specifics must go through Flutter platform channels.

## Migration order (P0 per §61.1)

1. Design tokens package (`packages/design_system`) — tokens + theme.
2. `packages/audio_contracts` — port playback engine interfaces from KMP.
3. Port `CrossfadeController`, `GaplessQueue`, `Automix`, `LrcParser`,
   `ScrobbleBus`, `SourcePlugin`/`SourceRegistry` to Dart + tests.
4. One global `PlayerController` (Riverpod) + playback state machine (§53.2).
5. Shell + Listen Now scaffold from tokens; Compose retirement begins.

## Compliance

- Spec §25: Flutter-first ✅ (this ADR)
- Spec §50.1: don't rewrite working code — porting with tests, not discarding ✅
- Spec §26.2/§51: feature-first folders, layered architecture ✅
