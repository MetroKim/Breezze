# Breezze legacy-to-independent migration inventory

Evidence checkpoint: 2026-11-25. This file records **source code and assets actually migrated**, while distinguishing superseded branches and outstanding handoffs.

## Canonical repositories

- Active, independent production source: `MetroKim/Breezze`, branch `main` (not a BitChord fork).
- Historical, BitChord-forked project: `MetroKim/Breezze-legacy-fork`, branch `main`; retain intact as an audit/archive reference, **not** a second deployable app.
- Verified path + Git blob comparison: **477 of 477 files on the old main are already present** on the independent main. The old-main snapshot has no missing paths. The independent repo had 2 additional files and 10 modified files at comparison commit `13b6c9e`; newer implementations take precedence over old modified files.

## Recovered brand sources from the unmerged historical monochrome-brand implementation

- `apps/mobile/assets/icons/breezze-logo-white.svg`: editable white-on-black vector lockup.
- `apps/mobile/assets/icons/breezze-logo-black.svg`: editable black-on-white vector lockup.
- These two original paths were **absent** from the independent `main`, but available as Git blobs in current repo PR #56's history. They are now restored as supplementary brand source files.
- Existing launcher icons for iOS, Android, macOS, Windows and web, symbol/mark SVGs, `bz_brand_icons.dart` and `pubspec.yaml` asset registration were already present; **do not replace the selected monochrome white mark on black** with an unrelated speculative concept.
- The source SVG lockups include editable SVG `<text>` dependent on the chosen font; the current Flutter app intentionally continues shipping the existing rasterized wordmark for consistent native rendering.
- Added a Flutter regression test verifying the two recovered vectors and existing icon sources load through the registered Flutter asset bundle.

## Supplied additional visuals — distinct from the older Git fork

The user-provided `Breezze_Frontend_Figma_Import_Pack.zip` contains **16 screen SVGs**, one overview board SVG and PNG plus README. The `breezze_flutter(1).zip` file contains UI mock/reference code, not a licensed backend, usable audio source or real album art. This source is not interchangeable with production widgets; **migrate its reusable layout semantics rather than replacing real Riverpod/auth/audio code with mocks**. The independent app's `docs/design/BREEZZE_UNIFIED_FRONTEND_HANDOFF.md` already describes the corresponding runtime architecture. The **exact original source archives have now been transferred** to `docs/design/reference/`, with independently checked byte-for-byte Git blob hashes:

- `Breezze_Frontend_Figma_Import_Pack.zip`: 19 entries (16 screen SVGs, a board SVG and PNG, and the original README). SHA-256 `6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435`. Contains visual mockups only, not deployable production interfaces.
- `breezze_flutter_ui_reference.zip`: the preserved original 14,743-byte user-supplied Flutter visual reference archive `breezze_flutter(1).zip`. SHA-256 `140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40`. Its mock player/catalog are not part of the runtime.
- `tools/verify_design_handoff_archives.py` validates both archives, CRC integrity, SVG structure, exact expected screen inventory, and archive safety in CI.

No ZIP contents are automatically extracted into Flutter `lib/` or `assets/`; this preserves the working Supabase-first authenticated API, signed player, and app branding.

Other design references in the personal file library specify multiple competing concept variants; actual source SVG artwork for all requested historical alternatives is not present as files in either Git main. Do not invent matching assets and claim the original pack was copied.

## Branch triage and deliberately excluded historical code

Some older unmerged `Breezze-legacy-fork` branches contain `legacy/kotlin-client/` (approximately 1,500+ files), a BitChord-derived second implementation, `Jamendo`, browser social-login variants, Radio, duplicate player state and/or abandoned experiments. **Do not copy the old application wholesale**; it would violate the four-tab, Supabase-first, no-radio, listener-first architecture and create duplicate playback/auth stacks. Review any branch-specific isolated tests and components separately against current code and quality gates. Preserve source branch refs so no history is lost.

The separate unmerged frontend PR #65 concerns design foundations and must be validated against the current production-backed Flutter components before adoption. Native Google/Apple and YouTube playlist consent remain external OAuth verification tasks, not consequences of asset migration.

## Release/verification

- Active code lives only in the independent `main`; no unreviewed migration is pushed to the production API.
- GitHub CI must pass on the migration commit. Verify Android and iOS launcher rendering on emulator separately; the presence of generated files is not emulator proof.
- Keep user-approved white-on-black identity unchanged and avoid redundant generated platform files.
