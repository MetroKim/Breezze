# Breezze original UI source handoff — archive, not runtime

These are byte-for-byte copies of the original user-supplied visual sources. They were transferred into the independent `MetroKim/Breezze` `main` without modifying or replacing Flutter's authoritative application.

## Archive contents

**Breezze_Frontend_Figma_Import_Pack.zip** (540,353 bytes; SHA-256 `6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435`): 16 original **390 × 844 SVG screen concepts** — Home, Browse, Library, Search, Now Playing, Lyrics, Artist, Album, Playlist, Sign In, Settings, Downloads, Queue, Onboarding, Replay and Account — one combined SVG composition board, a PNG overview and the original README. These SVGs are visual handoff frames, **not** a complete editable Figma component library or real backend-connected UI.

**breezze_flutter_ui_reference.zip** (14,743 bytes; SHA-256 `140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40`): exact preserved user-supplied `breezze_flutter(1).zip`, including lightweight player, artist, lyrics and controls examples. It contains mocked player/catalog state and has an empty cover-art folder; do not copy it over the real app.

## Access and verified preservation

Archives are deliberately stored under `docs/design/reference/`, **not** the Flutter application's asset bundle. This avoids duplication, fake music playback, stale routes, and inflated production binaries. To inspect an archive, extract it separately with any ZIP program. To verify source integrity on a checkout, run `python3 tools/verify_design_handoff_archives.py`. This verification also runs in GitHub CI.

## Current design decisions

The actual Flutter production UI remains in `apps/mobile/lib` and shared components in `packages/design_system`. Canonical navigation is **Home · Browse · Library · Search** with a single global player. The approved Breezze launcher identity is a white custom mark on a black background. Earlier alternative color concepts and old Radio/navigation prototypes are historical references, not active design overrides.

For screen-by-screen parity and implementation status see `docs/design/BREEZZE_UNIFIED_FRONTEND_HANDOFF.md` and `docs/audit/LEGACY_BREEZZE_MIGRATION_INVENTORY.md`.
