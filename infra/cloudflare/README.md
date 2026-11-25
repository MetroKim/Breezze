# Breezze Cloudflare Edge, Caching and Traffic Architecture

**Status:** Existing API and media Workers and private R2 bucket are provisioned; current production code/credentials and real recording playback still require release-gated verification.  
**Decision:** Cloudflare handles API acceleration and signed private R2 delivery for Breezze-owned or separately licensed media. Approved external providers may still stream directly to Flutter. R2 is never a source of copied YouTube or other unauthorized catalogue media.

**Release gate:** GitHub `main` may be ahead of the live Railway/NestJS and Cloudflare deployments. Run `infra/cloudflare/media-worker`'s `npm test` and `npm run test:http` before staged rollout. The HTTP smoke test exercises an original synthetic AAC tone with local workerd/R2; it is not evidence that any copyrighted catalogue audio is available. See `docs/architecture/MEDIA_DELIVERY_RELEASE_GATES.md`.

## 1. Architecture boundaries

Cloudflare protects and accelerates Breezze's own API. It does not become a proxy for every audio byte and does not replace the NestJS/PostgreSQL application backend.

```text
Flutter clients
   |                                  Approved music providers
   | API / metadata / playback       (provider-hosted audio)
   v                                          ^
Cloudflare DNS + TLS + WAF + rate limits      |
   |                                          | direct HTTPS stream
   v                                          |
Cloudflare API Worker                         |
   |                                          |
   v                                          |
NestJS API ---- Provider Resolver ------------+
   |              | adapters / health /
   |              | timeout / circuit breaker
   |
   +---- PostgreSQL (canonical user + catalog metadata)
   +---- Redis (hot ephemeral cache / BullMQ coordination)
   +---- BullMQ workers (async metadata, sync, analytics)
```

**Audio path:** the API returns a provider-approved, short-lived playable source to the client. The Flutter audio engine connects to that provider directly. Do not route full audio streams through Workers or the NestJS origin unless a provider contract, rights requirement, and measured use case explicitly require it.

**Private media delivery:** the existing `infra/cloudflare/media-worker` serves separately rights-cleared internal AAC/FLAC and MP4 assets from the private `breezze-media` R2 bucket. NestJS authorizes per-track rights, territory and verified asset readiness before signing short-lived delivery grants. Do not use R2 as a generic proxy or re-hosting layer for YouTube or third-party catalog recordings. Artwork may be fetched from its source and cached by the client; public artwork proxying is an optional later decision, not a prerequisite.

## 2. Cloudflare service allocation

| Service | Use in Breezze | Guardrail |
|---|---|---|
| DNS + DNSSEC | Authoritative DNS and domain protection | Enable DNSSEC where supported |
| TLS | Client-to-edge and edge-to-origin encryption | Full (strict) |
| WAF / managed rules | Filter common web attacks and abusive traffic | Tune in log mode before blocking |
| Rate Limiting | Route and identity-aware abuse controls | Separate limits for auth, search, resolve, mutations |
| Workers | Thin API gateway, request normalization, cache policy, edge checks | Stateless; keep domain authorization in NestJS |
| Cache API / CDN cache | Public, non-personalized metadata and static assets | Explicit allowlist; never cache private responses |
| KV | Small, eventually consistent config and selected short-lived data | Not canonical rights/session/playlist storage |
| Queues | Async event fan-out or provider metadata refresh where useful | Idempotent consumers, bounded retries, DLQ |
| Turnstile | Bot signal on selected abuse-prone flows | Validate server-side; not authentication |
| Durable Objects | Only for real-time shared sessions/rooms if required | Do not create one per ordinary listener |
| Observability | Edge logs, traces, metrics and alerts | Redact tokens, URLs and personal data |

PostgreSQL remains the canonical relational store. Redis remains for existing BullMQ and low-latency ephemeral backend needs. Cloudflare KV is not a Redis replacement. Do not add D1 as a second source of truth.

## 3. Cache architecture

Caching is layered. Every cache entry has a defined owner, key, TTL, stale policy and invalidation rule.

### 3.1 Cache layers

1. **Flutter local cache:** recently viewed metadata, artwork, search history, and local library data. Bound disk size and evict least-recently-used entries. Local cache never grants playback rights.
2. **Cloudflare edge cache:** only explicitly public and non-user-specific GET responses, plus immutable static assets.
3. **NestJS/Redis cache:** hot normalized catalog/provider metadata and short-lived provider health/lookup data. Use versioned keys and bounded TTLs.
4. **PostgreSQL:** canonical accounts, ownership, playlists, favorites, library records, rights decisions/audit state, and durable listening data.

