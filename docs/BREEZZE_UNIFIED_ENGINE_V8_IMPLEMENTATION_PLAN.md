# Breezze Unified Engine V8 — Implementation & Acceptance Plan

**Owner:** Breezze engineering | **Branch:** `main` | **Baseline:** `cb71606a124d94281a75402651455964d3a96f92` | **Started:** 2026-11-26 | **Release state:** BLOCKED until verified.

**SINGLE CANONICAL VERSION — V8 ONLY (2026-11-26).** This is the sole active Breezze master plan, execution backlog and release-acceptance authority. The obsolete V6/V7 plan files are removed from the working tree, with their historical Git commits preserved for audit. No task, README, CI job, PR description or downstream AI agent may treat an earlier plan's version labels, screenshots, checkmarks, provider choices or target platforms as the current implementation contract. All future changes belong to V8 and its evidence ledger; stage/checkpoint numbers (e.g. V8.2 or V8.4) are revisions **within** V8, not separate product versions.

### Consolidated engineering decisions retained in V8

- Retain the existing Flutter monorepo (`apps/mobile`) with Riverpod and the shared `design_system`, `api_client`, and `audio_contracts` packages. No second app, UI toolkit, client-wide theme or audio controller.
- Use one NestJS/Prisma API; Supabase Auth/Postgres with schema/RLS boundaries; Cloudflare API and media Workers with private R2; Drift/SQLite and a per-account outbox on devices. Do not add redundant Isar/Hive databases or duplicate cloud gateways.
- Four tabs are **Home / New / Library / Search** (New replaces the older Browse label). Retain one persistent global player, queue, Now Playing, and adaptive desktop sidebar/phone tab bar.
- Catalog APIs are for discovery and legally available previews only. Spotify/Deezer/YouTube Music metadata is never a full-track distribution or offline entitlement. Full native audio and downloads require independently authorized licensed assets, territory/time-granted sessions and actual verified delivery bytes.
- Preserve legacy account IDs/data until an explicitly tested migration; validate cross-account isolation, Google/Apple native sign-in configuration, and rights/security/account-transition tests before changing production auth.
- Keep the absolute release, production deployment, downloadable source/artifact and store-publication freeze until every required V8 verification gate and explicit owner approval. Historical CI or implementation source alone is not proof of completion.



## V8 UI Reference Integration — YTMusic-style structure, Breezze identity (2026-11-26)

