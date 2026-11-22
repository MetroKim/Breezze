# Breezze Provider Integration Decision

**Status:** Approved architecture; provider credentials and legal/operational verification still required  
**Scope:** Catalog discovery, provider matching, playback resolution and failover  
**Non-goal:** Hosting or proxying third-party music files

## 1. Decision summary

Breezze uses a provider-neutral resolver behind the NestJS API. No client or screen calls a music source directly. Provider adapters are independently enabled, health-checked and replaceable.

| Role | Candidate | Decision |
|---|---|---|
| Catalog search and cross-service matching | MusicAPI Core | Preferred integration candidate, pending account credentials, plan/rate-limit review and terms review |
| YouTube Music catalog/search | `ytmusicapi` | Optional adapter for discovery/metadata experiments; unofficial dependency with rate-limit and compatibility risk |
| Playback source | Provider-specific authorized stream resolver | Enable only when the provider permits Breezze's intended playback use and returns a playable source |
| Desktop fallback | Liner Desktop | Not an embeddable or server-side fallback; no code, assets, algorithms or private API behavior may be reused without written authorization |

Audius is the first official third-party playback adapter in the current Breezze implementation. It is deliberately restricted to public, ungated tracks that the official API allows the app to access. This is not a complete commercial music catalog. `ytmusicapi` is an unofficial YouTube Music client API and is metadata/discovery only; it does not provide Breezze with a streaming licence. MusicAPI Core remains an optional future catalog candidate and is not connected.

## 2. Liner Desktop restriction

Reference: https://github.com/tryliner/desktop

Liner Desktop is a desktop application that connects to Liner's own backend. Its current Source-Available & Non-Commercial Contribution License restricts commercial deployment, public competing forks, extraction/reuse of core algorithms and assets, and modified builds to the official Liner services.

Therefore Breezze must not:
- embed or bundle Liner Desktop as a fallback player;
- fork, rebrand, redistribute or deploy it as a Breezze component;
- extract its resolver, signer, audio processing, lyrics synchronization, shaders, assets or distinctive UI;
- depend on private Liner endpoints or credentials.

A separate Breezze-native fallback is implemented through the provider adapter contract. Liner may be evaluated as a standalone third-party desktop product by a human, but it is not a Breezze runtime dependency. Revisit only if the rights holder grants explicit written permission covering the exact intended use.

## 3. Optional future MusicAPI credentials and UUID semantics\n\nMusicAPI is not connected in the current release. This section is retained only for a future integration after credentials, plan limits and terms are reviewed.

MusicAPI documents these distinct values:
- **Client ID:** identifies the Breezze integration; public catalog routes accept it as a Token credential.
- **Client Secret:** paired with the Client ID; backend-only, never in Flutter, browser bundles, URLs, logs or Git.
- **integrationUserUUID:** identifies one connected MusicAPI user/library. It is not an API key and does not authenticate requests by itself.
- **DevToken:** short-lived ES256 token minted by Breezze's backend for a specific integration user. If used in a client, include the user's UUID as `sub` so it cannot access another connected user's library.

The UUID values supplied during planning must be treated as connected-user identifiers unless MusicAPI confirms otherwise. They must not be placed in a shared provider credential field or used as a substitute for Client ID/Client Secret. Map an integration UUID to the authenticated Breezze account on the server; never accept a caller-supplied UUID as proof of ownership.

Required backend configuration (values supplied through the deployment secret manager, not committed):
- `MUSICAPI_CLIENT_ID`
- `MUSICAPI_CLIENT_SECRET`
- `MUSICAPI_BASE_URL=https://api.musicapi.com`

Use the public Client ID only for supported public catalog calls. Use Basic authentication with Client ID + Client Secret only from the backend for routes that require it. If user-library routes are added, mint short-lived, user-scoped DevTokens server-side and bind them to the correct `sub`.

## 4. YouTube Music adapter boundary

Reference: https://github.com/sigma67/ytmusicapi

