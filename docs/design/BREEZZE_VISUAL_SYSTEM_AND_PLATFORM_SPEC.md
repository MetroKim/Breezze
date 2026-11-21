# Breezze Visual System & Cross-Platform Interface Specification

Status: frontend implementation contract  
Product: Breezze listener application  
UI technology: Flutter / Dart, one shared application codebase

## Product boundaries

Breezze is a free, listener-first music experience. It has no subscriptions, paywalls, artist portal, artist upload tools, distributor workflows, or purchase flows. Artist records remain catalog metadata for discovery, credits and discography only. Downloads are a listener feature and remain inside Library.

The five primary destinations are Home, Browse, Radio, Library and Search. Downloads is a Library destination. Account, profile, preferences, help and support are reached from the profile/settings surfaces.

Apple Music and BitChord are interaction and visual references only. Breezze uses independently implemented Flutter widgets, its own design tokens, original SVG icons, its own navigation and its own brand assets. No Apple proprietary code/assets or BitChord GPL source/assets are copied.

## Visual language

- Brand: Breezze wordmark and B-note mark.
- Accent: Breezze red, used for active navigation, primary actions and selected states.
- Content surfaces: calm neutral light/dark surfaces; artwork supplies the colour and emotion.
- Glass: restrained frosted material for floating navigation, mini-player, playback controls, sheets and contextual overlays. Never put every content card behind blur.
- Player: artwork-led atmosphere, high-contrast readable controls, soft edge lighting and a translucent control layer.
- Typography: shared Breezze type scale; support operating-system text scaling.
- Geometry: shared spacing, radius and motion tokens. No one-off arbitrary values for common components.
- Icons: original, consistent SVG line icons with optical alignment and semantic labels. No emoji, platform icon-font mixtures or decorative placeholder glyphs.
- Motion: short, purposeful transitions; reduced-motion preference disables shimmer, breathing artwork and nonessential transitions.
- Themes: light, dark and system-following modes. Increased contrast and reduced transparency must retain readable solid-surface fallbacks.

## Responsive system

| Window width | Navigation | Content layout | Input model |
|---|---|---|---|
| Compact, under 600 px | Five-item bottom bar | Single column; horizontal artwork rails | Touch, gestures, keyboard when present |
| Medium, 600–839 px | Bottom bar unless tablet layout is explicitly selected | Two-column cards where space permits | Touch, stylus, keyboard |
| Expanded, 840–1199 px | Persistent left navigation | Adaptive two-column content and wider player | Touch, mouse, keyboard |
| Wide, 1200–1599 px | Left navigation | Multi-column discovery, centered max-width content | Mouse, keyboard, touch |
| Ultra-wide, 1600 px+ | Left navigation | Centered content with bounded reading width; optional secondary queue pane | Mouse, keyboard |

The current shared shell uses the compact bottom navigation below the expanded breakpoint and a persistent desktop navigation rail at expanded widths. Screen content must not stretch indefinitely on ultra-wide displays.

All pages must handle portrait/landscape, resize while open, safe areas, keyboard insets, narrow desktop windows, high text scale and focus traversal. Desktop controls must have hover, focus, pressed and disabled states. Touch targets remain comfortable on mobile.

## Primary navigation and shell

1. Home — Listen Now, recent listening, saved/favourite content and data-backed recommendations.
2. Browse — discovery categories and editorial/catalog destinations.
3. Radio — featured stations, directory, station detail and schedules.
4. Library — playlists, artists, albums, songs, genres, compilations and Downloaded.
5. Search — global catalog search, Your Library scope, recents and suggested destinations.

The mini-player remains available whenever a track is active. It supports artwork, title, artist, progress, previous, play/pause, next, tap-to-expand and swipe-up on touch. Desktop places the mini-player in the content footer rather than forcing a mobile bottom bar.

Press-and-hold slide navigation is an optional shortcut, never the only way to navigate. Desktop must provide ordinary click and keyboard access.

## Screen and subsection inventory

