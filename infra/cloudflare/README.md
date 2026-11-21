# Breezze Cloudflare-First Infrastructure Architecture

**Status:** Architecture decision record / implementation target  
**Decision:** Cloudflare is Breezze's primary edge, media-delivery, and perimeter-security platform. The existing NestJS + PostgreSQL backend remains the application system of record.

## 1. Decision and boundaries

Breezze will use Cloudflare where it provides clear operational value: edge routing, private object storage, CDN delivery, caching, request filtering, rate limiting, and asynchronous edge workloads.

Cloudflare does **not** replace the NestJS domain backend or PostgreSQL by default. We will not migrate the application into Workers merely for architectural fashion. The Flutter app continues to call the NestJS API; the Cloudflare edge sits in front of the API and serves authorized media.

### System topology

```text
Flutter clients (Android / iOS / tablet / desktop)
        |
        v
Cloudflare DNS + TLS + WAF + rate limiting
        |
        +--------------------------+
        |                          |
        v                          v
api.breezze...                 media.breezze...
Cloudflare Worker              Cloudflare Worker
(edge routing /                 (auth + signed access /
request policy)                 range-aware media gateway)
        |                          |
        v                          v
NestJS API (origin)             Private R2 bucket
        |                          |
        +---- PostgreSQL            +---- CDN/cache policy
        +---- Redis / BullMQ
        +---- external catalog / rights providers
```

The Worker layer is an edge gateway and policy enforcement point. Domain decisions, user ownership, catalog normalization, playlist rules, and rights decisions remain in NestJS unless a specific edge use case is approved.

## 2. Cloudflare service allocation

| Service | Breezze responsibility | Policy |
|---|---|---|
| DNS | Authoritative DNS for Breezze zones | Enable DNSSEC where supported |
| TLS / SSL | Client-to-edge encryption and origin encryption | Full (strict); no insecure origin mode |
| WAF / managed rules | Filter common web attacks and abusive traffic | Start in log/simulate mode, tune, then block |
| Rate Limiting | Per-route and per-identity abuse controls | Apply stricter limits to auth, search, playback resolution, and uploads |
| Workers | API gateway, media authorization gateway, edge request logic | Keep stateless; do not move NestJS domain logic wholesale |
| R2 | Private object storage for owned/licensed media, artwork, and derived assets | Private buckets; access only through authorized service paths |
| CDN / Cache API | Cache safe public assets and eligible media responses near users | Never cache private user data or unvalidated authorization responses |
| KV | Small, eventually consistent configuration and short-lived cache entries | Not the source of truth for balances, rights, or critical session state |
| Durable Objects | Coordination for genuinely stateful real-time features | Introduce only for live collaborative playback/rooms where required |
| Queues | Async media processing, metadata jobs, webhook fan-out, and retries | Consumers must be idempotent; use dead-letter handling |
| Turnstile | Bot mitigation on registration, login recovery, and abuse-prone public forms | Validate tokens server-side |
| Observability | Worker logs, traces, metrics and alerts | Redact tokens, signed URLs, and personal data |

**Not selected as primary database:** D1. PostgreSQL remains the canonical relational database because the existing NestJS/Prisma data model, transactions, joins, and operational workflows already depend on it. D1 may be evaluated for an isolated edge-owned dataset, not as a second competing source of truth.

**Redis remains:** BullMQ and current backend workloads depend on Redis. Cloudflare KV is not a drop-in Redis replacement.

## 3. Request and media flows

### API request

1. Client sends HTTPS request to the public API hostname.
2. Cloudflare terminates TLS, applies WAF and route-level rate limits.
3. API Worker validates basic request shape and forwards to the private NestJS origin.
4. NestJS authenticates the user, authorizes the operation, applies domain rules, and accesses PostgreSQL/Redis.
5. Response returns through Cloudflare.
6. Cache only explicitly public, versioned, non-user-specific GET responses. Authenticated API responses default to `private, no-store` unless a route is reviewed and explicitly opted in.

### Authorized media playback

1. Flutter requests playback resolution from NestJS using a canonical track ID.
2. NestJS resolves the catalog provider and invokes the Rights module.
3. If permitted, backend returns a short-lived media access grant or opaque playback token.
4. Client requests the media object through the media Worker.
5. Worker validates the grant, object key, expiry, allowed method, and byte-range policy.
6. Worker streams the private R2 object and supports HTTP Range requests for seeking.
7. Cache behavior is selected by object class and authorization model. Do not put user-specific or revocable private streams into a shared cache key.

A successful HTTP response is not proof that a track is legally playable. Rights and territory checks must happen before issuing the grant and must be revocable.

## 4. R2 bucket and object layout

Use separate private buckets or strict prefixes for different lifecycle/security classes:

- `audio-originals/` — quarantined uploads and source masters; never public.
- `audio-transcoded/` — approved playback renditions.
- `artwork/` — cover art and artist imagery.
- `previews/` — explicitly authorized preview assets.
- `temporary/` — short-lived processing artifacts with lifecycle cleanup.

Object keys must be opaque and non-guessable; do not include email addresses or other personal identifiers. Persist canonical object keys and metadata in PostgreSQL, not public R2 URLs.

