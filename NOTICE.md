# Chordline — Notice

This branch (`chordline`) contains **Chordline**, a phantom synthesis project
created by re-imagining the merged feature sets of two open-source music
clients:

- **BitChord** — https://github.com/kushagrasinghx/BitChord (GPLv3)
- **Liner (tryliner/desktop)** — https://github.com/tryliner/desktop
  (Liner Source-Available & Non-Commercial Contribution License)

## No code was copied

All Chordline source code was written from scratch. Neither repository's
source was consulted beyond their public READMEs and directory structures.
Chordline re-implements the *ideas* documented in those READMEs:

- From BitChord: crossfade controller, gapless queue, Automix
  beat-matching, sleep timer, pluggable source registry, multi-provider
  lyrics, scrobble bus (30-second rule), Discord Rich Presence layer.
- From Liner: floating always-on-top overlay window, local-file scheme
  (`chordline-local://`), frosted-glass design tokens, Feature-Sliced layout.

## Licensing of new code

The new Chordline code in this branch is intended to be GPL-3.0-compatible
per the project design. Because the underlying repository already carries an
MIT LICENSE for the original MetroMusic code, the repository maintainer
should decide one of:

1. Keep MIT for everything (simplest; both parents were only sources of
   ideas, not code), or
2. Add a per-module license file for the Chordline additions.

## Trademarks

Chordline is not affiliated with, endorsed by, or connected to YouTube,
Google, Spotify, BitChord, Liner, or any streaming platform.