### Home / Listen Now
- Compact Breezze header, profile and contextual actions.
- Recently Played.
- Shared With You, shown only when a real share/social source is connected; otherwise an honest onboarding/empty state.
- Personalized mixes and stations, only when backed by real recommendation data.
- Favorites / saved listening.
- Replay and annual listening summaries only when sufficient listening analytics exist.
- Create playlist action, profile, share and overflow menus.
- Row headers expose a clear “See all” action; cards open canonical detail pages.

### Browse
- Latest Songs, New Releases, Trending Songs, Daily Top 100, Coming Soon.
- Music Videos, Charts, Browse by Genre, Moods & Activities, City Charts, Upcoming Concerts.
- Seasonal collections and artist spotlights when editorial data exists.
- Each destination has its own page, filter and empty/error/loading states.
- Search-provider ranking must never be relabeled as official charts, local rankings or editorial recommendations.

### Radio
- Six featured stations in a two-column card grid at the top.
- Full station directory below.
- Station detail with description, verified live status, schedule and related stations.
- Save/share actions.
- A station is playable only after a valid stream is connected to the shared audio engine; metadata alone is not a play action.

### Library
- Playlists, Artists, Albums, Songs, Genres and Compilations; section visibility is editable.
- Downloaded remains a permanently reachable subsection.
- Favorites are a first-class saved collection.
- Playlists support create, rename, delete, play, shuffle, add/remove tracks and reorder where persistence supports it.
- Artist and album pages require canonical catalog IDs and metadata.
- Offline content is account/device scoped and shows real download/lease state.
- No collaboration or cross-device sync claims until supported by the service.

### Search
- Global search field and Service / Your Library scope.
- Recent searches and two-column suggested destinations.
- Search results grouped by verified result type: songs, albums, artists, playlists, videos and events only when the source provides those types.
- Genre, mood, release date, language, explicit-content and credits filters appear only when the source can filter accurately.
- ISRC search may be exposed as an advanced search mode when supported.
- Empty results, loading, offline and provider-error states are distinct.

### Now Playing and Playing Next
- Artwork, title, artist, album context, seek, elapsed/remaining time, previous, play/pause and next.
- Favorite, lyrics, queue, shuffle and repeat controls.
- Playing Next separates queued items from Continue Playing when the engine exposes that distinction.
- Queue supports remove, clear-upcoming and reorder only when those actions are implemented by the queue model.
- Lyrics reload on track changes; stale asynchronous responses must never replace the current track's lyrics.
- Output selection is shown only when the platform can enumerate output devices.
- Karaoke/vocal separation, SharePlay, translation/pronunciation, Autoplay, Automix and spatial controls are capability-gated, not decorative promises.

### Album, playlist, artist and track details
- Album: canonical artwork/metadata, play/shuffle/save/share, tracklist, release details and verified credits.
- Playlist: artwork/title/description, play/shuffle/save/share, tracklist and owner-permitted management.
- Artist: portrait/name, follow state, essential albums/songs, videos, concerts, similar artists and discography when data exists.
- Track rows share a single visual contract: artwork, title, artist, duration, explicit marker, favorite/download state and contextual actions.
- Lossless, Hi-Res, Dolby Atmos, bitrate, sample rate and other format badges appear only when verified by the source and active playback path.

### Profile, Settings, Help and Support
- Profile: display name/photo, public playlist visibility, recently played and listening stats only when those services exist.
- Settings: playback, downloads, storage, data saver, language, display, accessibility, privacy and notification preferences.
- Help: searchable articles, contact support, feedback, issue reporting, terms and privacy.
- No subscription, payment, gift-plan or family-plan UI.

## Reusable component library

- BzSvgIcon: single icon primitive backed by original Breezze SVG paths/assets.
- BzGlassContainer: one controlled translucent surface with a solid reduced-transparency fallback.
- BzSkeleton: shimmer block with reduced-motion support.
- BzSkeletonTrackRow: artwork + text + trailing-action placeholder.
- BzSkeletonArtworkCard and BzSkeletonArtworkGrid: responsive card placeholders.
- Artwork image component: fixed aspect ratios, memory-aware sizing, cached loading, placeholder and error fallback.
- Track row: shared across Search, Browse, Library, playlists and queue.
- Section header: title, optional subtitle and explicit See all action.
- Empty state: concise explanation and a useful next action.
- Error/offline state: actionable retry and clear offline messaging.
- Context menu/action sheet: actions depend on the entity and current permissions.
- Confirm dialog: required for destructive operations.
- Responsive content container: bounded width and consistent horizontal insets.

