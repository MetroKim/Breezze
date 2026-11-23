# Breezze — One-Million-Active-Listener Scaling Plan

**Status:** Engineering target; not evidence of achieved capacity  
**Primary constraint:** Breezze must not become the audio bandwidth origin. The app resolves approved provider streams and plays them directly on the device.

## 1. Define the target correctly

Track three different quantities:
- **Concurrent active users:** app sessions currently active.
- **Concurrent listeners:** users currently receiving audio from external provider hosts.
- **Breezze API concurrency:** requests currently being processed by Cloudflare/NestJS.

They are not interchangeable. A million open app sessions do not mean a million simultaneous API requests. A million streams should not mean a million audio streams through Breezze servers.

Build capacity from a workload model, not a headline number. Record peak factor, geography, request mix, client retry behavior, provider limits and expected cache hit ratio.

## 2. Reference topology

```text
Flutter clients
  |-- public metadata/search --> Cloudflare edge cache (eligible GET only)
  |                                  |
  |                                  v cache miss
  |                              NestJS API
  |                                  |
  |                         Redis / PostgreSQL
  |
  |-- playback resolve ------> Cloudflare WAF/rate limits -> NestJS Resolver
  |                                                        |
  |                                                        v
  |                                              approved provider adapter
  |                                                        |
  |<---------------- short-lived playable source ----------+
  |
  +---------------- direct HTTPS audio stream ------------> Provider CDN/origin
```

Cloudflare is the perimeter, traffic filter and public-response cache. NestJS owns authentication, authorization, canonical entities, provider selection and rights checks. PostgreSQL is durable truth. Redis is ephemeral acceleration/queue coordination. BullMQ handles non-interactive work.

## 3. Request-path engineering

### Public reads
- Cache only explicitly public and deterministic GET endpoints.
- Key by normalized query + locale + territory + filter + cursor + schema/catalog version.
- Use stale-while-revalidate within a bounded stale window.
- Coalesce simultaneous misses (single-flight) at the origin.
- Add TTL jitter to prevent synchronized expiry.
- Return explicit Cache-Control and Vary headers.
- Keep cache payloads compact and versioned.

### Personalized reads and writes
- Never share-cache profiles, playlists, favorites, private library, listening history, sessions or playback grants.
- Use authenticated user-scoped Redis keys only where measured to help.
- Use ETags/versions for conditional fetches and optimistic writes.
- Require idempotency keys for retried mutations.
- Enforce authorization in NestJS on every protected operation.

### Search
- Normalize and cap query input.
- Debounce on the client; cancel stale requests.
- Cursor paginate and cap page size.
- Cache only public search responses with full key dimensions and short TTL.
- Avoid expensive wildcard scans; use indexes and measured query plans.
- Apply per-account and per-IP/device rate limits without punishing carrier NAT users.

### Playback resolution
- Resolve once per playback intent, not per audio chunk.
- Return a short-lived provider URL/token with format, expiry, seek and attribution capabilities.
- Do not edge-cache the grant.
- Use provider-specific concurrency budgets, timeouts, circuit breakers and retry budgets.
- Refresh expired URLs only when necessary; avoid synchronized refresh storms.
- Fallback only to an approved source that confidently matches the same recording and rights/territory.

## 4. Cache policy

| Object | Starting policy | Notes |
|---|---|---|
| Hashed app assets | 1 year, immutable | Change filename on release |
| Public artwork | 1–7 days if source terms permit | Respect source headers and attribution |
| Artist/album metadata | 15–60 min | Stale-while-revalidate |
| Public feeds/charts | 1–5 min | Include locale/territory/version |
| Search suggestions | 1–5 min | Normalized query key |
| Search results | 30–120 sec | Include query/filter/cursor/locale/territory |
| Provider health | 5–30 sec | Never equals rights approval |
| User-specific data | no shared edge cache | User-scoped only |
| Auth and playback grants | no-store | Sensitive and short-lived |
| Audio stream | provider-managed | Not stored or proxied by Breezze |

Treat TTLs as initial values; tune from freshness requirements and hit/miss telemetry.

## 5. Backend capacity

