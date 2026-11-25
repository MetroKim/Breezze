# Previous Breezze migration — verified provenance

**Source:** [MetroKim/Breezze-legacy-fork main](https://github.com/MetroKim/Breezze-legacy-fork/tree/main), archived into [independent MetroKim/Breezze main](https://github.com/MetroKim/Breezze/tree/main) through [PR #64](https://github.com/MetroKim/Breezze/pull/64).

## Git tree verification

- Compared all Git blobs across the old fork `main` (477 files) and the independent repository `main` (479 files) on 25 November 2026.
- **All 477 old-main paths are present in independent main.** No path from old-main was dropped.
- The independent main has two additional files and 10 changed source files (quality workflow, album cloud sync, YouTube Music client, backend library, smoke tests and OAuth documentation). These are *not* automatically regressions; the newer versions are authoritative.
- Existing app brand files, launcher icons, native platform icon catalogs, design system, API, Flutter client and four-tab shell are already included.
- The old fork still holds unmerged feature branches. Those branches contain historical duplicate Kotlin/BitChord content, stale radio/social modules and older authentication implementations; **do not merge them verbatim into the independent, Flutter-first app**, as that would restore removed product scope and weaken the unified production design.

## Brand SVG assets recovered from the earlier design branch

The following monochrome vector lockups were still absent from the independent main and were recovered verbatim from the old [monochrome branding branch (PR #56)](https://github.com/MetroKim/Breezze/pull/56):

- `apps/mobile/assets/icons/breezze-logo-white.svg` — high-contrast white Breezze logo/wordmark, preferred on black surfaces
- `apps/mobile/assets/icons/breezze-logo-black.svg` — black Breezze logo/wordmark for light surfaces

These are supplemental editable design source assets. The existing working Flutter launcher, `BzBnoteMark`, `BzRibbonLogo`, and source-generated platform icons remain active to prevent a second competing logo path.

## Supplied frontend archives

The previous uploads `breezze_flutter(1).zip` and `Breezze_Frontend_Figma_Import_Pack.zip` were inspected independently. The first is a demo Flutter UI with fake catalog, timer-driven player, and no real album art; the second contains 16 editable-SVG visual references (Home, Browse, Library, Search, Now Playing, Lyrics, Artist, Album, Playlist, Sign In, Settings, Downloads, Queue, Onboarding, Replay, Account), a combined vector board and derived PNG.

The visual/interaction ideas are already mapped to working Breezze Flutter counterparts in [the unified frontend handoff](../design/BREEZZE_UNIFIED_FRONTEND_HANDOFF.md). **Do not overwrite the live global player, account gate, catalog resolver or downloaded rights with demo mock state.** Keep the independent repo's current Flutter code authoritative.

## Acceptance criteria

The previous main repository has been migrated path-for-path; supplemental black/white logo masters are imported from its earlier design work. A *complete* audit of unmerged branches, third-party Kotlin fork files, Figma editable components, old screenshots, and any archive that is not accessible in the current session is a separate explicit stage, not a claim of full completed feature migration.

Approved product constraints retained: Breezze name, dark black/white preferred identity, Home/Browse/Library/Search only, one shared player, Supabase authentication, separate explicitly consented read-only YouTube account linking, rights-gated media, no Audius or duplicate radio tab.
