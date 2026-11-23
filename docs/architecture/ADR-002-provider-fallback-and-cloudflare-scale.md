# ADR-002 — Provider integrations, desktop fallback and edge scale

**Status:** Accepted with legal and provider-verification gates  
**Date:** 2026-11-21  
**Scope:** Breezze provider resolution, desktop fallback policy, Cloudflare traffic handling and credential management

## Context

Breezze needs resilient music discovery and playback resolution, with an engineering target of supporting traffic that may grow beyond one million concurrent active users. The application already defines Cloudflare as its edge layer, NestJS as the domain/API backend, PostgreSQL as durable truth, Redis/BullMQ for ephemeral caching and asynchronous jobs, and direct-to-provider audio delivery.

The requested candidate integrations are:

- `tryliner/desktop`: https://github.com/tryliner/desktop
- `ytmusicapi`: https://github.com/sigma67/ytmusicapi
- MusicAPI: credentials were supplied separately; the exact service, API base URL, endpoint contract and terms have not yet been identified.

## Decisions

### 1. Cloudflare is the edge and traffic-control layer

Use Cloudflare DNS, TLS Full (strict), WAF, bot controls where appropriate, route-specific rate limiting and a thin Worker/API gateway. The Worker must remain stateless and must not own authorization or provider-selection business logic.

Cache only explicitly allowlisted public, deterministic GET responses. Default all unknown routes to pass-through and `Cache-Control: private, no-store` where the response is private or sensitive. Never edge-cache authentication/session data, user libraries, playlists, favorites, listening history, rights decisions, playback grants or signed provider URLs.

Use layered caching:

1. Client: bounded LRU metadata/artwork cache; never treat cached data as playback authorization.
2. Cloudflare: public catalog/browse/search metadata with keys containing all representation dimensions (locale, territory, filters, cursor and schema/catalog version).
3. Redis: hot normalized provider/catalog metadata, provider health and short-lived lookup data; use TTL jitter, single-flight request coalescing and bounded stale-while-revalidate.
4. PostgreSQL: canonical user, library, playlist, rights and durable records.

Keep audio bytes on approved provider infrastructure. The app resolves playback once per playback intent and streams directly from the provider; do not proxy every audio segment through Workers or NestJS. Cloudflare does not remove origin, database or provider capacity constraints.

### 2. Provider resolver is the only provider integration boundary

Implement/retain a NestJS provider-adapter contract with operations for search, metadata lookup, playback resolution (only if the provider actually supports it), health, attribution, capabilities and typed error mapping.

The resolver must enforce:

- rights and territory checks before returning a playable source;
- stable track matching and no silent substitution with a different recording;
- bounded timeouts, retry budgets with exponential backoff and jitter;
- per-provider concurrency limits, circuit breakers and health scoring;
- short-lived playback URLs/grants that are never shared-cached;
- typed errors for not found, unavailable, throttled, rights denied, territory blocked, expired source, unsupported format and timeout.

A provider's availability is not proof of permission to stream its content. Provider terms, licensing and territory restrictions must be reviewed before production playback is enabled.

### 3. Liner Desktop is not an approved Breezze fallback at present

The current `tryliner/desktop` repository license is a source-available, non-commercial license. It prohibits commercial use/deployment/distribution, public competing forks and extraction/reuse of core algorithms and assets without prior express written authorization. Its README also states that the desktop client connects to Liner's own official API backend.

Therefore Breezze must **not** embed, fork, rebrand, redistribute, run as a Breezze service dependency, extract code from, or rely on private client behavior from this repository unless the rights holder first grants written authorization covering the exact intended use and the official-service dependency is acceptable.

Until that authorization exists, the production fallback remains the next independently approved provider adapter, followed by user-owned local audio where supported by the client. A provider outage must degrade playback cleanly; it must not trigger an unauthorized Liner dependency.

If written authorization is obtained, record its scope, term, territory, distribution rights, backend/API rights and permitted code/assets in a separate ADR before implementation.

### 4. ytmusicapi is an optional metadata/discovery adapter, not a guaranteed streaming source

`ytmusicapi` is an MIT-licensed, unofficial Python library that emulates YouTube Music web-client requests and is not supported or endorsed by Google. It may be evaluated behind a server-side adapter for permitted metadata/discovery operations after legal/terms review and resilience testing.

Do not assume it is an official YouTube Music API, a stable playback CDN, or a grant of rights to stream tracks in Breezze. Do not place YouTube/Google cookies or credentials in Flutter, the public repository, logs or client-visible configuration. Treat account-cookie authentication as highly sensitive; production use requires an explicit security and terms review. If its behavior changes or requests are throttled, open the circuit and fall back to another approved source.

Repository: https://github.com/sigma67/ytmusicapi

### 5. MusicAPI integration is blocked on provider identification

The supplied UUID-like values are treated as credentials and are deliberately not recorded here. The exact MusicAPI vendor and API contract are not known from the credentials alone.

Before implementing the adapter, obtain and verify:
- provider's official documentation and API base URL;
- endpoint definitions for search, metadata and playback/stream resolution;
- authentication header format and credential rotation procedure;
- rate limits, concurrency quotas, caching restrictions and attribution requirements;
- content licensing, allowed territories and commercial-use terms;
- response schemas, expiry semantics and error codes.

Store replacement credentials only in the deployment secret manager (GitHub Actions environment secrets and/or Cloudflare Worker secrets as appropriate). Reference them through environment variables such as `MUSIC_API_KEY`; never commit them, put them in app assets, or expose them through a Flutter build. The values pasted into chat must be revoked/rotated before use.

## One-million-active-user engineering gates

“One million concurrent users” is a target, not a guarantee from Cloudflare. Model active sessions, active listeners, API request concurrency, search QPS, playback resolutions/sec, provider quota, cache hit ratio, DB QPS, queue throughput, geography and peak factor separately.

Required controls:
- horizontally scale stateless NestJS instances behind the protected origin;
- protect PostgreSQL with connection pooling, query timeouts, indexes and bounded connection budgets;
- use cursor pagination and bounded payload sizes;
- separate interactive requests from background BullMQ work;
- use idempotent consumers, bounded retries and dead-letter handling;
- avoid retries that amplify provider outages;
- apply route/account/device/IP rate limits without relying on IP alone (mobile carrier NAT);
- instrument Cloudflare, API, PostgreSQL, Redis, queues and provider adapters with correlated request IDs and secret redaction.

Required load-test stages: 10k, 50k, 100k, 250k, 500k and 1M virtual active clients. Include steady-state, traffic spikes, cold-cache bursts, provider 429/5xx, origin degradation and regional distribution. Record p50/p95/p99 latency, error rate, edge hit ratio, origin load, DB pool wait, queue age, provider health, playback resolution/start success and cost per active listener.

Do not claim the one-million target is achieved until production-like staged tests pass and recovery behavior is demonstrated.

## Rollout checklist

- [ ] Rotate the credentials pasted into chat; store replacements only as secrets.
- [ ] Identify MusicAPI vendor and obtain official API/terms documentation.
- [ ] Complete rights/terms review for every provider and territory.
- [ ] Keep Liner disabled unless explicit written authorization is obtained.
- [ ] Implement provider adapters behind the common resolver contract.
- [ ] Verify edge cache allowlist and prove private responses are never shared-cached.
- [ ] Verify origin protection, rate limits, circuit breakers and provider concurrency budgets.
- [ ] Run staged load tests through 1M virtual active clients before making capacity claims.