## Loading and state design

Loading UI must preserve the final content geometry to reduce layout shift:
- Home and Browse rails: artwork-card skeletons.
- Search and track lists: track-row skeletons.
- Radio: station-card grid skeletons.
- Library: collection-specific list/grid skeletons.
- Album/artist/playlist detail: artwork hero plus metadata and track-row skeletons.
- Lyrics: compact line skeletons, then a distinct unavailable state.
- Downloads: progress rows for active jobs and skeleton rows while local inventory is scanned.

Every data surface has explicit loading, loaded, empty, offline, error and stale-cache states where applicable. Never show fake catalog items, fabricated counts, fake friends, fake charts or pretend stream availability.

## Cross-platform capability matrix

Flutter's shared UI code does not make every OS integration universally available. Feature-detect each capability and provide a graceful fallback.

| Platform | Primary UI adaptation | Native integrations requiring platform support |
|---|---|---|
| Android phones/tablets | Bottom navigation on phones; rail/sidebar on large screens; system back handling | Background playback notification, lock-screen controls, Android Auto, widgets, media session, share sheet |
| iOS/iPadOS | Bottom navigation on phones; adaptive sidebar/split view on iPad | AVAudioSession, lock-screen/Control Center, AirPlay, SharePlay, CarPlay, widgets, Siri/App Intents |
| macOS | Sidebar, resizable window, keyboard shortcuts, queue pane | Media keys, system share, AirPlay and native window/menu integration |
| Windows | Sidebar, keyboard/mouse focus, resizable layouts | System media transport controls, notifications, share/open-with integrations |
| Linux | Sidebar, keyboard/mouse focus, resizable layouts | MPRIS, desktop notifications and portal-based file/share integrations where supported by packaging/runtime |
| Web | Responsive sidebar, browser keyboard shortcuts, bottom mini-player where useful | Browser media session, browser autoplay restrictions, downloads and share APIs subject to browser support |
| Android TV / Google TV | Remote-first focus navigation, large typography and horizontal rails | TV launcher, remote media controls and voice search |
| Wear OS / watchOS | Companion remote UI, small-screen now-playing and simplified lyrics | Separate companion app, watch connectivity and background execution |
| Car systems | Reduced-distraction Now Playing and voice-first actions | CarPlay / Android Auto entitlements, certification and platform-specific UI templates |
| Smart speakers | No assumption of a touch UI | Vendor SDKs, casting protocols and device discovery |
| VR / AR | Optional immersive playback surface | Separate rendering/input capability and platform-specific runtime |

CarPlay, Android Auto, watch apps, TV apps, smart speakers, widgets, lock-screen/live activities, browser extensions and VR/AR are separate platform deliverables—not automatic consequences of a shared Flutter widget tree.

## Accessibility and quality bar

- Screen-reader labels and semantic grouping for every control.
- Keyboard focus order and visible focus states on desktop/web.
- Dynamic text scaling without clipping or hidden actions.
- Increased contrast and reduced transparency support.
- Reduced motion disables nonessential animation and shimmer.
- Touch targets sized for mobile use; pointer hover does not replace click.
- RTL layout and localized strings must be supported by layout primitives.
- All visible actions have a real handler or are clearly disabled with an explanation.
- Light/dark/system themes are reviewed at compact, tablet and desktop widths.

## Definition of frontend completion

The frontend phase is complete only after:
1. All five destinations and their core subsections have a designed route or an intentional capability-gated state.
2. Album, artist, playlist, track, radio-station, profile and settings surfaces have coherent layouts.
3. The same components are reused across platforms and content types.
4. Mobile, tablet, desktop, Linux and web layouts adapt without overflow.
5. Every SVG icon is present, semantically labeled and visually consistent.
6. Skeleton, empty, offline, error and success states are implemented for the core data surfaces.
7. Light/dark, text scaling, keyboard focus and reduced-motion states are reviewed.
8. Flutter format, analyze, widget tests and platform builds pass.
9. Backend work does not begin until this frontend checklist is reviewed and approved.


