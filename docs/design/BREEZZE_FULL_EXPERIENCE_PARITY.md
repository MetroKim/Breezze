# Breezze — full music-app information architecture and experience acceptance contract

Breezze targets the breadth, navigation quality and polish of a mature music service. These are **original Breezze screens and components**, not copied Apple art, icons, fonts, proprietary motion assets or service endpoints. Feature visibility must correspond to real local/backend/provider data. Design completion is not proof of music licensing.

## Global experience

- **Five primary destinations:** Home, New, Radio, Library, Search. Persistent compact navigation; an adaptive sidebar on tablet/desktop; mini-player never hides actions or navigation.
- **Secondary destinations:** Now Playing, Playing Next, Album, Artist, Song, Playlist, Music Video, Downloads, Account, Settings, Notifications, Support, Onboarding.
- **Content structure:** consistent screen headline, optional account action, summary/featured rail if genuine data exists, track/album grids, empty/loading/error states, contextual menus, responsive safe area and 44pt minimum interactive targets.
- **Player:** persistent across tab changes and account-aware; seek, shuffle, repeat, queues, lyric focus, sleep timer, artwork atmosphere and visible unavailable-source states. No metadata-only media IDs in the native audio queue.
- **Visual system:** Breezze monochrome/SVG mark, dark/light semantic tokens, semantic typography, original vector icons, quiet blur with solid high-contrast fallback, artwork-led color, reduced-motion behavior. No faux content, neon decoration or BitChord/Apple trademark graphics.
- **Platform layouts:** compact phone tabs, tablet navigation/sidebar with constrained reading width, desktop sidebar + floating mini-player, keyboard/focus/large-text and screen-reader support. Maintain iOS, Android, Linux, Windows, macOS and web build checks.

## Feature inventory and evidence status

| Area | User-facing sections | Current source-level state | Still required for product acceptance |
| --- | --- | --- | --- |
| Home | Personalized picks, Recently Played, mixes, Favorites, Replay, account | Real saved history/favorites, personalized home feed when supplied, replay summary, honest empty states | Personalized quality evaluation, social sharing feed, real-device QA |
| New | New Releases, Charts, Daily Top 100, Latest/Trending, Genres, Moods, Music Videos, Concerts, upcoming and editorial | Genre/mood discovery search, provider-supplied releases/charts/videos/concert metadata for supported routes; album/chart details now navigate inside Breezze | Verified feeds for remaining headings, no fake ranking, editorial source, concert regional coverage |
| Radio | Station directory, show schedule | API-backed information and schedule | Licensed station stream resolver, media-session and interruption QA, live indicators from actual stream |
| Library | Playlists, Artists, Albums, Songs, Genres, Compilations, Downloaded | Account-scoped favorites/playlists, artist grouping, save/remove album metadata, verified-source genre grouping and compilation filtering, user section preferences, download library | Full cloud album sync, legacy album metadata backfill, cross-device conflict resolution, offline entitlement validation across devices |
| Search | Song/artist/catalog discovery, search history, Saved Library scope, official Music Videos | Federated song search, local saved-track search, explicit video mode with user query, account-scoped history | Artist/album type tabs; better result grouping and personalized ranking; embedded official video where platform allows |
| Player | Artwork, lyrics, queue, transport, sleep timer | Native transport, synced/plain lyrics, focus mode, artwork, background-media bridge, queue mechanics | Real-device audible QA, resilient URL renewal, platform audio focus, advanced audio formats |
| Social | Share, profiles, collaborative playlists, listening together | Account/profile and basic playlist flows | Collaboration/SharePlay-equivalent, real-time sync, privacy controls |
| Advanced audio | Crossfade, AutoMix, lossless, Dolby Atmos, spatial audio, Sing/duet, AirPlay-style routing | Do **not** infer support from a setting/visual badge | Verified DSP/codec/output path per OS, provider rights, devices and licensed formats |
| Operations | Offline downloads, takedowns, moderation, recommendations | Partial provider/rights and storage pipelines exist | Production source-to-speaker tests, rights auditing, distribution and accessibility acceptance |

## End-to-end acceptance gate for every screen

1. Route is reachable without external navigation for normal metadata and account flows.
2. Screen loads real API/local data, no static content impersonating a chart or catalog.
3. Loading, zero results, offline, denied permission, expired grant and retry states are tested.
4. Actions mutate the correct user/account state and survive app restart; switching accounts never leaks data.
5. Search and UI never enable full-track streaming or downloading merely from metadata.
6. Smaller phones, tablet and desktop do not overflow; high contrast/reduced motion work; interactions have semantic labels.
7. Flutter analysis/tests plus Android/iOS/Linux/macOS/Windows/Web builds all pass.
8. Visual screenshots and actual hardware audio/video verification close the final acceptance gap.

## This implementation slice

- Standardized Home / New / Radio / Library / Search navigation.
- Desktop sidebar now offers Account and Settings.
- Search Songs vs Music Videos is explicit; the video query is no longer hard-coded to one exact phrase.
- Album and chart discovery opens Breezze metadata details rather than auto-handing-off to another music app. Music video results now open a Breezze route with the official YouTube IFrame player on Android/iOS/macOS/web; Windows/Linux present an explicit official watch-page fallback. Upstream embed restrictions remain enforced. The video player is not a licensed native audio stream.
- Albums can be saved from metadata details and removed in Library, keyed to the signed-in owner.
- Library section choices persist by owner.
- Central UI permission guard excludes retired Audius and other discovery-only tracks from native playback/queue/download actions.

**Not a 100% completion certificate.** The sections above remain tracked in the existing master completion issue; this document defines the target and what evidence is needed before making a full-parity claim.


## Release-network and album category hardening

- The generated Android **main** manifest now explicitly requests `android.permission.INTERNET` and `ACCESS_NETWORK_STATE`. Debug-only permissions are not sufficient evidence for the release APK.
- Generated macOS DebugProfile and Release entitlements explicitly enable `com.apple.security.network.client`; existing sandbox entitlement keys are preserved.
- The CI cross-platform build runs `tool/verify_platform_network_permissions.py --android --macos` after generator and compiles an Android **release** APK as well as debug APK.
- iTunes album detail metadata carries `primaryGenreName` and an explicit `isCompilation` boolean; an absent flag does **not** imply compilation.
- Album genres and compilation flags round-trip through account-scoped saved album storage, including default-safe decoding of older saved albums.
- Library Genres displays saved album groups when genuine classification exists; Compilations filters explicitly marked compilations. Empty categories remain honest rather than being populated with fabricated data.
- Existing saved albums may lack these newer fields until re-saved or genuinely re-fetched. These changes do **not** establish music rights, cloud album sync, physical-device audible playback or radio station stream licensing.