### 3.2 Initial cache policy (tune from measured freshness)

| Data class | Suggested initial TTL | Cache rules |
|---|---:|---|
| Hashed app assets / versioned SVG | 1 year | immutable; filename changes on release |
| Public artwork, when safely cacheable | 1–7 days | honor source rights/cache headers; use content/version key |
| Stable artist/album metadata | 15–60 min | public only; stale-while-revalidate |
| Search suggestions | 1–5 min | normalized query + locale + territory + catalog version |
| Public browse/editorial feed | 1–5 min | key includes locale + territory + feed version |
| Search result page | 30–120 sec | key includes normalized query, filters, locale, territory, cursor |
| Provider availability/health | 5–30 sec | short TTL; never treat as rights approval |
| User library, playlists, favorites, profile | no shared edge cache | private; user-scoped server/client cache only |
| Auth/session/refresh | no shared edge cache | private, no-store |
| Playback resolve/grant | no shared edge cache | no-store; short-lived and user/territory scoped |
| Listening event writes | no cache | durable, idempotent ingestion |

These are starting values, not measured guarantees. Provider terms and origin Cache-Control take precedence where applicable.

### 3.3 Cache-key and invalidation rules

- Normalize search input before key creation (Unicode normalization, whitespace normalization, bounded length).
- Include every response-varying dimension: locale, territory, content filter, pagination cursor, schema version and catalog/provider version as applicable.
- Never include bearer tokens or raw secrets in a cache key.
- Never use one shared cache key for authenticated user data.
- Use versioned keys for catalog/feed generations. Prefer version bumps over broad purge storms.
- Use stale-while-revalidate for safe public metadata. Serve stale only within a bounded stale window.
- Use request coalescing/single-flight at the backend for hot cache misses to prevent thundering herds.
- Add TTL jitter to backend cache expiry to avoid synchronized expiration.
- Negative-cache only safe not-found/provider-unavailable results, with very short TTLs. Never negative-cache authorization failures globally.
- Purge by tag or version on editorial/catalog changes. Do not purge all edge cache for a single item update.
- A cache hit must never bypass current rights, territory, account state or revocation checks.

### 3.4 Edge cache eligibility

The Worker should use an explicit route allowlist, not a broad “cache GET” rule. Default everything to pass-through/no-store. Cache only routes whose handler declares public, deterministic, non-personalized output. Set correct Cache-Control/Vary headers at origin and test them at the edge.

## 4. API request flow

1. Flutter sends HTTPS request to the API hostname.
2. Cloudflare applies WAF, bot signals where configured, request-size limits and route-specific rate limits.
3. A thin Worker applies request normalization and the public-cache allowlist.
4. Worker forwards misses/private requests to the protected NestJS origin.
5. NestJS authenticates identity, authorizes the exact resource/action, applies domain rules, then accesses PostgreSQL/Redis.
6. Response returns with explicit cache headers; only eligible public responses enter edge cache.

Keep the origin inaccessible except through the intended Cloudflare path where deployment permits. If private networking is unavailable, require authenticated origin access and strict network controls.

## 5. Provider resolver and fallback behavior

The Provider Resolver is a NestJS domain/application service, not a Cloudflare Worker responsibility.

- Each provider implements a common contract: search, resolve, health, capabilities, attribution and error classification.
- Normalize provider results into canonical Breezze Track metadata; preserve source IDs separately.
- Resolve a track using stable identity signals (provider ID when known, ISRC when available, normalized title/artist/duration as a cautious fallback).
- Apply rights/territory policy before returning a playable source.
- Use bounded timeouts, limited retries with exponential backoff + jitter, per-provider concurrency limits, circuit breakers and health scoring.
- Fallback only to a provider that has the same or a confidently matched recording and is permitted for the user's territory and requested use.
- Do not silently swap to a different recording, live edit, remix or low-quality version.
- Return typed failures: not found, unavailable, rate limited, rights denied, territory blocked, expired URL, unsupported format and provider timeout.
- Never cache signed playback URLs or treat provider health as a rights decision.
- Liner Desktop is **not an approved fallback integration**: its current repository license prohibits commercial use/distribution and reuse of core algorithms, and requires modified builds to use official Liner services only. Do not embed, fork, rebrand, extract its resolver, or depend on its private client behavior for Breezze without explicit written authorization from the rights holder.

