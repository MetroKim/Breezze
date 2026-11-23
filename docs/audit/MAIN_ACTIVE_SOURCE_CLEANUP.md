# Breezze main — active-source cleanup

This cleanup is applied directly to `main`. It removes obsolete source trees from the **current Git checkout** without rewriting Git history or deleting user data.

## Removed from active source
- Legacy Kotlin/BitChord-derived client tree (`legacy/kotlin-client/`) that is not a dependency of Flutter builds.
- A second, unused Chordline/Kotlin Multiplatform application: root `app/`, `desktop/`, `shared/`, `sharedUi/`, root Gradle catalog/build files.
- Empty/superseded `radio-fragment.prisma` and `lyrics-fragment.prisma` placeholders; the real Prisma schema and migration history are retained.
- Out-of-scope **user-to-user** social following NestJS module and API; Breezze's **music-artist** following in `library/` remains a product requirement.

## Keep (not duplicates)
- `apps/mobile/` Flutter client including login, four-tab navigation, global audio/player and cross-platform adapters.
- `packages/design_system/`, `packages/audio_contracts/`, `packages/api_client/` are shared Flutter packages with distinct purposes.
- `backend/api/` NestJS production gateway, working authentication until verified Supabase cutover, Prisma schema/migrations, artist follows, playlists, listening events, Replay, lyrics and rights enforcement.
- `backend/ytmusicapi/`, `infra/cloudflare/`, `.github/workflows/`, `docs/`.
- Root `LICENSE` and `NOTICE.md` and `docs/legal` for attribution. Deleting a historical tree does not remove Git history or automatically resolve third-party licensing questions.

## Held for dependency and migration work
- Legacy NestJS authentication is currently active on main. Supabase Auth replacement belongs behind validated rollout, not an untested deletion.
- Source-specific providers (including any old Audius paths) must be migrated against catalog and rights tests, not removed blindly.
- User playlist and offline/download data are retained; deletion can permanently lose user records.
- Historical design documents may contradict the current product contract. Normalize their status and pointers instead of pretending every document is executable source.
- Music video, B-Spatial, AutoMix DSP, concerts, lyric translation/pronunciation, yearly Replay and library-wide downloads remain separately gated by implementation, test evidence, provider rights, and media fidelity.

## Verification rules
- Confirm the current `main` tree contains no obsolete client or social module paths.
- Run CI, web preview, CodeQL. Reject a release on a failing gate.
- Keep artist following; user-to-user social graph is out of scope.
- No claim that source deletion also deletes historical Git commits, licenses or rights obligations.
