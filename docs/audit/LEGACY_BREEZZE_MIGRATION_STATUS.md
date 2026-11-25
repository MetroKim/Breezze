# Breezze legacy migration and preservation audit

**Source of truth:** `MetroKim/Breezze` (independent `main`). This document distinguishes byte-level source preservation from runtime integration, UI design references, abandoned upstream scaffolds, and Google permissions.

## Verified previous-main source mirror

- Original repository: [MetroKim/Breezze-legacy-fork](https://github.com/MetroKim/Breezze-legacy-fork), old main Git SHA `5fe8263d7f93db4e8b08ad6b16e675e95afe0e51`.
- Independent repo: [MetroKim/Breezze](https://github.com/MetroKim/Breezze), **477/477 original main tracked files are present** at their original paths. Git tree entry paths were compared, not inferred from filenames or README claims.
- Original mobile icon inventory: **23 SVG and 3 PNG files** in `apps/mobile/assets/icons/`. Each is still present; automatic Flutter asset-bundle tests now assert the complete inventory. Additional native launcher resources exist under `apps/mobile/{ios,macos,web,windows}/`.
- The current independent source intentionally has newer edits; do **not** overwrite them with older blob hashes to force exact byte equality.
- Historical source branch: `archive/previous-breezze-main-20261125` (exact original SHA). Additional extant original Git commits preserved as `archive/legacy-audio-first` and `archive/legacy-pre-detach`.
- Current independent app is **Flutter** with its own NestJS/Prisma backend, Supabase Google/email identity, Cloudflare API/Media Workers and authorized content gate. No Audius, generic unlicensed audio stream extraction, or revived Radio tab should be introduced by source migration.

## Previously unmerged design changes

- [PR #65: frontend-polish foundations](https://github.com/MetroKim/Breezze/pull/65) merged into independent `main` as `18dd8f69efaefcc903eef376885af5b903490278`, after PR CI, CodeQL and web-preview smoke passed.
- Historical [PR #56: monochrome branding](https://github.com/MetroKim/Breezze/pull/56) is a conflict-prone old branch; the official black/white logo SVGs were recovered on main without replacing current player or appearance logic. Its Radio and duplicate appearance controller are **not** current product requirements.
- Selected original design source is preserved in the repo's `apps/mobile/assets/icons/`, `docs/design/`, and `packages/design_system/`. The Flutter app loads the icons from `pubspec.yaml`.

## User-provided visual references (separate from shippable runtime)

- `Breezze_Frontend_Figma_Import_Pack.zip`: 16 screen SVG concepts, one combined board SVG, one PNG overview and README; source ZIP SHA-256 `6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435`. **This exact source ZIP has now been committed** to `docs/design/reference/Breezze_Frontend_Figma_Import_Pack.zip` (verified Git blob SHA `627609d5e8cfa470d64117378bfc0cc2f819dde7`) along with the original Flutter UI-reference ZIP (`docs/design/reference/breezze_flutter_ui_reference.zip`, verified blob SHA `190a51803b9de70800fe097e2d40a1ae5aa51ca1`). Their SHA-256 values match the user's original uploads. `tools/verify_design_handoff_archives.py` checks the exact archives in CI. It is not an editable Figma component library or a completed Flutter port. Figma source: https://www.figma.com/design/ekwtakfmPO7IPjMAbu1iZC
- `breezze_flutter(1).zip`: small sample scaffold, source SHA-256 `140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40`. Its simulated timer-driven playback and mock music catalog must **not** replace native just_audio, active queue or authorized backend.
- Current `docs/design/BREEZZE_UNIFIED_FRONTEND_HANDOFF.md` documents where to apply reference UI decisions; user-selected app icon is the white symbol on a black ground.
- If the original expanded “Concept C / Drift” vector pack or other standalone icon variations are desired, retrieve and inspect their **actual SVG masters**; written export specifications alone are not source files. Do not fabricate original marks and claim they were migrated.

## Branch-only source that is NOT yet fully migrated

The old fork also contains unmerged `feat/supabase-auth-breezze`, `integration/p0-p1-verification`, `feat/audio-first-video-handoff`, `codex/verify-audio-resume-race` and other branches. Their current trees include deprecated Kotlin/BitChord source, mock/UI artifacts and conflicting auth/media approaches. Most of these branch Git objects do not exist in the independent repository (the GitHub Git API rejects their old commit SHAs); **they have not been imported merely because old main was mirrored**.

**Do not delete the old fork yet.** First preserve the remaining branch histories independently or reconcile their uniquely needed, safe functionality with current Flutter/Prisma tests and exact-main CI. Never merge all branch trees blindly, overwrite live Railway data, or duplicate deprecated providers.

## Validation gate

1. All previous-main file paths present in independent repo: **PASS**.
2. Previous-main 26-icon bundle presence: newly covered by Flutter tests; wait for the **current commit** CI before declaring test PASS.
3. Frontend polish source merged: **PASS**; separate device/emulator visual acceptance remains open.
4. Original user-provided Figma and Flutter visual ZIPs transferred **byte-for-byte** to the repository: **PASS**, with CI archive verifier.
5. All historical **unmerged branch commits** preserved independently: **NOT COMPLETE**. Archive attempt [run #45564087967](https://github.com/MetroKim/Breezze/actions/runs/45564087967) fetched 11 old fork branches, but GitHub refused to push branches containing `.github/workflows/listener-runtime.yml` because the connected GitHub App lacks `workflows` permission. The failed import workflow was removed from `main` to keep the release pipeline clean. Keep the old fork intact until an authorized Git credential/workflow permission is available; do not misreport those branches as imported.
5. Production rights and OAuth permissions: remain under their own verified gate; source migration is not authorization.
