# Breezze V8.4 — Security, Frontend–Backend and UX acceptance ledger

**Status:** DEVELOPMENT / RELEASE FROZEN. **Date:** 2026-11-26.
**Base:** `main` at `b82414c24654a5cb8a68e121b9ea2bf6536b2230`.
This file is a set of measurable acceptance gates, **not a claim of 100% completion**.

## No-release rule

No GitHub Release, source archive, publicly downloadable development artifact,
store publication, signed distribution or new production deployment until all
mandatory gates below pass on the **same reviewed commit**, every required
recording/territory right is documented, and the owner separately approves
release. A passing unit test is not a playback or licensing license.

## Security inspection scope

| Layer | Tool / evidence | Status at this checkpoint |
| --- | --- | --- |
| Full Git history | Existing Gitleaks V8 history workflow | Passing on recent PR heads; rotation of historically exposed keys not proved |
| TypeScript, Python, Actions, Android | Existing CodeQL | Per-language CI required on final commit |
| Dart and app code, backend/IaC source | New Semgrep CE 1.187.0 whole-tree CI | Added as candidate; scan outcome pending |
| Node, Dart, Python dependency advisories | New OSV 2.7.1 whole-tree CI | Added as candidate; scan outcome pending |
| Exact dependency resolution | New Python lockfile inventory | **BLOCKED:** at minimum uncommitted app pubspec.lock and backend/worker npm locks; ytmusicapi Python ranges unpinned |
| Supabase | Connected project's security advisor | Returned zero lints on 2026-11-26; manual RLS/ownership audit still needed |
| Public API docs | Production Swagger policy | Hardened in draft; backend Jest and live 404 check pending |
| Account transport | [Draft PR #73](https://github.com/MetroKim/Breezze/pull/73) | Cross-account delayed 200/401 race fix unmerged; integrate and test |
| Metadata sidecar signed URLs | [Draft PR #77](https://github.com/MetroKim/Breezze/pull/77) | Remove experimental direct-audio URL exposure before any production promotion |
| Native audio / temporary offline plaintext | V8.3 renderer and BZA8 crypto | Crypto/secure-key native, lifecycle and account-switch tests not signed off |

No code/secret/finding artifacts are uploaded by the new security workflow. A
scanner failure must not be reclassified as an ordinary warning. Its report
stays in the ephemeral runner and a safe count goes to the job log. A clean
scanner result is not proof of no vulnerability or of secure business logic.

## UI contract — original Breezze, Apple Music-inspired navigation

Exactly four visible tabs: **Home / New / Library / Search**.
No Radio/Downloads/Settings fifth tab. Preserve the single global
`PlayerController`, mini-player, Now Playing, queue and audio_service session.
The icon source remains Breezze's original official pixel-B, not Apple assets.

| Surface | Backend/data integration | Mandatory empty/error/offline UX |
| --- | --- | --- |
| Home | Signed-in user history, saved music, follows, recommendation data from authorized APIs | Real personalized content or explicit "nothing yet"/reload; never fabricated tracks |
| New | Published provider metadata for releases, charts, genre/mood, official music-video entry | Provider attribution, loading and retry, metadata-only versus playable distinction |
| Library | Owner-scoped playlists/albums/artists/offline leases and per-user download jobs | Empty library instructions, expired/revoked download explanations, no cross-account leaks |
| Search | Safe, debounced query to shared Breezze API, metadata provenance, legal player handoff | Clear zero-results, transient retry, invalid response, rights denial and offline states |
| Global Now Playing | Rights-authorized session + heartbeat, queue, lock-screen, interruptions | Resolving/buffering/failure/expired-grant recovery with no preview misrepresented as full audio |
| Auth/profile/settings | Supabase verified sign-in, device security, real functional toggles | Signed-out gate on all destinations; disabled unconfigured OAuth providers must be clearly marked |

### Visual and interaction acceptance (still required)

- Capture and review **real rendered** Home/New/Library/Search, mini-player,
  Now Playing, auth, settings, download errors, and all detail pages on Android,
  iOS, web, Linux and Windows as supported. Audit all routes for dead buttons,
  empty placeholders, overlapping text, clipped controls, missing API actions
  and duplicate navigation.
- Phone widths 320/390/430dp; tablet 768dp; desktop 1280/1440px; portrait
  and landscape; dark/light; text scaling 100% and 200%; reduced motion.
- VoiceOver/TalkBack meaningful labels, correct focus order and activation;
  desktop keyboard traversal/shortcuts, focus indicators, MPRIS and physical
  media keys; tappable controls at least 44×44 logical pixels where feasible.
- Consistent Breezze typography, tokens, album-art proportions, accent use,
  adaptive sidebar, mini-player geometry and all empty/error/skeleton states.
- Document actual before/after screenshots and emulator/device logs privately,
  not as public GitHub attachments. No claim of pixel-perfect Apple UI; maintain
  Breezze's original brand, code and assets.

## Data, auth and playback E2E gates

1. Verify every Flutter API call against the NestJS/OpenAPI endpoint and
   server DTO/authorization contract; no screen may call a metadata provider
   as a replacement for a rights-aware playback grant.
2. Validate ownership across Supabase RLS, Prisma writes, queue/session/logout,
   and download worker restarts. Verify account A to B isolation and stale HTTP
   response suppression; use test accounts, not production listener data.
3. Two actual rights-cleared full recordings: stream + seek + range +
   heartbeat + background + expired grant; 403/404/429/5xx; real worker R2 bytes.
   Metadata discovery and generated QA sine tones do not prove commercial rights.
4. Optional AutoMix: authorized dual native decks and BPM/key analysis with a
   tested fallback; interrupt/revoke both immediately if either grant dies.
5. Offline: BZA8 AES-256-GCM + secure per-user key, no plaintext transient
   persistence at rest, tamper/revocation/airplane-mode tests on devices.
6. Fresh same-SHA Flutter/Dart/Jest/Prisma/Workers/CodeQL/SAST/OSV/Gitleaks
   results; signed and installed platform packages; network and auth acceptance.
   Any missing evidence is BLOCKED, not PASS.

## Independent current CI observations

- Draft V8.3 [PR #79](https://github.com/MetroKim/Breezze/pull/79):
  AutoMix fail-closed and seven client fixture fixes with typed analysis
  clean-up; its final exact-head CI remains the required merge gate.
- Draft Linux [PR #80](https://github.com/MetroKim/Breezze/pull/80):
  newest Linux distro compatibility [run 45818711078](https://github.com/MetroKim/Breezze/actions/runs/45818711078)
  ended SUCCESS (CI compile, ELF, real MPRIS registration, distro linkage).
  This does not certify audio output or hardware keys.
- New V8.4 security + client resilience branch: source changes committed,
  **scan and app/backend test results pending**; do not merge blindly with
  other drafts, especially PR #73's edits to the same API client.

## Next remediation order

1. Run the new security workflow; triage real findings, establish committed
   dependency locks (and Python transitive dependency hashes) without leaking
   credentials. Do not bypass a scanner to obtain green CI.
2. Reconcile the outstanding auth/signed-URL PRs, then verify every API
   frontend/backend contract and automated backend permissions.
3. Carry out a full original Breezze design/functional UI walkthrough,
   fix each empty or dead route, and run real widget/accessibility tests.
4. Resolve licensed audio assets/rights, native playback/offline AutoMix
   and physical devices; signed distribution remains frozen.

Update the existing [V8 tracker #78](https://github.com/MetroKim/Breezze/issues/78)
and [master #27](https://github.com/MetroKim/Breezze/issues/27) with
confirmed SHA/run evidence. Never mark a gate DONE because code was drafted.