## Complete 1–50 catalog coverage and release status

This status map preserves the full supplied catalogue while distinguishing real frontend behaviour from capabilities that need native services, catalog rights or backend contracts.

| # | Catalogue area | Breezze frontend status |
|---:|---|---|
| 1 | Five-tab navigation and press/hold slide | Implemented: five destinations; tap navigation is primary, press/hold remains a shortcut. Desktop uses the adaptive rail. |
| 2 | Home / Listen Now | Implemented: recent listening, favorites, create playlist, profile/account and honest Shared With You, mixes and Replay states. |
| 3 | Browse | Implemented: responsive discovery-card directory and genre search. Verified latest releases, editorial lists, charts, city charts, video, concerts and seasonal feeds are catalog/editorial-source gated. |
| 4 | Radio | Implemented: station directory, featured layout, station detail and schedule. Live playback is gated until real stream URLs use the shared audio engine. |
| 5 | Library | Implemented: Playlists, Artists, Songs, Downloads and section customization. Album, Genre and Compilation collections remain honest empty states until canonical catalog metadata exists. |
| 6 | Search | Implemented: query, Breezze/Your Library scope, recent searches and suggested destinations. Advanced filters are source-contract gated. |
| 7 | Full-screen Now Playing | Implemented: artwork, seek, transport, favorite, lyrics visibility and Playing Next access. |
| 8 | Mini-player | Implemented: artwork, track metadata, progress, previous, play/pause, next, tap-to-expand and touch swipe-up. |
| 9 | Album detail | Layout contract defined; canonical album page waits for provider album IDs, release metadata and complete tracklists. |
| 10 | Playlist detail | Implemented locally: artwork, play/shuffle, rename, delete, add through Search, remove and reorder. Remote share links and collaboration are gated. |
| 11 | Artist detail | Saved-artist view implemented from real locally saved tracks. Full artist profile, portrait, discography, videos and concerts require canonical artist metadata. |
| 12 | Song/search result | Track rows and playback/actions implemented. Explicit markers, duration and source badges are shown only when verified metadata exists. |
| 13 | Song badges and symbols | Original SVG icon set implemented. Explicit, download, favorite, Lossless, Atmos and collaboration badges are conditional on verified state. |
| 14 | Popovers and menus | Core action menus, playlist picker, confirmations and queue sheet implemented. OS share sheet and output selector depend on platform support. |
| 15 | Visual affordances | Shared selected, active, disabled, pressed, focus, add, favorite and navigation treatments defined in the design system. |
| 16 | Platform variations | Adaptive shell implemented for compact and expanded windows. Native platform integrations are tracked separately in the platform matrix. |
| 17 | Widgets | Design scope documented; native home/lock-screen widgets require separate platform targets and extensions. |
| 18 | Account and profile | Account details, display-name editing and session management implemented. Profile photo, bio, public playlists and follower graph await social/profile-media contracts. |
| 19 | Social and sharing | Honest non-connected states are implemented. Friend activity, collaborative playlists, group listening and social sharing are capability-gated. |
| 20 | Settings and preferences | Account, audio quality, download controls, playback capability notes, appearance/accessibility guidance and local search-history clearing are laid out. |
| 21 | Playback controls and states | In-app mini-player, full player and queue are implemented. Lock-screen and system media controls depend on each platform audio session. |
| 22 | Playlist and album management | Local playlist create/rename/delete/add/remove/reorder is implemented. Folders, smart playlists, cover uploads and collaboration require additional data models/services. |
| 23 | Search refinements | Search scope and recents are implemented. Genre, mood, date, language, explicit and credits filters appear only when source filtering is accurate. |
| 24 | Lyrics and karaoke | Lyrics lookup, synced/plain rendering and track-change stale-request protection are implemented. Vocal separation, translation and pronunciation are gated by providers/platforms. |
| 25 | Discovery and recommendations | Genre discovery and category destinations are implemented. Personalized recommendations, editor picks, artist spotlights and release calendars require verified editorial/catalog data. |
| 26 | Playback quality and formats | Quality preferences are present. Lossless, Hi-Res, Atmos, bitrate, sample-rate and spatial indicators require source and active-pipeline verification. |
| 27 | Car and vehicle UI | CarPlay/Android Auto are separate reduced-distraction platform deliverables, not implied by the Flutter mobile layout. |
| 28 | HomePod and smart speakers | Not part of the current UI runtime; requires vendor/casting integrations and device discovery. |
| 29 | Widgets and lock-screen quick actions | System media controls are supported where the audio-service plugin/platform supports them. Widgets, Live Activities and browser extensions are separate deliverables. |
| 30 | Accessibility | Semantic controls, system theme, high-contrast glass fallback and reduced-motion-aware skeleton/player animation are implemented. Full assistive-technology audits remain part of QA. |
| 31 | TV, console, desktop, watch and VR variations | Desktop layout foundation is implemented. TV/console/watch/VR need dedicated focus, input and native target work. |
| 32 | Empty and loading states | Shared skeletons now cover Home, Browse, Search, Radio, Library, Downloads, Account, playlist detail and lyrics loading. Offline/error/empty states are retained. |
| 33 | Additional symbols and badges | SVG vocabulary is present. Quality, live, spatial, group and exclusivity badges remain data/capability-gated. |
| 34 | Expanded popovers and menus | Queue, action menus and playlist picker are implemented. Lyrics actions, output routing, sleep timer and SharePlay require their services. |
| 35 | Visual design and affordances | Breezze tokens, restrained glass, artwork-led player, responsive discovery cards and original SVG icon library are implemented. |
| 36 | Internationalization and region | Layout foundations support RTL and localized text expansion; translations, regional editorial feeds and territory-aware release schedules remain future work. |
| 37 | API and catalog fields | UI consumes current track metadata. Optional fields such as ISRC, explicit, credits, format, license and release state must be added to typed contracts before display. |
| 38 | Playback history and recents | Device-local recent history and Favorites are implemented. Detailed play counts, streaks and long-range analytics require an analytics contract. |
| 39 | Cross-device sync | Account-scoped playlist merge exists. Queue/session continuity and shared device volume require a dedicated playback-session service. |
| 40 | Enhanced audio | No fake spatial, head-tracking, adaptive EQ or bit-perfect controls. Each appears only after a verified engine/platform implementation. |
| 41 | Family and group | Excluded from the current listener MVP; no family plan or paid tier UI. Group listening may be evaluated later as a free social capability. |
| 42 | Offline and download management | Downloads, progress, retry/pause/cancel, storage use, quality preference and rights revalidation are implemented. Advanced prioritization and offline queue rules are future work. |
| 43 | Player themes and visual modes | Light/dark follows system theme. High-contrast and reduced-motion fallbacks are respected. Manual per-app theme controls are not yet exposed. |
| 44 | Notifications and system integration | Background audio and supported lock-screen/media notifications use the audio-service layer. Live Activities and per-platform control-center surfaces need platform targets. |
| 45 | Quick actions | Press/hold tab navigation and core in-app shortcuts exist. Widgets, voice intents and global hotkeys are platform-specific future work. |
| 46 | Seasonal and event features | Destination design is included in Browse; content is gated on editorial feeds and verified event metadata. |
| 47 | QR and deep links | Not exposed until canonical Breezze URLs and routing are implemented. Never generate fake share URLs or QR codes. |
| 48 | User statistics and analytics | Replay summary is displayed only when real data exists. Top artists, streaks, comparisons and weekly/monthly analytics need event aggregation and privacy controls. |
| 49 | Payments and subscriptions | Explicitly excluded: Breezze is free, with no subscriptions, paywalls, upgrade prompts, gift plans or purchase UI. |
| 50 | Help and support | Settings entry points are designed. Real support channels, issue submission and legal URLs must use verified Breezze destinations before being enabled. |

### Release rule

A capability marked *gated* is still part of the interface architecture, but it must not be represented as live or playable until the corresponding data contract, permissions, platform integration and tests exist. This is deliberate product correctness—not a reason to fabricate demo content.