- Isolate `ytmusicapi` behind a dedicated adapter/service boundary. Do not import provider DTOs into domain entities.
- If the Python package is used, run it as a small separately deployable Python service rather than spawning Python for each NestJS request.
- Apply strict timeouts, bounded concurrency, per-provider rate budgets, response validation and circuit breakers.
- Cache only public metadata/search results with normalized query, locale, territory and schema version in the key.
- Do not cache cookies, account headers, signed URLs, authorization decisions or user-specific library responses in shared edge cache.
- Treat throttling, consent changes, endpoint changes and provider blocks as normal failure modes.
- Keep it disabled by default until a deployment has a valid provider configuration and an approved usage/rights review.
- Do not scrape, download, rehost or relay audio as a workaround for unavailable playback rights.

## 5. Resolver contract and failover

Each adapter implements the existing Breezze provider contract and declares capabilities independently:
- search;
- metadata;
- availability;
- playback;
- download.

A provider with `playback: false` may contribute metadata/search results but must never be selected for playback.

For a playback request:
1. Authenticate the Breezze user.
2. Load the canonical track and territory.
3. Ask the rights service for the requested action.
4. Select only providers whose playback capability is enabled and whose terms/rights permit the use.
5. Match the same recording using provider ID, ISRC where available, and conservative title/artist/duration matching.
6. Resolve a short-lived provider-hosted URL; return it to the device.
7. The Flutter audio engine streams directly from the provider host.
8. If resolution fails, try the next eligible provider only when the recording match and rights decision remain valid.

Never silently substitute a remix, live version, cover, different master or unrelated recording. Never treat a metadata search result, provider health check or MusicAPI match as a rights grant.

Classify errors as `NOT_FOUND`, `RATE_LIMITED`, `UNAVAILABLE`, `TIMEOUT`, `RIGHTS_DENIED`, `TERRITORY_DENIED`, `URL_EXPIRED` and `UNSUPPORTED_FORMAT`. Retry only transient errors, with exponential backoff, jitter and a global retry budget.

## 6. One-million-active-listener traffic design

Cloudflare handles the edge perimeter and eligible public API cache; it does not carry the audio payload by default.

- Cloudflare DNS/TLS, WAF, bot controls and route-specific rate limits protect the API.
- A thin Worker applies request normalization and an explicit public GET cache allowlist.
- Public cache keys include normalized query, locale, territory, filters, cursor and schema/catalog version.
- Public metadata uses bounded TTLs and stale-while-revalidate; backend cache misses use single-flight request coalescing and TTL jitter.
- User profiles, playlists, favorites, library data, auth/session data, rights decisions and playback grants are private/no-store and never shared-cache.
- Playback resolution is one small API request per playback intent, not one request per audio segment.
- Audio flows directly from the approved provider to the Flutter audio engine.
- NestJS stays stateless and horizontally scalable; PostgreSQL is durable truth; Redis is bounded ephemeral cache/queue coordination; BullMQ handles non-interactive work.
- Apply per-provider concurrency budgets, circuit breakers, bounded retries and fail-fast degradation so a provider outage cannot exhaust API capacity.
- Do not claim one million capacity until staged production-like tests reach one million active clients and meet latency, error, cache-hit, database, queue and provider SLOs.

The existing one-million scaling plan remains the detailed load-test and cache-policy reference:
`docs/architecture/BREEZZE_ONE_MILLION_SCALING_PLAN.md`.

## 7. Rollout gates

- [ ] Confirm MusicAPI account Client ID and Client Secret exist; store only in deployment secrets.
- [ ] Confirm the supplied UUIDs are MusicAPI integration-user UUIDs and identify which Breezze account (if any) each belongs to.
- [ ] Review MusicAPI plan, rate limits, service coverage and permitted use.
- [ ] Review YouTube/Google terms and the `ytmusicapi` project's current license/operational risks.
- [ ] Implement and test provider adapters behind the existing registry.
- [ ] Keep playback disabled for any provider without explicit playback capability and rights approval.
- [ ] Verify private responses and playback grants cannot enter Cloudflare or shared Redis caches.
- [ ] Load-test provider throttling, cache stampedes, cold starts, origin failover and the staged one-million target.