- Stateless NestJS instances; horizontal scale across failure domains.
- PgBouncer/managed pooler and a strict application-wide connection budget.
- Query timeout, request timeout, response-size and pagination limits.
- Index only from actual query plans; remove N+1 patterns.
- Read replicas for safe stale-tolerant reads, never for authorization-sensitive consistency.
- Partition listening events by time only when measured volume requires it; aggregate asynchronously.
- Redis with bounded memory, key TTLs, eviction monitoring and no durable-truth responsibilities.
- BullMQ consumers have concurrency caps, idempotency, retry budgets and dead-letter queues.
- Keep playback resolution synchronous and fast; move analytics/recommendations/metadata refresh to queues.

## 6. Provider resilience

Each adapter exposes a shared contract and health state. Classify errors into timeout, throttled, unavailable, not found, rights denied, territory denied, expired URL and unsupported format.

Use:
- strict connection and total timeouts;
- per-provider semaphores/concurrency budgets;
- exponential backoff with jitter and a global retry budget;
- circuit breaker with half-open probes;
- provider priority and territory/capability filtering;
- exact/strong recording matching before fallback;
- observability by provider and failure class.

Do not use Liner Desktop as a Breezze fallback without explicit written authorization. Its current license is source-available/non-commercial, prohibits commercial deployment/distribution and extraction of core algorithms, and restricts modified builds to official Liner services. It is a desktop client, not a licensed generic fallback API. Evaluate independently licensed providers instead.

## 7. Cloudflare configuration principles

- WAF and route-specific rate limits in front of the API.
- Thin Worker; do not put core business logic or long-running jobs in it.
- Explicit cache allowlist, default pass-through/no-store.
- Cache key includes every public representation dimension; never token-based shared cache.
- Origin protection and TLS Full (strict).
- Turnstile only as an additional bot signal.
- KV for small, eventually consistent config only.
- Durable Objects only for actual coordinated real-time rooms, not per-user session storage.
- Queues for asynchronous edge-origin events only when they simplify the existing BullMQ design; avoid duplicate queue systems without a clear boundary.

## 8. Load-test programme

Test with production-like topology and provider simulators that reproduce latency, quotas, 429s, 5xx, slow streams and URL expiry.

| Stage | Virtual active clients | Exit criteria |
|---|---:|---|
| 1 | 10,000 | Correctness, no data leakage, baseline latency |
| 2 | 50,000 | Stable cache hit ratio and bounded DB pools |
| 3 | 100,000 | No runaway retries or queue growth |
| 4 | 250,000 | Regional traffic and failover behavior |
| 5 | 500,000 | Provider throttling and origin saturation tested |
| 6 | 1,000,000 | Sustained target plus spike, cold-cache and dependency-failure tests |

For each stage report p50/p95/p99 latency, throughput, 4xx/5xx, edge hit ratio, origin requests, Worker errors/CPU, DB pool wait/locks/slow queries, Redis memory/evictions, queue age, provider latency/429/5xx, playback resolution success, playback start time and cost per active listener.

A stage passes only when service-level objectives are met, no cross-user data leakage occurs, queues drain after the test, and recovery from provider/origin failures is demonstrated. Do not mark the one-million target complete until the final stage passes.

## 9. Rollout sequence

1. Measure current API and database baseline.
2. Add Cloudflare WAF, origin protection and per-route rate limits.
3. Add thin Worker with explicit public cache allowlist.
4. Implement provider resolver adapters, typed failures and circuit breakers.
5. Implement Redis metadata cache, single-flight and invalidation.
6. Fix DB query plans, connection pooling and pagination.
7. Move non-interactive jobs to bounded queues.
8. Run staged tests and tune the measured bottleneck.
9. Repeat tests after major schema, provider or traffic changes.

## 10. Go-live gates

- [ ] Provider integration rights/terms reviewed.
- [ ] No Liner code, client, algorithm or service dependency without written authorization.
- [ ] Audio is direct from approved provider by default.
- [ ] Private data and playback grants are never shared edge-cached.
- [ ] Provider circuit breakers and concurrency budgets tested.
- [ ] DB pool and query budgets validated under load.
- [ ] Queue retry storms and DLQ recovery tested.
- [ ] WAF/rate-limit false positives reviewed.
- [ ] One-million test report approved; no capacity claim based only on architecture.