Upload path:
1. Authenticated client asks NestJS for an upload session.
2. NestJS validates ownership, quota/abuse policy, and upload metadata.
3. Upload goes to a restricted staging destination.
4. Queue job validates MIME signature, file size, malware/moderation status, and metadata.
5. Approved asset is transcoded/processed and moved to the approved prefix.
6. Database state changes to ready only after processing succeeds.

## 5. Cache policy

| Content | Cache policy |
|---|---|
| Versioned app assets, SVGs, static artwork | Long TTL + immutable where versioned |
| Public catalog metadata | Short/medium TTL; purge or version on updates |
| Public chart/editorial feeds | Short TTL with explicit freshness metadata |
| Authenticated library/profile/playlist data | Private, no-store by default |
| Playback authorization responses | No shared cache |
| Private audio | No shared cache unless token-bound cache key and revocation behavior are explicitly designed and tested |
| Signed upload/download grants | No-store |

Use cache tags or purge workflows for assets that need invalidation. Cache misses must safely fall through to the origin. Never treat KV or cache as the authoritative rights database.

## 6. Security model

- Keep R2 buckets private.
- Keep origin services inaccessible from the public internet where deployment supports private networking; otherwise require authenticated origin access and strict firewall allowlists.
- Store API keys, origin credentials, signing keys, and provider secrets as Worker secrets or backend secret-manager values. Never commit secrets.
- Validate signed grants server-side, including expiry, object key, HTTP method, byte-range allowance, and user/territory binding as required.
- Apply request-size limits and upload content validation.
- Use per-route rate limits plus account/device/IP signals; avoid IP-only controls that punish carrier-grade NAT users.
- Turnstile is a bot signal, not authentication.
- Log request IDs and security outcomes, not access tokens, passwords, raw signed URLs, or unnecessary personal data.
- Keep authentication and authorization separate: authentication establishes identity; authorization checks whether that identity may perform this action on this resource now.

## 7. Reliability and scale

Cloudflare's edge reduces latency and absorbs/cache-serves repeat traffic, but it does not make the whole system infinitely scalable. The database, origin API, provider quotas, audio egress, and queue consumers remain capacity constraints.

Required controls:
- PostgreSQL indexes, connection pooling, query budgets, and read-path optimization.
- Redis/BullMQ queue concurrency limits, bounded retries with exponential backoff and jitter, idempotency keys, and dead-letter queues.
- Per-provider timeouts, circuit breakers, and fallback behavior.
- CDN cache-hit ratio, R2 egress, Worker CPU/duration, origin latency, DB saturation, queue age, playback-start latency, and playback failure dashboards.
- Load tests for concurrent search, playback resolution, range requests, uploads, and hot-object traffic.
- Multi-region database strategy only when measured availability/latency needs justify the complexity.

## 8. Deployment environments

Use separate Cloudflare resources and credentials for development, staging, and production. Production R2 buckets and secrets must never be reused by local development.

Deployment pipeline:
1. Typecheck and unit test Worker code.
2. Run API contract and authorization tests.
3. Deploy Worker to staging.
4. Run smoke tests for health, auth forwarding, R2 authorization, range requests, cache headers, and rate limiting.
5. Promote the same artifact to production.
6. Monitor error rate and playback-start latency; support fast rollback.

Wrangler configuration must use environment-specific bindings. Resource IDs and secret values belong in deployment configuration/secrets, not checked-in source.

## 9. Initial rollout order

1. DNS, TLS Full (strict), WAF baseline, and origin protection.
2. API hostname proxy and route-specific rate limiting.
3. Private R2 buckets and upload-processing workflow.
4. Media Worker with authorization and byte-range support.
5. Cache only static/versioned assets and explicitly public catalog responses.
6. Queues for media processing and background jobs.
7. Turnstile for selected abuse-prone flows.
8. Durable Objects only after a concrete real-time feature requires coordinated state.

## 10. Explicit non-goals

- No wholesale NestJS-to-Workers rewrite.
- No D1/PostgreSQL dual-write architecture.
- No replacing Redis/BullMQ with KV.
- No public R2 bucket for protected music.
- No caching of private library/profile/playback authorization data.
- No claim that Cloudflare alone guarantees a target of hundreds of millions of concurrent users.
- No addition of subscription, billing, or paywall services. Breezze remains free.

## 11. Operational acceptance checklist

- [ ] TLS is Full (strict); origin is protected.
- [ ] WAF rules are tuned against observed false positives.
- [ ] Auth, search, playback, and upload routes have explicit rate limits.
- [ ] R2 buckets are private and lifecycle policies are configured.
- [ ] Playback grants are short-lived, scoped, and revocable.
- [ ] Media Worker supports byte ranges and correct content headers.
- [ ] Private responses are not shared-cached.
- [ ] Upload pipeline validates content before publication.
- [ ] Queue consumers are idempotent and have bounded retry/dead-letter behavior.
- [ ] Secrets are deployed through secret bindings, never committed.
- [ ] Dashboards and alerts cover edge, origin, database, queue, and playback health.
- [ ] Load tests include origin saturation and cache-miss scenarios.
