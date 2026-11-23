# Breezze branch consolidation audit

**Snapshot:** 22 November 2026. **Canonical production source:** `main`.

GitHub reported **54 branches** and **zero open PRs**. These 34 branch heads match the exact head SHA of an already **merged** pull request; their accepted changes were integrated to `main` through GitHub's merge/squash history. The cleanup workflow removes only those now-redundant branch pointers, not the PRs or files in `main`.

## Verified already-merged branch pointers (34)

| Branch | PR | Verified head SHA |
| --- | --- | --- |
| `feat/account-preferences-wiring` | #44 | `867aa7926bb6` |
| `feat/apple-music-parity-navigation-search` | #51 | `4ab0efb89356` |
| `feat/breezze-audio-engine-foundation` | #8 | `67ecec6ebd70` |
| `feat/breezze-embedded-official-music-videos` | #52 | `b61615ec1462` |
| `feat/breezze-end-to-end-listener-wiring` | #34 | `8c1cc1c47efe` |
| `feat/breezze-immersive-lyrics` | #50 | `97612e4f4865` |
| `feat/breezze-in-app-completion-contract` | #33 | `1b59dce98cfd` |
| `feat/breezze-in-app-support-requests` | #41 | `7902f9548dbe` |
| `feat/breezze-personalized-home-feed` | #38 | `366876a0aaac` |
| `feat/deezer-soundcloud-catalog` | #49 | `d8313812cee8` |
| `feat/durable-playback-heartbeats` | #47 | `41ca653a59c4` |
| `feat/flutter-playback-session-integration` | #29 | `f32372d29057` |
| `feat/home-feed-rights-safe-recommendations` | #25 | `b02ca5b770c6` |
| `feat/liquid-glass-design-system` | #20 | `61996b19c45c` |
| `feat/playback-session-pause-resume-contract` | #28 | `7d18ce77e3d0` |
| `feat/player-sleep-timer` | #45 | `30e081a06f54` |
| `feat/recommendations-onboarding-preferences` | #40 | `b2006cf8369c` |
| `feat/server-authorized-playback-sessions` | #26 | `44991ae1a860` |
| `feat/youtube-music-primary-provider` | #7 | `e5f425fdac26` |
| `feature/breezze-product-experience` | #6 | `1c80e62b1bc1` |
| `fix/backend-atomic-playlist-ordering` | #16 | `50c5498d36eb` |
| `fix/backend-catalog-foreign-keys` | #15 | `356aa206a4ed` |
| `fix/backend-download-provider-capabilities` | #11 | `8ec507b6d54a` |
| `fix/backend-listening-history-validation` | #13 | `f8a80669c22a` |
| `fix/backend-lyrics-translation-rights` | #10 | `eff14003a1c1` |
| `fix/backend-normalize-account-emails` | #12 | `c82eb16d5d1b` |
| `fix/backend-provider-rights-gate` | #9 | `3d9acba4c612` |
| `fix/backend-territory-and-range-audit` | #30 | `538e86cc7f7a` |
| `fix/breezze-local-account-data-isolation` | #42 | `013e1c318bbb` |
| `fix/breezze-offline-sync-outbox` | #39 | `3f8084f43ec8` |
| `fix/liquid-glass-green` | #35 | `263ca62df7fa` |
| `fix/production-api-connectivity` | #48 | `66e7f30ff5a2` |
| `fix/security-global-login-account-throttle-main` | #18 | `59d973f4ab47` |
| `fix/settings-feedback-entry` | #43 | `6d6fb265c832` |

## Intentionally retained branches (20 at snapshot)

| Branch | Audit disposition |
| --- | --- |
| `breezze` | Historical foundational reference; held. |
| `chordline` | Historical foundational reference; held. |
| `feat/apple-music-liquid-glass` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/durable-idempotent-listening-events` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/durable-playback-heartbeat-recovery` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/home-feed-and-idempotent-play-events` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/home-personalized-recommendation-shelf` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/liquid-glass-token-layer` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/liquid-glass-tokens` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feat/rights-filtered-recommendations` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feature/free-video-search` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feature/metro-music-experience` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `feature/premium-look` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `fix/backend-short-lived-media-grants` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `fix/download-territory-trust-boundary` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `fix/liquid-glass-frontend` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `fix/p0-admin-rbac-and-ci` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `fix/security-global-login-account-throttle` | Not verified as a matching merged PR head; retain for separate diff/rights review. |
| `frontend-finish-pass` | Old ancestor; no unique commits ahead of main, retained until separate cleanup decision. |
| `main` | Canonical code; do not delete. |

## Safety gates

1. A branch is eligible only if a closed PR has `merged_at`, the same source repository, and an **exact recorded PR head SHA** matching the branch's current Git SHA.
2. Refuse deletion for `main`, `breezze`, `chordline`, protected branches, and any branch linked to an open PR.
3. Re-read every branch SHA at deletion time; if moved, leave it intact.
4. No code from rejected, superseded or diverged branches is automatically merged. Some contain outdated API/rights logic.
5. PRs, merged commits and their history remain auditable on GitHub. Deletion is only of redundant branch refs.

## Notable nonmerge decision

`fix/download-territory-trust-boundary` diverged from `main` and includes an older download-provider capability flow that would sign Breezze media paths for external providers. The current `main` **rejects third-party storage downloads without an authorized source** and already incorporates correct bounded/suffix byte-range handling. Do not merge this branch wholesale.

The legacy `feat/apple-music-liquid-glass` branch adds an isolated unreferenced `bz_probe.dart` and a material recipe overlapping the tested design system already in `main`. This is **not** a safe production merge solely on its branch name.

**Passing CI on a stale branch is not enough.** Canonical CI must be green after repository modifications; device playback and UX acceptance remain separate from build validation.