**Cross-chat handoff — START HERE for any future Breezze design session.** Owner selected [jogeanmcf/ytmusic_clone](https://github.com/jogeanmcf/ytmusic_clone) as the **complete UX structure and section reference** for Breezze V8, supplemented with premium restrained glassmorphism. The reference's GitHub repository has no declared license (as inspected 2026-11-26), and its README explicitly calls its streaming backend unfinished. **Do not copy source, code, artwork, fonts, YouTube Music marks, layout assets, or package setup into Breezze; independently implement equivalent screen hierarchy and interactions in existing Flutter/Riverpod with original Breezze styling.** Do not add GetX, a second app or an independent player.

### Non-negotiable UI and brand behavior
1. The **upper-left brand header morphs on vertical scroll**: expanded Breezze wordmark and brand mark becomes a compact **circular black/neutral badge with the genuine Breezze B-note icon** as its visible face. When user scrolls back up it expands to full Breezze identity. Inspired by the compact YouTube Music header behavior, but every word and graphic is Breezze. At desktop sizes the adaptive navigation/sidebar remains consistent, with no duplicate top-level route.
2. Use the original Breezze symbol/wordmark (assets in `apps/mobile/assets/icons`, `BzBnoteMark`/`BzRibbonLogo`), `BzGlassContainer`, existing design tokens, and accessible contrast. Keep “Breezze” text in headers, settings, nav, player, semantics and any newly added surfaces; no YouTube Music product marks, logos or replacement app identity.
3. Exactly four global destinations in this order: **Home, New, Library, Search**. Reference's three-tab “Start/Explore/Library”, in-page search, and branded YouTube shell are *structural inspiration*, not replacement navigation. Preserve one global player, queue, audio focus handling and mini-player.
4. Responsive Flutter UI: editorial home discovery shelves, selected and sticky mood chips; New/Explore release/chart/genre/mood and official music-video sections; Library shortcuts for downloads, playlists, songs, albums, followed artists (and recent activity when real); Search with query suggestions/history, filters and results across available audio metadata, videos, artists, albums and library. For unsupported live datasets (ranking, upcoming releases) show clear real-world availability states rather than fabricated charts.
5. Every introduced surface has a working interaction: chips trigger scoped searches or real genre fetches; section headers navigate to real existing routes; cards open proper licensed-playback/official-video/catalog detail; profile opens account; search operates over real providers; library sections display account-scoped user data; no empty `onTap` callbacks, decorative “More” links, duplicate player, fake cast/microphone/subscription controls or unimplemented screens.
6. Glassmorphism belongs **only on selected headers, pinned filters, selected hero cards and global mini-player/nav**, respecting existing blur-performance budget, Reduce Motion, high contrast, 48dp touch targets, safe areas, and text scaling. No full-screen heavy blur or overlay that blocks scrolling/taps. Smooth collapse animation is disabled/reduced when OS accessibility requests it.
7. Maintain original Breezze design hierarchy and platform idioms. Apple Music-inspired polish may remain; the requested YTMusic-inspired section architecture is the new UX reference. All source/provider music access stays under V8 lawful rights model.

### File and implementation handoff
- **Primary branch:** `main` (single canonical V8 baseline). PR #83 merged its unified UI; [PR #84](https://github.com/MetroKim/Breezze/pull/84) merged on 2026-11-26 at `6055db1b40b4d3bc0fb20a0eb23ae24fdf4af048`, bringing pinned moods and reference section parity. **Native acceptance and final exact-head CI remain unverified**.
- **Main shell:** `apps/mobile/lib/widgets/bz_shell.dart`; four tabs and shared mini-player remain authoritative.
- **Home:** `apps/mobile/lib/features/home/home_screen.dart`; move to scroll-aware Breezze morphing header using reusable `BzMorphingBrandHeader` widget; mood chips, scrollable personalized/real rails and glass discovery hero.
- **New:** `apps/mobile/lib/features/browse/browse_screen.dart`; real interactions for discovery destinations, genre chips and accessible expandable browse sections; avoid false ranking claims.
- **Library:** `apps/mobile/lib/features/library/library_screen.dart`; functional downloads, playlist, album, artist and saved-song shortcuts; account-owned data.
- **Search:** `apps/mobile/lib/features/search/search_screen.dart`; existing search history, filters, artist/song/video discovery + error handling should remain wired. Do not replace with a display-only screenshot.
- **Design components:** `apps/mobile/lib/widgets/bz_brand_icons.dart`, `apps/mobile/lib/widgets/bz_discovery_spotlight.dart`, and `packages/design_system` glass widgets. Implement new reusable widgets without using reference code/assets.
- **QA:** widget tests for initial expanded/header compact state & scroll reversal, semantic Breezze labels, reduced motion/high contrast, Home mood-chip action, New links and Library shortcuts; exact-commit Flutter analyzer/test/build matrix, then native mobile/desktop visual and accessibility acceptance.

### Work state and acceptance tracking
- **Reference read:** inspected all four reference screens (Home, Explore, Library, Search) and the search results plus trends, chips and genre components; all designs are **independent reimplementation**.
- **Implemented in merged PR #83:** original `BzDiscoverySpotlight`, Home mood searches, unified four-tab shell, real New/Library/Search destinations, original Breezze branded header and common glass renderer. Merge is verified as a Git operation; exact-platform functional acceptance is still open.
- **Integrated on main via merged [PR #83](https://github.com/MetroKim/Breezze/pull/83):** scroll-aware pinned `BzMorphingBrandHeader` in Home and New; original `BzCompactBrandMark` in Library and Search; Home glass spotlight, mood search, actionable New/music-video/artist discovery tiles; New spotlight + live genre/collections; Search optionally opens directly in authorized official-video discovery mode. Uses only Breezze branding/assets and existing Riverpod, catalog sources and native/official player policy. Added scroll reversal, compact marker, action, reduced-motion and tile widget tests. **All remain UNVERIFIED pending current SHA CI/native acceptance.**
- **Next:** validate merged [PR #84](https://github.com/MetroKim/Breezze/pull/84) against the final `main` SHA, repair any test failures, then obtain native/accessibility evidence across Android, iOS, Linux, Windows, macOS and web. Keep the release freeze. Revisit unsupported Cast/mic/artist chart/community playlist paths only after real integrations and rights are established; never render dead buttons.
- **Completion:** V8 UI is not “100% complete” without checked branch CI, native app interactions and accessibility evidence. No release, deployment, public code archive or installer until owner explicitly approves the final verified build.

## V8 UI single-design-system cutover and six-platform acceptance — 2026-11-26

**Owner mandate:** remove duplicate/obsolete *visual implementations*, use the selected YTMusic-style **screen/section layout as an independently recreated UX reference**, and keep Breezze as the only app brand. Preserve and reconnect functionality rather than deleting working state management, authorization, account data, media players or provider APIs. Do not vendor the third-party Flutter repo because its license is unspecified. **No “100% finished” claim unless exact-head CI and native OS acceptance pass.**

### One UI source of truth — enforced in V8 CI
| Responsibility | Sole active implementation | Duplicate/retirement rule |
|---|---|---|
| Top navigation | `apps/mobile/lib/widgets/bz_shell.dart` | Exactly Home / New / Library / Search; no second shell, no new Radio/YTMusic tabs |
| Theme + layout tokens | `packages/design_system/lib/src/bz_theme.dart`, `tokens.dart` | `lib/bz_theme.dart` stays a re-export, not a competing palette |
| Glass rendering | `packages/design_system/lib/src/glass/bz_glass.dart` | **`BzGlassContainer` now delegates to `BzGlass`**, no separate blur/filter renderer; BzGlassBudgetScope in pages and player/tab chrome |
| Main brand | `bz_brand_icons.dart` and `bz_morphing_brand_header.dart` | Upper-left Breezze wordmark collapses to black circular white B-note, not the YouTube Music mark |
| Catalog/detail toolbar | `bz_branded_app_bar.dart` | Secondary/YouTube discovery screens use Breezze logo, secondary provider labels only |
| Source-specific discovery | `features/browse/ytmusic_client_screen.dart` **reachable from New** | Preserve authorized YT metadata, video/account-playlist actions, replace nine old standalone AppBars with shared Breezze toolbar; not a top-level app or duplicate player |
| Home/New sections | `features/home/home_screen.dart` and `features/browse/browse_screen.dart` | Original glass hero, context rails, genuine working mood/genre/catalog/video actions; no copied source or fake charts |
| Saved library and search | `features/library/library_screen.dart`, `features/search/search_screen.dart` | Existing account-safe playlists, albums, follows, downloaded assets, artist and video search, never duplicate ownership or media engines |

**CI prevention:** `tools/check_v8_ui_single_source.py` + 6 tests executed from `.github/workflows/breezze-quality.yml`. Reject extra provider tabs, stale duplicated glass filter, missing original logo, old YouTube-branded provider app bars or a vendored reference UI. `apps/mobile/test/v8_cross_device_layout_test.dart` covers responsive layouts for Android, iOS, Windows, macOS and Linux target themes plus 280dp foldable accessibility; **web requires the independent real Flutter web build/smoke workflow**. Static/widget evidence is not hardware certification.

### Feature / interaction cutover acceptance
- **Home:** real persisted recent plays, follows/favorites and personalized rails where backend source exists; Breezze expanding/collapsing masthead; functional mood searches, new-release and artist routes, official music-video search, actionable original glass hero.
- **New:** live genre filters, backend-checked release/chart/video/concert collection screens, 100% original Breezze chrome, and linked YouTube Music *metadata* companion for public discovery + separately consented linked playlists. Provider names remain for lawful source attribution only.
- **Library:** playlists, albums, followed artists, favorites, downloads, pin and edit workflows should stay backed by existing account-scoped stores; no duplicate data stack.
- **Search:** real catalog/typeahead/history, songs/artists and official video scope, library and explicitly user-selected device audio; original Breezze header, disabled unsupported requests with explanation.
- **Player:** exactly one native audio controller and Now Playing and official visible YouTube video route; no illegal audio extraction or ungranted offline claims.
- **Responsive:** test widths 280, 320, 390, 768, 1024 and 1280 logical pixels; iOS/Android safe areas, large Dynamic Type, high contrast/Reduce Motion, Windows/macOS/Linux keyboard and hover, web loading and history. Keep current six-target build workflows; native OS emulator/hardware controls, screenshots and distribution signing are **NOT YET VERIFIED**.
- **Release:** remains blocked until *all* V8 quality, rights, auth, security, true native interactions and platform packaging gates pass and owner explicitly approves. No new production deployment.

**Working implementation:** [PR #83](https://github.com/MetroKim/Breezze/pull/83) merged the main UI cutover; [PR #84](https://github.com/MetroKim/Breezze/pull/84) implements reference-specific interaction parity. Separate [PR #82](https://github.com/MetroKim/Breezze/pull/82) retires older V6/V7 master plan files and must be reconciled without restoring old designs. Historical source archives are not permission to reintroduce retired UI; do not confuse merged source with exact-head test evidence.

### V8 unified four-tab header and detail cutover checkpoint (2026-11-26)

- **All four pages** now reference the **same** `BzMorphingBrandHeader`: Home and New use pinned scrollable slivers; Library and Search use a shared header over their existing real, account-scoped content through `NestedScrollView`. Old static round badges in Library/Search headers were retired, and existing search/filter/library actions remain connected.
- A true desktop **`BzSidebarBrandOwner` inherited scope** controls whether the wordmark is shown in page chrome, so desktop sidebar + content never show two Breezze logos. Standalone pushed pages are outside that scope and retain their own identity. On compact screens the wordmark collapses into an original circular B-note on scroll.
- A single `BzBrandedAppBar` replaces legacy Material `AppBar` variants in YouTube Music discovery and its nested routes, Browse catalog collections, playlists, song/album details, artist pages, Account, Notifications, and official video player. The Now Playing immersive view retains purpose-built player controls, not an unnecessary toolbar.
- `BzGlass` is the only blur implementation; `BzGlassContainer` delegates as a compatibility facade so existing gameplay/navigation widgets remain functional. One design system + one audio engine; no vendored third-party Flutter clone and no unnecessary fresh app scaffold.
- CI source gate now checks all four page header call sites, absence of duplicate brand marks, one glass engine and absence of legacy detail toolbars; regression fixtures cover these. UI widget tests span target-platform themes and 280dp foldable, and are included in macOS and Windows host jobs, with Linux/Android/web plus iOS build workflows separately configured.
- **Status remains UNVERIFIED FOR FULL NATIVE ACCEPTANCE:** PR #83 source is merged, and PR #84 is merged but remains subject to exact-head CI, true Android/iOS/desktop interactive tests, visual evidence, accessibility and rights validation. Do not merge old UI wholesale or publish any release without these gates. Fix failing tests rather than removing them.

## V8 reference repo screen-parity follow-up (2026-11-26)

**Merged implementation:** [Breezze V8 PR #84](https://github.com/MetroKim/Breezze/pull/84), merged into `main` as `6055db1b40b4d3bc0fb20a0eb23ae24fdf4af048`. This is a continuation of **merged PR #83**, not a new UI framework or duplicate shell. `main` is the canonical V8 baseline, and this PR's source changes are **not certified green** without exact-head CI and native OS acceptance.

### Audited upstream structure and exact Breezze routing contract
| Upstream screen/component | V8 only destination | Implementation and real interaction |
|---|---|---|
| Home masthead with choice-chip bar pinned underneath | Home | Existing `BzMorphingBrandHeader` (expanded Breezze wordmark → compact round B-note) immediately followed by **one** `BzPinnedMoodRail` sliver. Remove duplicate in-body mood chips. Moods navigate to `SearchScreen(initialQuery: '<mood> music')` using live search adapter |
| Upstream session artwork rows and quick songs | Home | Render existing authenticated account-scoped recent/personalized artwork rails **before** the promotional glass spotlight, keeping the playable-source policy. Retain unavailable/loading/error states faithfully, no scraped audio or fabricated recommendations |
| Explore: Releases / Charts / Moods & Genres top-level entries | New | `BrowseScreen` features these **three unique** `BzDiscoveryActionTile` entries at top, each preserving `_openCollection` real provider-backed routes; **exclude** them from the later discovery grid to avoid duplicate visual designs |
| Explore artist/song/video trends | New and its detail screens | Maintain provider-attributed Deezer charts/official YouTube video discovery plus source-specific artist and track details. Show unsupported ranks as unavailable, not algorithmically fabricated numbers |
| Library: downloads, playlist, songs, albums, artists | Library | Account-owned existing `All` collection overview with actual shortcut actions and playlist/saved-song stores, followed artists and downloaded media (only when authorized). No fake subscriptions or dead shortcuts |
| Search: service vs Library, song/video/artist/album filters | Search | Reuse current `Audio / Video / Library / Local` scoped searches and genuine provider+owner result data. No dummy microphone, no duplicate YT Music app identity |
| Provider branding | All screens | Breezze app wordmark and compact circular B-note on content; source names only as data attribution. Native media player and queue are singular |

**Platform and architecture:** same Flutter/Riverpod code across Android, iOS, Linux, Windows, macOS and web; small-width (280–390dp) scrollable controls, large-font targets (48dp), Reduce Motion, contrast, keyboard semantics and desktop sidebar brand ownership. This change does **not** assert running-device, signed distribution or full media catalog rights acceptance.

### Regression checks for handoff
- `apps/mobile/test/bz_pinned_mood_rail_test.dart`: rail stays visible after vertical scroll, navigable horizontally on narrow accessible screens; mood callbacks work.
- `apps/mobile/test/browse_screen_test.dart`: three reference-major categories render exactly once; Moods routes to actual `Focus music` provider query.
- `tools/check_v8_ui_single_source.py` and `tools/test_v8_ui_single_source.py`: refuse missing/duplicated pinned rail or returning duplicate release/chart/mood sections.
- **Next:** review exact-commit GitHub CI on `main` after PR #84 merge, fix failures, check real emulator/system build matrix and compare screenshots for layout parity. Do not call this 100% done.

## V8 OLED Black + Listener Experience Upgrade — 22-point design contract (2026-11-26)

**Owner-approved superseding visual directive:** the Breezze design is always **true-black OLED (#000000), white/silent controls**, original transparent **B-note mark + Breezze** wordmark (not the black app icon tile), artwork-first shelves, provider-backed artists/songs, subtle *real-cover* ambient effects, and one full-player shell. This directive overrides previous red/pink accents, promotional/mockup artwork and circular black brand badges.

**Engineering PR:** [#84](https://github.com/MetroKim/Breezze/pull/84), branch `feat/v8-reference-structure-pinned-moods-20261126`; merged source remains **UNVERIFIED** until exact-head GitHub Actions and OS acceptance. Continue the V8-only architecture; no second UI, brand, audio engine, artist database or media rights workaround.

| # | Requirement | Implementation/evidence and precise remaining acceptance |
|---|---|---|
| 1, 22 | Exact original backgroundless mark and name | `BzBnoteMark` renders `breezze-symbol-white.svg`, which contains exactly the **vector paths inside** `breezze-app-icon.svg` and no opaque outer rectangle. `BzBrandLockup` combines it with Breezze text in auth, onboarding, Home/New and desktop; source tests added. Must visually certify screen captures |
| 2 | Previous / Play-Pause / Next | Existing one `BzTransportControls` and mini-player have wired `controller.previous` / `togglePlayPause` / `next`. Verify each on real native/emulator player |
| 3 | Real songs and artists from providers | Spotify/Deezer real discovery and exact canonical recording IDs are retained; official YouTube video stays in provider-controlled foreground playback. **Production finding 2026-11-26:** live Railway API lacks `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` variable *names*, although `YOUTUBE_DATA_API_KEY` is present; hence the deployed API cannot authenticate its client-credentials Spotify adapter. Deezer metadata/preview remains the keyless fallback. Adding credentials enables metadata, not raw full-track streaming. A verified authorized full-song asset/catalog and territory rights are still required for native player and offline downloads |
| 4 | Full account/profile page + Switch account + Settings | Existing owner-bound profile/sessions/revoke/delete and safe Switch account sign-out remain. **PR #84 adds avatar image selection, downsampling and owner-authenticated `PATCH /users/me/avatar`, stored in private Prisma `User.avatarPngBase64`; profile rehydrates and can remove its picture.** Shared backend PNG validation rejects non-PNG/oversized data; account-swap races are guarded. Migration deployment, device picker acceptance and network smoke are still pending |
| 5 | Playlist 2×2 artwork and custom cross-device covers | Real distinct saved-track 2×2 art remains the default, with uploaded single-image override and restore action. **PR #84 adds owner-scoped `Playlist.coverPngBase64`, authenticated `PATCH /playlists/:id/cover`, strict 224px/256KB PNG thumbnail processing, and offline `PlaylistStore` cover mutation replay/remote hydration.** Source tests cover two devices/tenant isolation; the real PostgreSQL migration and cross-platform file picker have **not yet passed exact-commit CI nor been deployed**. No unapproved public file bucket or music-provider artwork download is used |
| 6 | Artist/photo backgrounds on Explore | `BzDiscoveryActionTile(artworkUrl: ...)` supports restrained black-veiled **real provider artwork**. Featured cards request Deezer releases/charts and a catalog artist image; empty provider results retain dark tile, not fake stock models |
| 7 | Home section diversity and vertical listening feed | Existing source-backed Made for You, Trending, Recently Played, Mix, Favorites artwork rails. V8 adds pinned mood rail and a **vertical Continue listening** section wired to actual player/queue after the horizontal shelves. Additional algorithmic home categories require supported provider/rights inputs and tests |
| 8, 15 | OLED black on all pages, minimal dark UI | Root `MaterialApp` forces `ThemeMode.dark` and `bzDarkTheme` uses `#000000`; Settings reports always-on OLED. Check every modal/sheet/third-party embed for unintended colored surfaces |
| 9 | Silent-white interaction accent | `BzColorsDark.accent` and `accentOnTint` are `#FFFFFF`; navigation and controls consume semantic tokens. Decorative artwork colors must not become interactive-state red/pink |
| 10, 14 | Smooth album-art ambient glow and blurred mesh | Canonical `BzAmbientBackdrop` already draws actual cover-art blur plus two radial soft washes; V8 adds 420ms crossfades and zero-duration Reduce Motion. Performance budget and dynamic artwork tests remain |
| 11 | Subtle Home top ambience + elevated shelves | Home adds a very dark neutral top gradient fading to true black; existing elevated `bzSurface1` cards keep hairline separation. Verify on OLED/high contrast |
| 12 | Full-bleed artwork and looping video | Large artwork exists in `NowPlayingScreen`. **PR #84 adds opt-in local/licensed-video repeat** via native `VideoPlayerController.setLooping`, a **Fit/Fill screen** artwork/video framing control (`BoxFit.contain` vs `BoxFit.cover` on user action), pure-black video background and first-party SVG playback buttons, while official YouTube queue controls remain embedded and source-attributed. Repeat defaults off, pauses for OS lifecycle interruptions; video decoder/loop acceptance on Android, iOS, macOS and web is **NOT YET VERIFIED**. Cross-platform renderer parity remains open, never extract/cache YouTube audiovisual media |
| 13 | Song/video switch mode with quiet SVGs | Now Playing adds **Find video** with first-party SVG, pauses native audio and opens the existing official-video search with the current song/artist query. It does **not** claim an unverified one-tap identical video match; seamless inline player switching remains |
| 16 | Subtle top-bar gradient | Home page top gradient plus **PR #84 scroll-aware neutral gradient** now paint the morphing Breezze masthead. Gradient recedes as the header collapses and is disabled for system high-contrast requests. Exact-device dark/OLED screenshots remain pending |
| 17 | OLED cold-start native splash | Flutter pre-auth frame already uses the official Breezze mark on black. **PR #84 adds `configure_native_splash.py`** to generate an Android vector directly from the original transparent logo paths, OLED `LaunchTheme`/Android 12 system splash and black iOS storyboard with a source-identical transparent mark PNG; `generate_platform_targets.sh` reapplies it after `flutter create`. Idempotence/original-mark tests added, but emulator and device screenshots remain mandatory |
| 18 | Shimmer/skeletons | Existing `BzSkeleton`, `BzSkeletonTrackRow` and `BzSkeletonArtworkGrid` respect Reduced Motion; account/activity/home state placeholders wired |
| 19 | First-use/reset onboarding and mood prompts | Existing authenticated first-use/404 reset detection, regional/genre preference store and onboarding overlay retained. **Revisit music tastes** now opens the existing authenticated country/genre/artist onboarding from the profile page and saves through the established backend preference API. A distinct mood taxonomy/prompt is **not yet persisted separately**; any new backend field needs real schema and API acceptance, not decorative selection |
| 20 | Activity unread/read split + suggested follows | `NotificationsScreen` uses real backend notifications and `markNotificationRead`, clear Unread/Earlier groups, unread white indicator, separators. Suggested artists are fetched from real Deezer artist results keyed to the owner's onboarding interests and Follow uses owner-scoped `FollowedArtistStore`. No fabricated suggestions |
| 21 | Every section fully functional | **NOT COMPLETE.** Requires exact-head Flutter static analysis and widget tests, native desktop/mobile OS and accessibility screenshots, auth/account isolation, full-song rights-granted playback/offline delivery and reliable AutoMix acceptance. Never label source-only code "100%" |

**Explicit retained restrictions:** keep four tabs Home/New/Library/Search, native previous/pause/next and one Now Playing, Supabase authentication, owner-scoped storage, authorized media delivery, emulator/native quality gates and no release or production deployment. No unauthorized use of upstream `ytmusic_clone` source/assets. The earlier generated mockup uses decorative imagery/colors and is **not a screenshot or verification of actual Breezze UI**.

### Live environment audit (2026-11-26, read-only)
- Railway `Breezze API` is healthy with its own Railway Postgres and Redis, last successful API deployment on 2026-11-25 from an earlier `main` commit; `PR #84` is **not deployed**. Backend source config currently uses `main`, has `prisma migrate deploy` predeploy and /health check. GitHub branch passing tests never certifies deployed app.
- The connected Supabase project holds auth/profile-related tables but does **not** contain the NestJS `User`, `Track` and `Playlist` tables; do **not** infer a production SQL mismatch until the runtime `DATABASE_URL` target is verified. No production database schema changes were attempted.
- Railway API variable names include `YOUTUBE_DATA_API_KEY` but not Spotify client credentials. Previously supplied Spotify IDs are not evidence that a secret exists in the **deployed** environment. Never paste secrets into repository or Flutter; use managed runtime secrets only.
- Latest source-only V8 additions require one full CI run at the PR head: Flutter/widget tests across Linux/Windows/macOS, Android/iOS/web builds, native splash generation regression, Prisma generation/migration tests, CodeQL and provider/rights policy. Signed physical-device and licensed 180s+ full-track tests remain open.
 
### V8 OLED acceptance tests
- Widget tests: `bz_brand_lockup_test.dart`, `bz_morphing_brand_header_test.dart`, `bz_playlist_artwork_test.dart`, `playlist_cover_persistence_test.dart`, `test_configure_native_splash.py`; design-system `bz_theme_fallback_test.dart`, `bz_ambient_backdrop_test.dart`; `browse_screen_test.dart` and `home_screen_test.dart` for source-backed navigation.
- CI: `tools/check_v8_ui_single_source.py` + Python unit regression, `flutter analyze`, `flutter test`, and Android debug/release, iOS, macOS, Linux, Windows and Web builds. Distinguish source/compilation from actual device appearance and playback.
- Account acceptance: switch/sign-out session isolation; cloud and offline follows/favorites/cover ownership; do not surface previous owner's activity during a slow network response.
- Native/local video acceptance: explicit loop toggle, no video autoplay on entry, foreground playback only, pause on interrupted/inactive OS lifecycle, true-black player canvas; static UI source guard now blocks reverting to duplicate app bars and non-SVG YouTube queue controls. **Native-device codec evidence not yet collected.**
- **Release remains blocked** pending full native and authorized playback tests.

## Product contract (single source of truth)
- **Four top-level tabs in order:** **Home**, **New** (formerly Browse), **Library**, **Search**; no fifth Radio/Downloads/Settings tab.
- **Home:** listener-scoped history, favorites, follows, personalized shelves with honest source metadata. Do not label algorithmic shelves or charts as official without a real dataset.
- **New:** verified new releases, charts if licensed/attributed data exists, genre and mood discovery, music-video entry points.
- **Library:** saved songs, playlists, albums, followed artists, offline media, and download progress/failure recovery.
- **Search:** songs, artists, lyrics, and genre hubs; keep unplayable catalog results distinguishable from playable recordings.
- **Premium listening UX:** one mini-player, one Now Playing, consistent artwork, animations respecting Reduce Motion, Dynamic Type/text scaling, VoiceOver/TalkBack labels, keyboard/desktop navigation, and a stable back stack.
- **AutoMix:** online *optional* beat-matched transitions for **two authorized, simultaneously playable** audio streams; no provider extraction. A planning-only algorithm is **not** a mixed-audio engine. Fall back to gapless/normal transition if analysis, rights, decoder, or CPU budget is unavailable.
- **Offline:** rights-granted full tracks only. Encrypted, per-user app-private media with lease expiry/revocation, network/Wi-Fi gating, pause/resume/cancel, durable jobs, hash/integrity evidence, user-visible reason and retry; no YouTube/Spotify/Deezer metadata downloads.
- **Calls:** automatically pause during phone/exclusive audio interruptions, *resume after focus returns only if that same interruption paused active playback*, no intervening user pause/stop/track change, and current grant still authorized; **never** auto-resume after unplug/Bluetooth route removal.
- **Credentials:** client only receives public Supabase publishable key; server credentials remain in deployment secret stores or encrypted Supabase Vault with restricted SQL access. Add to `.gitignore`, never copy secrets into Git/issue/CI artifacts/logs or plaintext `public` tables. Inventory names and references, not values. Any exposed key must be revoked/rotated.

## Architecture (keep existing working services)
```
Flutter BreezzeShell (Home/New/Library/Search)
  -> global PlayerController + queue + OS audio_service
  -> PlaybackResolver / session + heartbeat (NestJS API on Railway)
  -> rights decisions (Prisma + Supabase Postgres)
  -> signed media worker (Cloudflare Workers + private R2)
  -> just_audio / ExoPlayer / AVFoundation / media_kit
```
Spotify/Deezer/MusicBrainz = discovery/metadata/previews only where licensed. YouTube Music = officially supported visible video playback. Only verified licensed Breezze assets or an actual authorized partner playback API can supply full-track native bytes. Secrets must **never** flow into the Flutter binary.

## Seven delivery stages (do not mark pass without evidence)

| Stage | Deliverables | Acceptance gate | Status |
|---|---|---|---|
| **1. UX navigation** | Home / New / Library / Search; profile/settings; mini-player; no wrong labels | Flutter widget tests + accessibility labels, iOS and Android smoke | Four shell labels wired; unit test added — CI/native pending |
| **2. Unified engine** | Single controller, rights-gated resolver, queue, signed sources, native focus | Dart unit tests; Android/iOS real decoder; no metadata-only full audio | Call auto-resume wired through player; policy + controller tests added; OS acceptance pending |
| **3. Media authorization & infrastructure** | Territory, rights, verified R2 variant, bounded signed URL, session lifecycle | Postgres/R2 integration, 200/206 bytes, deny expired/missing grants | Backend contract tests previously passed; full licensed catalog **blocked** |
| **4. Online AutoMix** | Pair analysis, dual-stream mix DSP or native verified transition, fallback and toggle | Two real authorized full tracks, seamless audible transition verified | Planning only; not complete |
| **5. Offline & error handling** | Queue/retry, offline leases, encryption, interruption/restart, explicit failure reason | Offline airplane-mode verified, account isolation, expiry/denial | Early rights denial, UI errors, per-asset-version HTTP range guard, backend SHA-256 identity, client SHA-256 integrity check and regression tests committed; **audio files still plaintext in app-private storage**, encryption/DRM and native acceptance pending |
| **6. Native OS + accessibility** | Auto-resume calls, no Bluetooth leak, media buttons, VoiceOver/TalkBack, Linux MPRIS | Emulator + physical device acceptance scripts and actual logs | Call-backend pause/resume race guarded and regression test committed; live `playerctl` transport acceptance script added; actual devices, TalkBack/VoiceOver and desktop keys pending |
| **7. Security, packaging & release** | Ignore credentials, secrets audit/rotation, signed Android/iOS/macOS/Windows/Linux artifacts, current-head CI | CI and CodeQL green, signatures verified, rights evidence, release checklist approved | .gitignore hardened and full-history Gitleaks v3 workflow committed (runner pending); Supabase Vault verified empty; credentials not migrated; signed builds/CI BLOCKED |

## Implementation rules
1. Make one scoped change at a time, with a regression test or exact manual acceptance command.
2. Update this plan and [master issue #27](https://github.com/MetroKim/Breezze/issues/27) with commit hashes and observed CI evidence; never claim PASS because a workflow is queued or code compiled only in theory.
3. Prioritize P0: compile, playback rights, login, media-session safety, secure keys, distribution; then P1: polish, AutoMix and personalizations.
4. Keep all platforms on the same authoritative player. UI cannot bypass backend rights.
5. GitHub release artifacts and source bundles stay unpublished until signed release approval.
6. If a test requires hardware, account credentials, license agreements or signing certificates, explicitly mark **External dependency** and include the exact acceptance checklist; do not fabricate evidence.

## Concrete acceptance matrix
- **Build/CI:** `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, Linux/Web/Android/iOS/Windows packaging jobs and CodeQL on the **same head SHA**.
- **Android/iOS:** signed-in playback with licensed 180+ second file; queue/seek/pause, lock-screen transport, incoming call pause/resume, manual pause during call must not auto-resume, headset/Bluetooth unplug must not auto-resume, OS interruption on/off, force-close recovery.
- **Accessibility:** real VoiceOver/TalkBack focus order, descriptive labels, 200% text, contrast, Reduce Motion and keyboard traversal.
- **Linux:** desktop launch under supported distro, MPRIS D-Bus registration **and transport commands** plus hardware media-key smoke.
- **Offline:** verified media bytes, correct user account isolation, AES authenticated encryption, restarts, Wi-Fi-only, integrity tamper rejection, grant expiry and revocation.
- **Signing:** Android AAB/APK production keystore fingerprints; iOS archive/provisioning; notarization for macOS; Authenticode/MSIX as appropriate on Windows; Linux package signing.
- **Catalog rights:** proof per recording, territory, duration and offline permissions; measured byte delivery; no rights inferred from metadata or R2 object names.

## Credential migration SOP (no secret values in commits)
1. Inventory **names** from Railway/Cloudflare/Google/Supabase and tracked config. Treat historical leaked values as compromised and rotate at origin.
2. Put active runtime secrets in the provider's encrypted environment/secret manager; optionally mirror necessary database-used secrets into Supabase **Vault** (encrypted at rest), with least privilege and a strictly server-side lookup.
3. Keep database catalog of `name, owner_service, vault_secret_id, rotation_at` only; never place decrypted secret values in exposed tables or call Vault from Flutter.
4. Gitignore `.env*`, platform signing files, local config and credentials. Keep sanitized `.env.example` templates, not real values.
5. Acceptance: automated secret scan + manual rotation confirmations, 401/403 fail-closed tests, no key in generated client assets.

## Status at plan creation
- **Known passing:** previous media delivery backend contract workflow [45779621949](https://github.com/MetroKim/Breezze/actions/runs/45779621949), on an older commit.
- **Pending current SHA:** [main CI 45802553236](https://github.com/MetroKim/Breezze/actions/runs/45802553236), [CodeQL 45802553174](https://github.com/MetroKim/Breezze/actions/runs/45802553174); Android/iOS simulator workflows had no pass at creation.
- **Critical blockers:** no verified paid/licensed full-song catalog nor rights to general Spotify/YouTube tracks, no signed distribution credentials/evidence, unverified physical device and VoiceOver/TalkBack acceptance.
- **Privacy note:** repository was public when implementation started; no secrets or production binaries may be committed.

## Follow-on checkpoint — recording identity, interruption sequencing and credential audit

- **Backend asset identity**: `backend/api/src/downloads/downloads.service.ts` now exposes `assetVersion` only when the verified `AAC_256` asset has an actual 64-hex SHA-256, rather than relying on an arbitrary metadata ID. Test: `backend/api/src/downloads/downloads.service.spec.ts`. Commits `a9d3d5e`, `51a715e`.
- **Exact resumption identity**: `packages/api_client/lib/src/downloads_library.dart` binds each resumable fragment to the owner, canonical track, and asset version; unversioned/mismatched fragments restart from byte zero. Parses complete HTTP `Content-Range` rather than a weak prefix; rejects wrong offsets. Computes the final SHA-256 for authenticated digest-bearing assets before writing successful metadata. The app forwards `AuthorizedDownloadGrant.assetVersion` to the client. Tests include valid/mismatched hash, stale fragments, and malformed HTTP 206. Commits `264ac9f`, `42bc29a`, `64002a0`, `5e9e3a6`, `fa77844`, `e2c333f`, `52f5bb2`.
- **Short-call race**: `PlayerController` now awaits the backend's in-flight pause acknowledgement before issuing call-restored resume. Tests cover a delayed pause RPC; this is NOT native telephony acceptance. Commits `6c979f9`, `6426d44`.
- **Linux media acceptance**: `apps/mobile/tool/check_linux_mpris_transport.sh` exercises real D-Bus Pause, Play and PlayPause transitions *with an authorized recording already playing*. Physical media keys, Seek and actual audio output remain unverified. Commit `38bac7e`.
- **Credential history**: `.github/workflows/v8-secret-history-guard.yml` uses Gitleaks v3 with full-history checkout and disables artifacts/comments/summaries. The scan has been **queued**, not proven passing. Every historical finding requires source-side rotation. Commit `b9a5317`.
- **CI status**: all current-run statuses must be observed on the final candidate `main` SHA. GitHub queued/cancelled workflows are **not** build/test passes. The repository remains release-blocked.
- **Outstanding critical requirements**: verified authorized catalog rights, encrypted offline-media-at-rest/approved DRM, executable two-stream online AutoMix rendering, native device/OS accessibility evidence, signed and verified installers, and a successful full current-SHA CI/CodeQL sweep.

## V8 execution ledger — 2026-11-26

| Area | Source evidence | Status |
|---|---|---|
| Four-tab navigation | `main_tab.dart`, `bz_shell.dart`, `breezze_navigation_test.dart`; commits `af75086` / `77762ba` / `c7c9554` | Code committed; Flutter test pending |
| Calls auto-resume | `call_auto_resume_policy.dart`, `JustAudioEngineAdapter`, `PlayerController`; tests `call_auto_resume_policy_test.dart` and `player_controller_test.dart`; through `4092a49` | Code committed; simulated unit tests pending; real telephony pending |
| Offline error handling | `DownloadsController`, `DownloadsScreen`; fail-closed policy and UI errors; commits `f850224`, `69728b2` | Code committed; app/airplane-mode/lease tests pending |
| Secrets | `.gitignore`, [custody record](security/BREEZZE_V8_SECRET_CUSTODY.md); Vault installed with **zero** entries; Gitleaks history scan has succeeded on multiple recent commits | Current source scanning works; real key rotation and selected Vault migration not completed |
| Licensed catalog | Previous backend contract suite passed on old SHA; no verified recording-level distribution/offline contract | **External licensing dependency / blocked** |
| Online AutoMix | `Automix.plan` plus `OnlineAutomixRenderer` equal-power two-deck overlap with authorization/decoder failure tests; actual native/global player connection and pitch-preserving BPM DSP are still missing | **Partially implemented; integration and native evidence blocked** |
| Offline encryption | BZA8 chunked AES-256-GCM audio encryption, per-user device key store and authenticated seek-source are now in mobile/API-client code; partial downloads may still create transient plaintext until sealed | **Implemented in source; native/security acceptance pending** |
| Signed packaging | Release/CI runners, signing keys, stores and hardware acceptance | **Not verified** |

**Next change order:** (A) current-commit Flutter CI; (B) OS/native interruption acceptance; (C) correct offline encryption/DRM and storage migration; (D) real licensed tracks and online dual-player DSP; (E) device accessibility + desktop MPRIS acceptance; (F) production signing and release freeze review. No green release status until all gates pass.


## Continuation checkpoint — 2026-11-26 (V8.1: CI reliability and account isolation)

**No release claim:** a GitHub Actions run is PASS only after completion against the exact release candidate SHA; pending, queued, running or cancelled is never a pass.

- **Navigation contract:** the identity guard now checks the canonical `Home / New / Library / Search` labels. Older guard failed on literal legacy `Browse` assertions; new source-based guard is committed and an earlier pipeline has shown identity guard SUCCESS.
- **Search regression:** `search_typeahead_test.dart` previously failed because its global `find.text('Songs')` found two headings across nested routes. The test now searches inside `SpotifyArtistScreen`. The Spotify/Deezer discovery + video isolation workflow `45812828461` returned SUCCESS on this change (`f11eccb`); full quality CI remains separate.
- **Private download jobs:** the previous shared `Downloads/jobs.json` contained one account's song titles/statuses after a different listener signed in. `DownloadJobOwnerDirectory` now derives a fixed owner-hashed private directory; `DownloadsController` clears pending status on auth changes, cancels prior-owner transfers, discards late transfer updates and serializes owner-scoped job writes. Legacy shared job file is removed instead of reassigned. Tests: `download_job_scope_test.dart`, `download_job_account_isolation_test.dart`. These are committed but **Flutter execution must still pass**.
- **CI scheduling:** `.github/workflows/ci.yml`, `breezze-quality.yml`, `codeql.yml`, and `v8-secret-history-guard.yml` use `cancel-in-progress: false`. This preserves the active build/scan while GitHub retains only the newest pending run on each ref. Do not equate an older successful SHA with validation of current main.
- **Security scan:** V8 secret-history guard `45813467262` completed SUCCESS on `7e53d6f`; it is not proof that historical leaked provider keys have been revoked or replaced.
- **Backend deployment drift:** Railway production's latest verified successful Breezze API deployment is commit `13b6c9e7` (2026-11-25), behind the current V8 main. Connected Supabase `djwvyjtebmsavhcrmhxf` lacks Prisma catalog tables `Track` and `AudioAssetVariant`. Preserve the current Railway `DATABASE_URL` until the authoritative DB and migration process are established; **never** direct production to an empty Supabase catalog.
- **Outstanding P0:** exact current-SHA Flutter/Windows/macOS/iOS/Android/Linux/Web CI and CodeQL; physical and simulator media-session/accessibility evidence; verified rights-cleared full-track catalog and offline grants; qualified online dual-source AutoMix; release-only signing certificates/keys and reproducible signed installers. Provider metadata alone cannot close rights gates.

See the same-sha evidence links and outstanding blockers in [master issue #27](https://github.com/MetroKim/Breezze/issues/27).

## V8.2 checkpoint — CI diagnostics and real two-deck renderer (2026-11-26)

**Latest source changes before this document:** `0596004b0f330d3596139d8470fff467039b74b1`.

- **Confirmed CI root causes:** older Linux build job `139886845648` stopped on Clang treating old `flutter_secure_storage_linux` nlohmann JSON literal operator warnings as errors; Linux compatibility job `139886915162` failed startup because `media_kit` could not locate `libmpv`. Another Linux build failed because older Clang 14 does not recognize `-Wno-error=deprecated-literal-operator`. Fixes: narrowly scope plugin-only diagnostic to **Clang 19+** (`apps/mobile/linux/CMakeLists.txt`) and install `libmpv-dev` for Linux build and compatibility test images.
- **Confirmed Flutter failure:** old Flutter test job `139886846026` failed four tests when `DownloadsController` wrote to `downloadJobStatusProvider` during Riverpod provider initialization. Fixed by removing that initialization-time cross-provider write, deferring account-switch notification until a microtask, and updating corresponding test timing.
- **Online AutoMix renderer added:** `packages/audio_contracts/lib/src/online_automix_renderer.dart` drives genuinely simultaneous independent decks through a bounded equal-power overlap; checks authorization at every step; stops both when rights/focus disappear; restores outgoing only if rights remain valid on decoder failure. Unit tests in `online_automix_renderer_test.dart`. **Still not wired to the active global PlayerController/just_audio dual-deck lifecycle**, and no native pitch-preserving tempo stretch. Never mark user-facing AutoMix PASS from the isolated unit tests.
- **Offline audio protection:** `BreezzeOfflineAudioCipher`, `secureDownloadsLibrary`, `BreezzeEncryptedOfflineAudioSource` now implement chunked authenticated AES-256-GCM media, device-held per-user keys, and seekable memory-only decryption. **Transient plaintext during initial download** and real-device decoder/keystore/call-interruption acceptance still need separate review; DRM/rights are distinct from AES.
- **Railway production:** all four services (Breezze API, catalog metadata, Redis, Postgres) reported online with no active failures. However API's last successful production deployment was **older** than V8. Railway has an **unapplied staged change** containing `YOUTUBE_DATA_API_KEY` and an API service config update; do **not** apply that patch automatically or conflate it with a verified V8 deployment.
- **Security:** Gitleaks history scan `45816216814` completed SUCCESS on `0596004b0`. This cannot revoke previously exposed provider keys and does not show a licensed media catalog.
- **Verification caveat:** CI `45816216878`, CodeQL `45816216664`, and Linux compatibility `45816216959` were **pending** when observed. The original build failures are fixed **in source**, not yet independently certified green on a final SHA. Do not publish signed/release artifacts.
- **External release dependencies:** a valid per-recording streaming/offline license manifest and actual recordings/territories; authorized Android/iOS/Windows/macOS signing identities and stores; physical-device telephone and Bluetooth tests; real TalkBack, VoiceOver and Linux hardware-key evidence. Neither generated synthetic QA audio nor Spotify/YouTube catalog metadata supplies commercial distribution rights.

**V8.2 acceptance priority:** green exact-head CI → native BZA8 decoder + interruption/accessible controls → connect and test authorized dual-deck AutoMix with two playback sessions → licensed catalog inventory and R2 delivery → signed installers + physical-device evidence → explicit release approval.


## V8.3 checkpoint — PR #84 merged, New/Home wiring and CI recovery (2026-11-27)

**Owner instruction:** Continue integrating the full Breezze project on `main`, report each verified change here and in [master issue #27](https://github.com/MetroKim/Breezze/issues/27), preserve the OLED-black / silent-white official Breezze brand, keep the release and production-deployment freeze. Only V8 is authoritative.

### Confirmed GitHub facts (not release certification)

- **UI source merge:** [PR #84](https://github.com/MetroKim/Breezze/pull/84) was explicitly moved from Draft to Ready and merged into `main` as [`6055db1b40b4d3bc0fb20a0eb23ae24fdf4af048`](https://github.com/MetroKim/Breezze/commit/6055db1b40b4d3bc0fb20a0eb23ae24fdf4af048). This was a source merge, **not** an app release, deployment, or native acceptance.
- **Home/New route contract:** `apps/mobile/lib/widgets/bz_shell.dart` still owns exactly four destinations in this order: Home → New (`BrowseScreen`) → Library → Search. The merged Home screen uses the pinned mood rail and the New screen promotes New Releases, Charts, Moods & Activities while excluding duplicate tiles from the remaining discovery grid. This is source inspection, **not** a claim that end-to-end user interaction has passed.
- **PR-head checks:** [CI run 45894645120](https://github.com/MetroKim/Breezze/actions/runs/45894645120) on PR head `5e1f3b93d39dfa04e73994b8b2f4b395fdfa6330` passed the identity, NestJS/Prisma, Windows build and Cloudflare Worker jobs, but **Flutter analysis/tests failed** in job `140167365400`. The immediate failure was `invalid_null_aware_operator` at `apps/mobile/lib/app/playlist_store.dart:353`. macOS/iOS and Linux/Android/web build jobs were still in progress when inspected. Separate PR-head CodeQL, Gitleaks history guard, media delivery verification and web preview smoke finished successful; these do not override the failing full CI job.
- **First repair on main:** [`5e245326375c536303ad8dda35d6555683370479`](https://github.com/MetroKim/Breezze/commit/5e245326375c536303ad8dda35d6555683370479) replaces unnecessary `coverPngBase64?.length` with `coverPngBase64.length` inside an already non-null-guarded playlist-cover validation block. The source-specific analyzer cause is removed; **new main-head analyzer, Flutter tests and builds have not been certified green here**.
- **New live-feed account safety:** [`0585b3448333e54b7beb2a1d8d682ef46e649d76`](https://github.com/MetroKim/Breezze/commit/0585b3448333e54b7beb2a1d8d682ef46e649d76) binds New collection responses to the requesting auth owner, invalidates pending fetches on account changes and refreshes the active collection. The UI hides an old owner's licensed-video listing during the transition. [`e189d3b78aaa5819c300286f40ed21a22dfac6cd`](https://github.com/MetroKim/Breezze/commit/e189d3b78aaa5819c300286f40ed21a22dfac6cd) adds a widget regression for a late account-A response after switching to account B. **Source committed; Flutter widget run/native acceptance pending.**
- **Production separation:** No Railway/Cloudflare/Supabase production cutover, signing or public application release is authorized by this merge/fix. Any production backend remains subject to DB migration reconciliation and previously recorded deployment drift.

### Required next verification and wiring work

1. Observe **completed** GitHub Actions for the final `main` SHA: Flutter analyzer and all unit/widget/integration tests, backend/Prisma, CodeQL, secret guard, both Cloudflare Workers, Android/iOS/macOS/Windows/Linux/Web builds. Repair fresh failures with file/line evidence; never use the successful PR SHA as a substitute for newer `main`.
2. Test Home pinned moods → real scoped search, New release/chart/mood cards → actual provider-backed destinations, Library and Search routes, back stack, OLED/high-contrast text, reduced motion, 280dp/390dp touch layouts, account switching and original Breezze mark across mobile/desktop/web. Where providers return no data, show truthful empty/error states.
3. Validate end-to-end auth → backend catalog → resolver → signed worker → player with **rights-cleared audio objects** and working Postgres migrations; verify denial on missing/expired/territory-mismatched grants and bytes/seek with real 200/206 responses. Existing Spotify/Google credentials or Deezer discovery endpoints are not audio redistribution licenses.
4. Wire and accept the current isolated dual-deck AutoMix renderer in the **one** active player only after explicit authorized-source tests; certify offline ciphertext-at-rest, transient-file handling, account isolation and expiry/revocation on actual devices.
5. Complete Android/iOS interruption and accessibility acceptance, desktop MPRIS/media-key transport, physical-device evidence and signed platform packages. Keep release **BLOCKED** until the owner explicitly authorizes it after all gates.

**Acceptance ledger rule:** A commit or merge means source changed; an individual CI job PASS means only that job passed on its exact SHA; device, licensing, database, media and deployment acceptance must be evidenced independently.

### V8.3 owner correction — transport behavior (2026-11-27)

**Final design decision:** Breezze Now Playing uses **Previous Track / Play-Pause / Next Track** only for its three primary transports, with Shuffle and Repeat remaining secondary options. **No separate rewind or 10-second seek-back button.** Track navigation remains attached to the single global `PlayerController`. This explicitly supersedes the brief rewind experiment and prevents future UI agents from restoring it.

**Main source fixes:** `f83145f2824241f6636a66785512285ddf7d80f0` removes the rewind SVG; `9e1a6079a8e0a209752ea892e1c6c2344f263ab5` removes the rewind transport control; `6fa9c085dc40917ff0685187e2a21064c10343eb` removes the rewind callback from Now Playing; `02c43426a5f4ab1e5ded0e906f8362173032b4c7` replaces the rewind test with checks for independent Previous/Next callbacks and the absence of a rewind button. **Source committed; exact-head widget/CI acceptance still pending.**


## V8 engineering change ledger and media architecture clarification (2026-11-28)

- V8 is the sole canonical plan. Every engineering change must update this document in the same development change set with affected components, rationale, exact code revision or PR reference, test evidence, outstanding blockers and next action. Record proposals as proposed, implementations as implemented, and acceptance as passed only with evidence. Keep issues #27 and #78 as supporting trackers; never use Notion or create competing version plans. Never record secrets.
- Extend the existing unified media resolver, not a second player: evaluate permitted alternative and unofficial provider interfaces, OpenSubsonic-compatible servers, direct audio sources and R2-backed media. Spotify/Deezer/YouTube Music metadata is not a playback grant; official visible YouTube video remains separate. No Audius.
- Proposed ingestion and delivery: artist/distributor uploads, recording/composition rights and royalty records where applicable, FFmpeg source validation and AAC/Opus/FLAC renditions, R2 storage, signed CDN delivery, HLS adaptive quality with range fallback, prebuffering and network recovery. Preserve actual source quality and label upscaling.
- Proposed recommendations: collaborative/content-based signals, follows, skips, completion and audio similarity. Offline: device/account-bound encrypted leases, expiry/revocation and integrity; encryption is not equivalent to commercial DRM.
- Acceptance: full-duration audio, seek, gapless/AutoMix, background and interruption recovery, adaptive network behavior, authorized offline playback, six-platform builds and native acceptance. Public-domain proof is not mainstream catalog acceptance. Provider research is not verified integration. No release, production deployment or premature completion.
- Evidence: issue #78 comment 7235710858 records media acceptance clarification. Main revision 92434089c291d6b64dcd5c8e69b4e4e384cc56d0 introduces opt-in nonproduction public-domain playback pathway; actual native acceptance remains open. Historical credential scan run 46006076944 failed; classify findings and remediate genuine exposures without weakening the scanner. Alternative provider integration and commercial catalog availability remain unverified.
