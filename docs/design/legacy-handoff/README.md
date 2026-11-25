# Breezze — preserved historical original design sources

This folder preserves **byte-identical** assets supplied during the previous Breezze design phases. They belong to the independent [MetroKim/Breezze](https://github.com/MetroKim/Breezze) repository. The current shipping app stays under `apps/mobile/`; these files are **historical design evidence**, not production assets or a second implementation.

## Exact original source archives
- `originals/Breezze_Frontend_Figma_Import_Pack.zip` — sixteen separate screen SVGs (Home, Browse, Library, Search, Now Playing, Lyrics, Artist, Album, Playlist, Sign In, Settings, Downloads, Queue, Onboarding, Replay, Account), 16-screen SVG board, PNG board and README. SHA-256: `6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435`.
- `originals/breezze_flutter(1).zip` — the visual-only prior Flutter reference including screens, mock catalog, mock player, theme, and widgets. **Never build or ship its dummy playback code.** SHA-256: `140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40`.

## Original brand/reference boards
- `originals/Breezze Music Brand Styleboard.png` — SHA-256 `d8e02e118262add42e598892bfcd2fef0239d07d6d7df5a53f92c9a2b6a0887c`.
- `originals/Breezze Music Brand Guideline Board.png` — SHA-256 `393b6cf6572ed03051e329b87b067e1070b95d684308547b642593c51e4ba231`.
- `originals/Breezze Music Branding Collection.png` — SHA-256 `92c76ef08b277acd5f38d191f0148d9d76977cf12c9e485d60098f0f39427eb0`.

All three boards are 1536 × 1024 PNGs.

## Original specs and active source separation
- `PNG-EXPORT-SPEC.md` — historical Glass Disc (Concept B) export recommendation.
- `breezze-concept-c-export-spec.md` — historical Drift (Concept C), a **competing** alternative. The names in an export specification are not proof every depicted vector was ever supplied. No missing icon may be fabricated and called the original.
- Recovered actual monochrome vector lockups are installed at `apps/mobile/assets/icons/breezze-logo-black.svg` and `breezze-logo-white.svg`, and retain the existing Flutter design system, four-tab layout and launcher icons. No new Radio, alternative provider, Auth0 or sample catalog is activated.

## Verification
Run `python apps/mobile/tool/verify_legacy_design_handoff.py` from the repository root. GitHub CI runs the same exact-source verifier. A successful source migration does **not** imply an editable Figma component library or fully emulator-verified app UX. See `docs/migrations/PREVIOUS_BREEZZE_SOURCE_AUDIT.md` for the legacy-branch reconciliation.
