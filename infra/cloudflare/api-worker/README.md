# Breezze API Edge Worker

This Worker is the Cloudflare edge entry point for the NestJS API. It is deliberately separate from `media-worker`, which handles private R2 uploads and media objects.

## Responsibilities

- Forward API requests to the configured HTTPS NestJS origin.
- Cache only public catalog detail GET routes:
  - `/api/v1/catalog/songs/{id}`
  - `/api/v1/catalog/albums/{id}`
  - `/api/v1/catalog/artists/{id}`
- Bypass cache for all other routes, all requests with Authorization/Cookie headers, range requests, and non-GET methods.
- Vary public cache entries by full URL/query, visitor country and first accepted language.
- Never cache playback resolution, signed media URLs, auth, user libraries, playlists, favorites, listening history, or writes.

The Worker does not implement domain authorization, rights decisions, provider selection, or authentication. Those remain in NestJS.

## Configure

1. Set `API_ORIGIN` to the HTTPS origin hosting NestJS (for example, `https://api-origin.example.com`). Do not point it back at the Worker hostname.
2. Deploy this Worker with Wrangler.
3. Attach the public API hostname/route to this Worker.
4. Restrict the origin firewall/network to Cloudflare egress where practical. If the origin is publicly reachable, configure authenticated origin pulls or an equivalent origin-authentication mechanism before production.
5. Configure Cloudflare WAF managed rules and rate-limiting rules in the dashboard for auth, search, playback resolution and write endpoints. Use route-specific limits; do not rely on one global IP-only threshold because mobile carrier NAT can group many listeners behind one address.
6. Verify with `curl -I` that private routes return `Cache-Control: private, no-store` and `X-Breezze-Edge-Cache: BYPASS`.

## Cache behavior

The initial edge TTL is 90 seconds, with a 30-second stale-while-revalidate window. This is intentionally conservative. The Worker only stores a 200 response when the origin has not marked it private/no-store/no-cache and has not emitted a Set-Cookie header. Tune TTL after freshness and origin-load measurements.

Cloudflare Cache API storage is data-center-local; this is an edge optimization, not a globally consistent database. Redis remains the shared backend hot cache, PostgreSQL remains canonical truth, and client cache remains bounded and disposable.

## Deployment

```sh
npm install
npx wrangler deploy
```

Set `API_ORIGIN` as a Wrangler variable in `wrangler.toml` or through the Cloudflare dashboard. Keep production origin details out of public source when required by your deployment policy.

This repository change does not deploy the Worker, create DNS records, provision WAF/rate-limit rules, or prove one-million-user capacity. Those require Cloudflare account access and staged load tests.
