# Breezze: Liner + BitChord backend feasibility (2026-11-26)

**Decision: do not vendor or run either app as Breezze's music catalog/streaming backend.** Re-evaluate only after licensing and provider authorizations are obtained.

## Verified source projects

### Liner — https://github.com/tryliner/desktop
- Repository: Electron/React desktop frontend, not an independent music database or a deployable media service.
- README explicitly states that its client depends on the *official Liner API* for catalog, streaming and lyrics. The repository's `electron/youtube/` folder handles playback fallback; its `backend/` is not a public catalog server.
- Main-branch LICENSE: **Liner Source-Available & Non-Commercial Contribution License v1.1 (2026)**. Sections 4(c) and 4(e) prohibit extracting its core algorithms or security/signing/audio mechanics for third-party applications and running derivative builds with alternative servers (including private builds); other sections also limit commercial use and redistribution.
- **Do not copy source, signer binaries, API signing code, audio algorithms, cryptographic assets, or call protected Liner services.** A separate agreement from the copyright holders is required for reuse.

### BitChord — https://github.com/kushagrasinghx/BitChord
- Main codebase: Kotlin Android **YouTube Music client**, not a separate song database; its music availability reflects its underlying providers.
- `backend/README.md`: Go **Listen Together synchronization/party** service (rooms, clocks, WebSocket), *not* a general music catalog or audio-hosting backend.
- LICENSE: **GNU GPLv3**. Redistribution of code adapted into Breezze may invoke corresponding-source and same-license obligations, inconsistent with a closed-source mobile release unless structured and reviewed carefully. Direct external use of an independently deployed service may have different implications; obtain legal review.
- Adopting BitChord's YouTube Music stream-resolution implementation would also reverse Breezze's explicit **YouTube video-only** provider policy and would not independently authorize native commercial audio playback.
- **Do not vendor BitChord code or its backend into Breezze's proprietary services without a compatibility and rights review.**

## What solves the real problem

Breezze currently searches only the **first 25 Deezer tracks** per query (not the platform's full inventory). Increase the first page to **50** (implemented in `deezer.adapter.ts`) and keep relevance ranking. This improves initial result coverage but does not expand the underlying catalog's licensed geographic availability.

Keep a source-aware aggregation architecture:

1. **Keyless Deezer metadata search** — primary public catalog. Use Redis for hot query results, stable `bz:deezer:<id>` and provider attribution.
2. **Spotify metadata** — optional only with official credentials; do not impersonate Spotify or use private client authentication.
3. **MusicBrainz metadata** — separate clearly attributed backup when enabled under appropriate use terms. Public web-service free access is restricted to noncommercial use and rate limits. For scalable catalog breadth, evaluate the MusicBrainz **CC0 core database export** and self-hosted indexing, respecting individual data licenses and attribution.
4. **YouTube music videos** — visible official video player only, not an audio catalog or extraction worker.
5. **Future recording partners** — add adapters only if they grant catalog access *and* explicit streaming/offline rights for Breezze, with per-territory entitlement and audit logging. Never treat a metadata URL as an audio URL.

## Acceptance gates
- Two independent song providers should never be mislabeled or duplicated under another brand.
- On Spotify-unconfigured or upstream failures, Deezer searches still return matches without blocking UI; MusicBrainz is a fallback only if authorized and rate budget is available.
- Limit/relevance tests for Deezer; prefetch/caching latency measured with real authorized providers, not invented metrics.
- No external Liner/BitChord source/vendor dependencies; no protected keys or client-signature bypass.
- Full native music playback remains **not complete** until an audio rights partner can supply complete recording streams to Breezze.
- Verify backend typecheck, Jest, Flutter tests and Android/iOS emulator acceptance at the same commit before production.
