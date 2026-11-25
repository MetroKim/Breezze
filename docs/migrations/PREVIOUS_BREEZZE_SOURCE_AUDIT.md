# Previous Breezze → Independent Breezze: audited migration

## Source and completeness
- **Source:** [MetroKim/Breezze-legacy-fork](https://github.com/MetroKim/Breezze-legacy-fork), branch `main`, commit `5fe8263d7f93db4e8b08ad6b16e675e95afe0e51`.
- **Target:** [MetroKim/Breezze](https://github.com/MetroKim/Breezze), independent `main`. The 25 November 2026 Git tree audit found **477/477 files** from the legacy `main` branch at identical relative paths and Git blob hashes. The target had two additional files; ten matching paths differed because the target contained newer changes. The legacy `main` snapshot is **fully mirrored**, not a reason to overwrite the current monorepo.
- Previous brand lockup vectors `breezze-logo-black.svg` and `breezze-logo-white.svg` were additionally recovered from the historical open [monochrome brand PR #56](https://github.com/MetroKim/Breezze/pull/56) into `apps/mobile/assets/icons/`, with a Flutter asset test. Keep the current monochrome launcher and native icon sets authoritative until a separate reviewed change replaces them.

## Original separately supplied design evidence
- `Breezze_Frontend_Figma_Import_Pack.zip`: 16 layout-reference SVG screens, combined SVG board, PNG overview and README. ZIP integrity **PASS**, all 17 SVG files parse as XML. SHA-256 `6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435`.
- `breezze_flutter(1).zip`: 14-file **visual-only** Flutter reference containing mock player/catalog state, not the production app. ZIP integrity **PASS**. SHA-256 `140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40`.
- Three previously supplied 1536 × 1024 brand reference boards (Branding Collection, Brand Styleboard, Brand Guideline Board) are now preserved byte-for-byte in `docs/design/legacy-handoff/originals/` alongside both original ZIP files. They are **historical alternatives**, not an authorized instruction to replace the active black/white brand.
- Exact historical handoff specifications are preserved in this directory as `PNG-EXPORT-SPEC.md` and `breezze-concept-c-export-spec.md`. They propose **different brand concepts** (Concept B and Concept C) and must not be silently blended together or used as authoritative runtime artwork.

## Branch reconciliation: preserve history, not duplicate products
- Existing old branches contain **unfinished or superseded alternatives**, not automatically verified requirements. Some carry a full 1500+ file upstream Kotlin/Compose mirror, legacy radio, old Jamendo providers and alternate auth flows. Copying them wholesale would break the current Flutter-first product and re-introduce code deliberately removed.
- Relevant sources remain retrievable by immutable [legacy branch history](https://github.com/MetroKim/Breezze-legacy-fork/branches) and the [monochrome PR #56](https://github.com/MetroKim/Breezze/pull/56). Any *new* implementation must be ported as an independent targeted change, preserve Supabase authority/one player/four tabs, and pass Flutter and backend CI before activation.
- User-provided Flutter concepts and Figma SVG screens are **reference materials**. Do not import their timer-simulated playback or hardcoded songs into the production app.

## Verification and limitations
- Repository source migration: checked via exact Git blob hashes.
- Recovered lockups: checked via new asset test; native launchers remain their existing verified files.
- Handoff ZIPs and three brand PNG boards: exact originals committed as binary files to `docs/design/legacy-handoff/originals/` and tested via SHA-256, ZIP checks, 17 Figma SVG XML parses and 1536×1024 board PNG dimensions. These are archival references, not committed native Flutter code or a completed editable Figma component system.
- Remaining work is feature-by-feature implementation and emulator/screenshot acceptance; no design concept or branch gets a fake production PASS merely because its source was archived.
