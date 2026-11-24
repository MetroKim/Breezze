# Breezze — YouTube account linking (Milestone 2)

This milestone adds a **user-approved read-only YouTube Data API connection** inside the existing **Browse → YouTube Music** companion screen. It does **not** make an independent Google/YouTube Music streaming service, and it does **not** authorize raw audio, background-only YouTube playback or YouTube media downloads.

## Implemented in GitHub main

- Separate Google authorization-code OAuth flow with **PKCE S256** and 10-minute, one-time, state-hashed, owner-bound server-side flows.
- NestJS `YoutubeAccountModule` exposing:
  - `GET /api/v1/youtube-account/status` — owner-only, no tokens.
  - `POST /api/v1/youtube-account/start` — returns only a Google consent URL and expiry for signed-in Breezze listeners.
  - `GET /api/v1/youtube-account/callback` — Google redirect; no Breezze JWT, Google code, OAuth token, or state rendered to browser HTML.
  - `GET /api/v1/youtube-account/playlists` — first 25 owned YouTube playlists using the supported `playlists.list(mine=true)` Data API.
  - `GET /api/v1/youtube-account/playlists/{playlistId}/items` — up to 50 videos from an owner-verified playlist via `playlistItems.list`; opens the **visible** YouTube player.
  - `DELETE /api/v1/youtube-account/connection` — clears token rows and unfinished link flows even when Google configuration is missing; revokes Google refresh token when possible.
- Separate, server-only AES-256-GCM token storage with per-Breezze-user authenticated associated data. Both access and refresh tokens are ciphertext in Postgres, never in Flutter, JSON responses, JWTs, shared caches or logs.
- Google consent requests only `https://www.googleapis.com/auth/youtube.readonly` for the independent account connection. **Breezze Supabase Google sign-in is not reused.**
- Flutter connects/disconnects through its existing BreezzeApi transport and a user-initiated external Google consent browser. Connected YouTube playlists are browsed in-app without a fifth tab.
- Tests cover consent URL, configuration fail-closed behavior, replay protection, owner isolation, encrypted tokens, playlist validation, invalid video IDs, disconnect and Flutter UI/transport.

## Deployment prerequisites (not configured automatically)

Set these only on the private **NestJS API** environment, never in Flutter, client repo files or Cloudflare public bindings:

| Server variable | Requirement |
| --- | --- |
| `YOUTUBE_ACCOUNT_LINK_ENABLED` | `true` only after Google Console project and consent are configured. Defaults disabled. |
| `YOUTUBE_ACCOUNT_CLIENT_ID` | Dedicated Google **Web application** OAuth client ID. |
| `YOUTUBE_ACCOUNT_CLIENT_SECRET` | Corresponding server-side OAuth client secret. |
| `YOUTUBE_ACCOUNT_REDIRECT_URI` | HTTPS callback endpoint that **exactly** matches an authorized Google OAuth redirect, e.g. the secure Breezze API edge domain + `/api/v1/youtube-account/callback`. |
| `YOUTUBE_ACCOUNT_TOKEN_KEY` | A distinct, securely generated base64-encoded **32-byte** AES-GCM key, retained in secret management and backed up appropriately. |

On Google Cloud, enable **YouTube Data API v3**, configure the OAuth consent screen, authorized domains and exactly matched redirect URI, request `youtube.readonly`, verify the project/privacy policy as required, and publish only after consent verification. The app must provide a deletion/disconnect and privacy policy describing token storage. No credentials or user consent have been supplied, so this feature remains **disabled in production**.

## Explicit functional limitations

1. The official YouTube Data API playlist list is **not the same as the complete private YouTube Music library** (e.g., all liked songs, albums, history, uploaded music or personalized recommendations). Separate upstream access and product validation would be needed for those capabilities.
2. Playlists are displayed as read-only snapshots; only the first 25 playlists and first 50 videos per playlist are returned. The responses explicitly mark when additional pages exist, rather than suggesting a complete library.
3. A Google account without an accessible YouTube channel cannot be linked through the channel-bound implementation. It fails closed, without inventing an account identity.
4. Account-linked content never enters the Breezze native audio queue or download manager. Songs/videos open the visible official YouTube player, consistent with platform restrictions.
5. Account consent is not native full-song playback or offline-download permission. The previous Deezer preview and Breezze-licensed media paths remain unchanged.

## Verification gates

- `prisma migrate deploy` on CI PostgreSQL; NestJS typecheck; Jest authorization/security tests.
- Flutter analysis, API contract and widget tests on the exact commit; target platform builds.
- In a dedicated non-production environment after Google Cloud credentials are configured: run real user consent → own-channel verification → own playlist listing → item opening → account disconnect → verify Google and local revocation; test expired token refresh and cross-user isolation.
- Manual privacy/security review, Google OAuth verification and consent checks **before** any production enablement.
- Do not mark full acceptance passed merely because mocked OAuth tests pass.

Sources:
- https://developers.google.com/identity/protocols/oauth2/web-server
- https://developers.google.com/youtube/v3/docs/playlists/list
- https://developers.google.com/youtube/v3/docs/playlistItems/list
- https://developers.google.com/youtube/terms/developer-policies
- https://ytmusicapi.readthedocs.io/en/stable/
