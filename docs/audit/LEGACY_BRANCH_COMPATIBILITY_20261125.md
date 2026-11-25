# Breezze historical fork branch compatibility audit — 25 November 2026

## Scope and verification standard

Canonical shippable source is the **independent** `MetroKim/Breezze` repository's `main`. Historical material is in `MetroKim/Breezze-legacy-fork`, not an alternate deployment target. The starting release baseline `dfc304647dccc3498afbeee7ecf379175ec71acd` completed 9/9 CI jobs, 4/4 CodeQL analyses and web-preview smoke successfully on 25 November 2026. Build success is **not** emulator or production OAuth/rights acceptance.

The original fork main tree's 477 tracked file paths are accounted for in the independent main: see [migration status](LEGACY_BREEZZE_MIGRATION_STATUS.md). The following dispositions concern **branch-only history**. Compare metadata was fetched for each old-fork branch against old-fork `main`. Ahead counts are historical commits and **not** counts of features that should be copied.

| Historical branch | Observed relationship to old fork main | Compatibility decision |
| --- | --- | --- |
| `backup/pre-detach-20261125` | Behind by 3 commits, 0 ahead | No distinct head changes to import; retain fork history. |
| `integration/audio-first` | Behind by 314 commits, 0 ahead | Ancestor/reference only; do not duplicate the modern player. |
| `integration/import-histories` | Diverged; 1 ahead, adding only `.github/workflows/import-histories.yml` | Historical archival automation, not runtime functionality. Do not run it with insufficient workflow permissions. |
| `fix/p0-idempotent-get-timeout-retry` | Diverged; 9 ahead (API and workflows) | Idempotent GET retry with token-switch guard already exists in independent main. PR #66 restores bounded timeouts across POST/PATCH/DELETE and an API regression test, without retrying mutations. |
| `fix/search-recovery-release-audit` | Diverged; 13 ahead (search, player, release and edge concerns) | PR #66 ports account-switch query isolation and empty-player back navigation plus legacy widget tests. Remaining edge/deployment changes require separate exact-diff/release review; no blind workflow overwrite. |
| `codex/verify-audio-resume-race` | Diverged; 6 ahead | PR #66 incorporates exact-entry/track handoff safety; historic listener runtime fixtures/CI must be assessed against current native acceptance tests, not copied as a second player stack. |
| `feat/audio-first-video-handoff` | Diverged; 58 ahead | AuthorizedDownloadGrant and offline lease policy are already active on main; PR #66 restores the additional video/audio resume guard and its original test. Other changes are conditional on media rights and native acceptance. |
| `fix/deezer-audio-queue` | Diverged; 1 ahead | Do not conflate a Deezer preview with licensed full-track playback or migrate an older player/stream-source policy wholesale. |
| `feat/supabase-auth-breezze` | Diverged; 80 ahead (auth, language, profile, Supabase functions) | Do not overwrite current sign-in/session/DB integration or introduce deprecated edge functions. Language and profile changes still need implementation-level review, and verified Google/Apple OAuth acceptance is separate. |
| `integration/p0-p1-verification` | Diverged; 46 ahead (auth bridge, API timeout, listener fixtures and release workflows) | PR #66 restores bounded HTTP timeouts; Supabase identity transition and listener runtime acceptance need distinct integration gates. Preserve the old branch until reconciled. |
| `main` | Historical original at `5fe8263d7f93db4e8b08ad6b16e675e95afe0e51` | All 477 tracked source paths represented on independent main; newer implementation takes precedence over exact old byte equality. |

## Targeted fixes under review

PR [#66](https://github.com/MetroKim/Breezze/pull/66) applies only compatible, testable behavior to the **existing** Flutter implementation:

- Search cancels old typeahead and clears the visible previous-account query as well as previous search results.
- Official video return restores audio only for the same queue entry and same recording after route disposal, while paused and in the foreground.
- Empty Now Playing route provides accessible Close and Back to music exits.
- GET, POST, PATCH and DELETE requests have bounded timeouts, retaining the current one-retry-only policy for idempotent GETs.

The corresponding historical regression tests were copied from old fork histories. **Do not mark any PR #66 changes as merged or passing until the exact head has passed required checks and main was reverified.**

## Open release blockers

1. **Historical commit preservation:** The old fork's remaining unique Git objects are not all in the independent repository. GitHub rejected archive ref pushes containing old `.github/workflows/listener-runtime.yml` using the current app token without the `workflows` permission. Retain old fork. GitHub workflow permission or an authorized history-preservation method is required before deleting it.
2. **Native acceptance:** Android emulator and iOS simulator playlist/offline, artist pin and real audio-decoder integration tests have dedicated `workflow_dispatch` workflows, but passing compilation alone is not evidence that these tests ran.
3. **Current product contracts:** Supabase-first must-sign-in, Deezer for catalog metadata, YouTube Music metadata-only until audio licensing, official YouTube video surfaces, one player, four tabs, no Radio/Audius replacement, and server-issued downloadable-media rights are non-negotiable migration constraints.
4. **Non-portable historical changes:** Language/UI features, auth bridge behavior and release/deployment workflows require a new implementation review against the canonical source. A historical branch's ahead count is not proof of missing current functionality.

**Result:** Main-tree source preservation is verified. Compatibility triage is documented, with safe repairs in PR #66. Complete migration certification is explicitly **still blocked** by unique history archival, exact-head merged CI, and native acceptance evidence.