The resolver must support multiple independently replaceable provider adapters. A provider outage should degrade discovery or playback cleanly rather than take down auth, library, playlists or the rest of the app.

## 6. One-million-concurrent-user capacity strategy

“One million concurrent users” is a capacity objective, not a Cloudflare checkbox. It must be translated into traffic profiles and proven with staged load tests. One million people streaming from external providers is materially different from one million people repeatedly hitting the Breezze API.

### 6.1 Keep audio off Breezze infrastructure

- Resolve playback through the API, then have the device stream directly from the approved provider.
- Do not relay audio bytes through Cloudflare Workers, NestJS or a Breezze storage bucket by default.
- This removes the largest bandwidth/egress workload from Breezze, but provider capacity, provider quotas, client network quality and rights remain external dependencies.
- If a provider requires proxying, treat it as a separate architecture and cost/risk review.

### 6.2 Keep the API stateless and horizontally scalable

- Run multiple NestJS instances across failure domains behind the Cloudflare-protected origin/load balancer.
- Store durable state in PostgreSQL; keep process memory disposable.
- Use connection pooling (e.g. PgBouncer or managed equivalent), strict DB connection budgets and query timeouts.
- Separate latency-sensitive request paths from background work.
- Apply cursor pagination and bounded response sizes everywhere.
- Avoid N+1 queries; select only required columns; inspect query plans and add indexes based on measured workloads.
- Use read replicas only for read paths with acceptable replication lag. Keep writes and authorization-sensitive reads on the primary/consistent path.
- Partition high-volume append-only listening events by time when actual volume justifies it; define retention and aggregation policies.
- Keep Redis hot keys bounded and monitor memory/eviction. Do not use Redis as durable truth.

### 6.3 Protect provider dependencies

- Per-provider concurrency budgets and request queues.
- Timeouts shorter than the user-facing request budget.
- Circuit breaker opens after measured failure thresholds; half-open probes recover carefully.
- Cache stable metadata, not signed streams or rights grants.
- Apply retry budgets; retries must not amplify an outage.
- Use provider priority and fallback only among approved, rights-compatible sources.
- Return fast, typed degraded responses when every provider is unhealthy.

### 6.4 Control traffic and abuse

- Route-specific Cloudflare rate limits for login, registration, password recovery, search, playback resolution and mutations.
- Combine account/device/IP signals; do not rely on IP alone because mobile carrier NAT can group many legitimate users.
- Enforce per-account playback-resolution budgets and abuse detection in NestJS.
- Use idempotency keys for retryable writes.
- Bound request bodies, pagination sizes, concurrent playback resolutions and expensive search filters.
- Protect expensive endpoints with bot controls and progressive challenges where appropriate.

### 6.5 Asynchronous work

Use BullMQ for non-interactive work such as listening-event aggregation, metadata refresh, recommendations, sync fan-out and cleanup. Consumers must be idempotent, concurrency-limited, observable and protected by bounded retries plus dead-letter handling. Do not put synchronous playback start behind a long-running queue.

### 6.6 Capacity model and test gates

Before launch, record assumptions for:
- concurrent active listeners;
- API requests per active listener per minute;
- search requests per second;
- playback resolutions per second (not per audio segment);
- metadata cache hit ratio;
- provider quota/concurrency per provider;
- DB read/write QPS and connection budget;
- background event ingestion and queue drain rate;
- regional traffic distribution and peak factor.

Run staged tests at 10k, 50k, 100k, 250k, 500k and 1M virtual active clients using realistic think time, cache warmth, cold-cache bursts, provider throttling and regional distribution. Test both steady state and sudden traffic spikes. Record p50/p95/p99 latency, error rate, cache hit ratio, DB saturation, queue age, provider failures, playback resolve/start success and cost per active listener.

Do not claim the one-million target is achieved until the test environment and production-like dependencies demonstrate it. Cloudflare absorbs and caches eligible traffic; origin, database and providers still need independently measured capacity.

## 7. Security and privacy

- Authentication establishes identity; authorization checks access to a specific resource/action.
- Derive user identity from the verified session, never a client-supplied user ID.
- Keep provider/API secrets in server-side secret storage or Worker secret bindings, never Flutter or Git.
- Validate provider playback grants and expiry; never trust client-side rights checks.
- Log correlation IDs and outcomes, not access tokens, passwords, signed URLs, raw search queries or unnecessary personal data.
- Ensure user A cannot read or mutate user B's library, playlists, profile or listening history.
- Turnstile is an abuse signal, not a replacement for authentication.

