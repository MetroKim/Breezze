# Breezze Listening Experience — Interface Contract

This document is the implementation contract for the Breezze mobile listening experience. The supplied 16-part feature catalog is the source of truth for screen order, placement, and interaction. Do not silently move destinations, add billing surfaces, or replace requested controls with unrelated features.

## Product rules

- Breezze is free to use. There is no subscription, membership, upgrade, or paywall panel anywhere in the product.
- The app shell has exactly five primary destinations: Home, Browse, Radio, Library, Search.
- Downloads is a Library sub-section. Settings and account actions are opened from the Home profile/menu surface.
- All interface glyphs are SVG. Do not add emoji glyphs, Material icon-font glyphs, or mixed icon packs. Brand wordmarks may remain separate vector artwork.
- Keep the chrome neutral, content-led, compact, and calm. Artwork should carry visual emphasis; controls should remain clear and restrained.
- Do not copy Liner source, assets, shaders, algorithms, or distinctive UI. Its source-available license prohibits extracting its interface design into another product. Breezze uses its own SVGs, tokens, components, and layouts.

## 1. Persistent bottom navigation

| Destination | Position | Required behaviour |
| --- | --- | --- |
| Home | Bottom, first | Opens Listen Now |
| Browse | Bottom, second | Opens discovery |
| Radio | Bottom, third | Opens stations and programs |
| Library | Bottom, fourth | Opens configurable personal collection |
| Search | Bottom, fifth | Opens global search |
| Press-and-hold slide | Bottom bar | Long-press and move horizontally to select another destination |

The active destination uses the Breezze red accent and a light neutral selected surface. The bar remains visible while switching tabs. The mini-player sits directly above it while audio is active.

## 2. Home / Listen Now

Order from top to bottom:

1. Brand and top-right profile/action cluster.
2. Listen Now heading.
3. Recently Played.
4. Shared With You.
5. Personalized mixes/stations.
6. Replay year summary near the bottom.

The top-right cluster reserves profile, share, create-playlist (+), and overflow actions. Profile opens account/profile settings. Playlist creation is local and account-scoped. Shared With You and Replay must display honest empty/building states until their social and listening-analytics services are connected; never fabricate friends, messages, or play counts.

## 3. Browse

Browse is the discovery destination. It must contain sections for Latest Songs, New Releases, Trending Songs, Daily Top 100, Coming Soon, Music Videos, Charts, Browse by Genre, Moods & Activities, City Charts, and Upcoming Concerts. Rows support expansion, item actions, and navigation to detail views.

The current connected discovery source returns track search results, not verified editorial charts, video catalogs, concert listings, or regional chart rankings. Do not label generic search results as official charts or latest releases. These feeds require their own catalog/event providers.

## 4. Radio

- Six featured stations at the top in a fixed two-column grid.
- Full station directory below.
- Station detail contains description, live status, and program schedule.
- Station share and add-to-library actions belong on the detail surface.
- A live-play control must remain disabled until station stream URLs are integrated into the single playback engine. Station metadata must never masquerade as playable audio.

## 5. Library

The configurable section order is Playlists, Artists, Albums, Songs, Genres, Compilations. Downloaded is a separate always-visible Library sub-section. Edit controls visibility of the six collection sections.

- Playlists: create, rename, delete, open, play, shuffle, add tracks, remove tracks, and reorder.
- Artists: saved/followed artists.
- Albums: saved albums.
- Songs: saved tracks.
- Genres: genres represented in saved music.
- Compilations: compilation albums.
- Downloaded: account-scoped offline items and in-progress downloads.

Local playlists are stored per account on the device. Cross-device playlist sync, collaborative editing, and playlist share links require backend support and must not be implied by local storage.

## 6. Search

Search includes a query field, Breezze/Your Library scope switch, recent searches, and a two-column suggested-search grid. Suggested destinations include Latest Songs, New Releases, Trending Songs, Daily Top 100, Coming Soon, Music Videos, Charts, Browse by Genre, Moods & Activities, City Charts, and Concerts.

Current provider results are track-oriented. Track rows support play, download, add to Library, add to Playlist, and contextual actions. Album, artist, video, chart, and concert result types require richer catalog contracts.

## 7. Now Playing

The full-screen player contains artwork, title/artist, seek position, previous/play-pause/next, favorite star, lyrics visibility, and Playing Next. Lyrics must reload when the track changes and stale lyric requests must not overwrite the current track. Queue controls include shuffle, repeat, remove-from-queue, and clear-upcoming.

