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

## Preserved earlier Breezze branding directions

These are **historical reference designs** from the user's original design Library, not replacements for the white-on-black logo used by the shipping Flutter client. Their original bytes and SHA-256 digests are preserved:

- [Breezze Music Branding Collection.png](historical-brand/Breezze%20Music%20Branding%20Collection.png) — `92c76ef08b277acd5f38d191f0148d9d76977cf12c9e485d60098f0f39427eb0`; dark/bright gradient and monochrome explorations.
- [Breezze Music Brand Styleboard.png](historical-brand/Breezze%20Music%20Brand%20Styleboard.png) — `d8e02e118262add42e598892bfcd2fef0239d07d6d7df5a53f92c9a2b6a0887c`; alternative Glass Disc design concepts.
- [Breezze Music Brand Guideline Board.png](historical-brand/Breezze%20Music%20Brand%20Guideline%20Board.png) — `393b6cf6572ed03051e329b87b067e1070b95d684308547b642593c51e4ba231`; alternate icon usage/export board.
- [Glass Disc SVG and PNG export specification](historical-concepts/GLASS_DISC_EXPORT_SPEC.md) — full original text SHA-256 `929503b0aeebf95a12af121c7a192d606a206fc95d13e53413bc08e11dec2314`.
- [Concept C / The Drift export specification](historical-concepts/DRIFT_EXPORT_SPEC.md) — full original text SHA-256 `fe8d213a9d5c83d4bfd53abaebc2f5135aa59dc3ebc243e2468797acd9a00aee`.

Original alternative-concept *SVG designs* described in those export specifications were not supplied in the file Library or in either Git repository. A PNG styleboard and textual specifications are **not proof** the complete original SVG variants exist. Do not generate substitute assets and mark them as migrated. Existing approved monochrome app icon and original vector symbols remain the shipping source of truth.
