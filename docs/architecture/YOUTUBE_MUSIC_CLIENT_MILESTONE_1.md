# Breezze — YouTube Music companion client, milestone 1

**Scope:** An embedded **public-catalog companion** inside Breezze's existing **Browse** tab. This does not replace Breezze's Supabase sign-in, Deezer previews, licensed asset handling, single global player, or four-tab shell.

## Implemented on main

- **Browse → YouTube Music** opens `apps/mobile/lib/features/browse/ytmusic_client_screen.dart`.
- Uses existing authenticated Breezze API client and existing Python `ytmusicapi` sidecar; no second API gateway.
- Displays data from `ytMusicExplore()`: new releases, trending songs, and official music videos.
- Displays `ytMusicMoods()` and drills into `ytMusicMoodPlaylists()`, then `ytMusicPlaylist()`; albums open `ytMusicAlbum()`.
- Playback actions open the **visible official YouTube player**; no YouTube audio extraction, hidden player, native YouTube audio queue, YouTube downloads or fabricated full-playback entitlement.
- Validates provider result envelope and IDs before opening playlist, album or video content.
- Isolates partial catalog failure; includes empty, loading, retry, and pull-to-refresh states.
- Adds Flutter widget coverage for browsing, album/playlist navigation, invalid IDs, and unavailable-source recovery.

## Next gated milestone: user-authorized account library

`ytmusicapi` supports account-scoped methods such as `get_library_playlists` and `get_library_songs` when authenticated. Breezze must **not** forward its Supabase login/Google social login token as a YouTube Music account token. Before enabling account libraries, implement a dedicated user-approved YouTube OAuth consent flow, server-side encrypted per-user token storage, account-owner binding, refresh/revoke/disconnect behavior, limited scopes, and a privacy/data-deletion contract.

The connected Google Cloud identity, any provider-issued credentials, and user's separate YouTube account authorization are prerequisites. Never collect raw browser cookies or expose authorization credentials in mobile source code, API responses, Redis shared cache or logs. OAuth consent is **not** a third-party native streaming or offline-download grant.

## Verification

- GitHub main commit: `309b08e200a50786e9b0facd38b0f7b933a67c1a` and its predecessors.
- CI: https://github.com/MetroKim/Breezze/actions/runs/45504286144
- Do not call milestone **verified** until Flutter analysis, widget tests and platform builds pass at the same commit. No device/emulator playback acceptance is claimed. The Browser Use research service was unavailable because its project credits were exhausted; public `ytmusicapi` documentation was checked separately.

## Sources

- https://ytmusicapi.readthedocs.io/en/stable/
- https://ytmusicapi.readthedocs.io/en/latest/reference/api/ytmusicapi.mixins.html
- https://developers.google.com/youtube/terms/developer-policies/