## 8. Deployment and observability

Separate development, staging and production zones, Worker environments, secrets and origin credentials. Deploy a thin Worker only after tests pass; keep a fast rollback path.

Dashboards and alerts must cover:
- Cloudflare cache hit/miss, WAF actions, rate-limit events, Worker errors and CPU;
- API p50/p95/p99 latency, throughput, error rate and saturation;
- PostgreSQL connections, slow queries, locks, replication lag and pool wait;
- Redis memory, hit rate, evictions and command latency;
- BullMQ queue depth, oldest job age, retries and dead letters;
- provider latency, quota/throttle errors, circuit state and resolution success;
- playback resolve-to-first-audio latency and failure classification.

Use trace/request IDs across Flutter, Cloudflare and NestJS. Redact credentials and personal data.

## 9. Rollout order

1. Protect API origin with DNS, TLS Full (strict), WAF baseline and route-level rate limits.
2. Add thin API Worker and explicit public-cache allowlist; keep private routes pass-through.
3. Implement provider adapter contract, resolver health, timeouts, circuit breakers and typed errors.
4. Add Redis cache-aside/single-flight for safe normalized metadata; define TTLs and invalidation.
5. Add DB pool/query budgets, indexes and read-path optimization from actual query plans.
6. Move non-interactive work to bounded BullMQ consumers.
7. Add regional and spike load tests; tune based on bottleneck evidence.
8. Consider Durable Objects only for a real-time feature that needs coordinated state.

## 10. Explicit non-goals

- No unlicensed R2 ingestion, generic YouTube audio extraction/re-hosting, or public R2 bucket delivery. Private R2 media delivery is supported only for recordings with explicit distribution rights, verified objects and protected grant paths.
- No default audio proxying through Workers or NestJS.
- No wholesale NestJS-to-Workers rewrite.
- No D1/PostgreSQL dual-write architecture.
- No replacing Redis/BullMQ with KV.
- No shared edge caching of private user data, rights decisions or playback grants.
- No claim that Cloudflare alone guarantees one million concurrent listeners.
- No subscription, billing or paywall infrastructure. Breezze remains free.

## 11. Operational acceptance checklist

- [ ] API origin is protected and TLS is Full (strict).
- [ ] WAF rules are tuned against observed false positives.
- [ ] Auth, search, resolve and mutation routes have explicit rate limits.
- [ ] Worker cache is explicit allowlist only; private responses are no-store.
- [ ] Cache keys include all public response-varying dimensions.
- [ ] Metadata cache has TTL jitter, single-flight and invalidation.
- [ ] No signed stream URL or rights grant is shared-cached.
- [ ] Approved provider-hosted audio streams directly where permitted; separately rights-cleared internal audio uses private R2 with signed grants and `no-store` delivery.
- [ ] Provider adapters have timeouts, circuit breakers and concurrency budgets.
- [ ] PostgreSQL pool/query budgets and Redis limits are measured.
- [ ] Queue consumers are idempotent and have bounded retry/DLQ behavior.
- [ ] Cross-user authorization tests pass.
- [ ] Dashboards cover edge, API, DB, Redis, queues and provider health.
- [ ] Staged load tests are complete and results recorded through 1M target.

## Implemented API edge Worker

The repository now contains a separate API gateway Worker at [`api-worker/`](./api-worker/README.md). It forwards requests to the NestJS API and caches only anonymous catalog detail GETs for songs, albums and artists. Authenticated requests, cookies, writes, playback resolution, search, range requests and all unlisted routes bypass edge cache.

Initial edge TTL is 90 seconds with a 30-second stale-while-revalidate window. Cache keys include the full URL/query, Cloudflare visitor country and accepted language. Responses with unsafe `Vary` headers, cookies, non-200 status or private/no-store/no-cache directives bypass cache.

The existing [`media-worker/`](./media-worker/README.md) remains a separate private R2 gateway for Breezze-owned or rights-cleared uploads. It is not the general provider streaming proxy. Signed media responses are `private, no-store`.

**Deployment is not yet performed.** Set `API_ORIGIN` to the private HTTPS NestJS origin, deploy the API Worker, attach the API hostname, configure origin authentication/network restrictions, and create Cloudflare WAF/rate-limit rules before routing production traffic through it. Account-side setup and load testing are still required.