Output routing, SharePlay, karaoke vocal isolation, lyric translation/pronunciation, volume control, Autoplay recommendations, and Automix must only be enabled when the corresponding platform or backend capability exists.

## 8. Mini-player

The mini-player sits above the bottom tab bar and provides artwork, track title/artist, progress, previous, play/pause, and next. Tap or swipe up expands Now Playing. It remains available across all five destinations while playback is active.

## 9. Album detail

Required placement: large cover and album metadata at top; play/shuffle/add/share/overflow actions near the hero; tracklist below; credits and lyrics from track-level metadata. Track rows support play, favorite, download, queue actions, and badges.

The current track search contract does not yet return album identity, album credits, release metadata, or complete album tracklists. Do not synthesize album pages from unrelated search results.

## 10. Playlist detail

Required placement: playlist artwork, title/description/owner/count, play and shuffle, add/share/overflow actions, then tracklist. Support rename/delete, add/remove, reorder, and download where the rights service permits.

Current implementation supports device-local playlists, play/shuffle, rename/delete, adding tracks from Search, and swipe-to-remove. Collaboration, remote sharing, reorder persistence, and cross-device sync remain backend work.

## 11. Artist detail

Required placement: artist portrait/name/follow/play/share/overflow; Essential Albums; Essential Songs; Music Videos; Upcoming Concerts; Similar Artists; full discography and Singles/EPs.

The current provider does not expose artist IDs, portraits, albums, videos, concert events, or similar-artist relations. These sections must be populated from an authorized artist/catalog provider before they are presented as live data.

## 12. Song row / search result

A track row reserves space for artwork, title, artist, duration, explicit/favorite/download/quality badges, play, add, share, and overflow actions. Only render explicit, Lossless, Dolby Atmos, or duration metadata when the source actually supplies it.

## 13. Song symbols and badges

- Explicit: E badge.
- Favorite: gold star.
- Downloaded: download indicator.
- Add: plus.
- Lossless and Dolby Atmos: only when source metadata and playback capability confirm them.
- Collaboration: people badge only for a real collaborative playlist.

Never display quality or collaboration badges as decoration.

## 14. Menus and popovers

Context menus are attached to the item they affect. They may expose Add to Library, Add to Playlist, Share, Rename, Remove/Delete, and Download according to item type and ownership. Destructive actions require confirmation. Share sheets must use real OS share support and valid Breezze links; do not create fake URLs.

## 15. Interaction and visual affordances

Use consistent SVG icons for plus, overflow, share, play, download, favorite, queue, shuffle, repeat, lyrics, and navigation. Selected/favorite states must visibly change. Row expanders open real content. Every action must have a real handler or be visibly disabled with a reason.

## 16. Platform behaviour

The five-tab mobile shell is the primary mobile layout. Tablet/desktop layouts may adapt to wider space, but preserve the same destinations and hierarchy. Keyboard shortcuts, desktop queue/sidebar, CarPlay, watch controls, AirPlay, and HomePod integration are separate platform capabilities and must be feature-detected rather than drawn as inert controls.

## Current implementation checkpoint

Implemented in the current UI pass:
- Five fixed bottom destinations with press-and-hold slide navigation.
- Original Breezze SVG navigation, action, player, and brand-mark assets.
- Red active-state accent and selected tab surface.
- Mini-player with previous/play-pause/next, progress, tap and swipe-up expansion.
- Home profile/settings entry, create-playlist action, and honest Shared With You / Mixes / Replay states.
- Search scope switch, suggested discovery grid, recent searches, track actions, local favorites, and add-to-playlist.
- Library section selector, visibility editor, account-scoped local playlists, playlist detail, and Downloaded section.
- Radio featured six-station grid, station directory, and schedules.
- Now Playing lyrics toggle, track-change-safe lyrics loading, favorite star state, and Playing Next queue with shuffle/repeat/remove/clear.
- Corrected glass fallback so bold-text accessibility does not disable the visual surface.

Not yet complete because the current connected services/contracts do not supply the required data or platform capability:
- Verified charts, City Charts rankings, editorial new releases/trending, music videos, concerts, and social Shared With You.
- Radio stream playback, artist/album entity metadata and detail routes, artist follows, album credits, collaboration and remote playlist sync.
- Full output routing/SharePlay, karaoke, volume API, lyric translation, Autoplay, Automix, and cross-platform companion controls.
- Full explicit/quality badges and shareable Breezze deep links.

No subscription or premium billing UI is part of the design or roadmap.
