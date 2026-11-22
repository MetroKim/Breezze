export interface Env {
  API_ORIGIN: string;
  EDGE_SHARED_SECRET: string;
}

const PUBLIC_CATALOG_PATH =
  /^\/api\/v1\/catalog\/(?:songs|albums|artists)\/[A-Za-z0-9_-]{1,128}$/;

const EDGE_TTL_SECONDS = 90;
const STALE_TTL_SECONDS = 30;

function jsonError(status: number, code: string): Response {
  return Response.json(
    { statusCode: status, error: code },
    { status, headers: { 'Cache-Control': 'no-store' } },
  );
}

function isPublicCatalogRequest(request: Request, url: URL): boolean {
  return request.method === 'GET'
    && PUBLIC_CATALOG_PATH.test(url.pathname)
    && !request.headers.has('authorization')
    && !request.headers.has('cookie')
    && !request.headers.has('range')
    && url.search.length === 0
    && (request.headers.get('accept-language') ?? 'und').length <= 256;
}

function buildCacheKey(request: Request, url: URL): Request {
  const country = request.headers.get('cf-ipcountry') ?? 'XX';
  const language = (request.headers.get('accept-language') ?? 'und').slice(0, 256);
  const key = new URL(url.toString());
  key.searchParams.set('__edge_country', country);
  key.searchParams.set('__edge_language', language);
  return new Request(key.toString(), { method: 'GET' });
}

function makeOriginRequest(url: string, request: Request, edgeSecret: string): Request {
  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.delete('x-breezze-edge-secret');
  headers.set('x-breezze-edge-secret', edgeSecret);

  // Cloudflare overwrites cf-ipcountry at the edge. Never trust a client-
  // supplied Breezze country header; derive the origin value only here.
  headers.delete('x-breezze-country');
  const edgeCountry = request.headers.get('cf-ipcountry')?.trim().toUpperCase();
  if (edgeCountry && /^[A-Z]{2}$/.test(edgeCountry)) {
    headers.set('x-breezze-country', edgeCountry);
  }
  const init: RequestInit = {
    method: request.method,
    headers,
    redirect: request.redirect,
  };
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body;
  }
  return new Request(url, init);
}

async function handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  if (!env.API_ORIGIN) return jsonError(503, 'API_ORIGIN_NOT_CONFIGURED');
  if (!env.EDGE_SHARED_SECRET || env.EDGE_SHARED_SECRET.length < 32) {
    return jsonError(503, 'EDGE_SHARED_SECRET_NOT_CONFIGURED');
  }

  const incoming = new URL(request.url);
  let origin: URL;
  try {
    origin = new URL(env.API_ORIGIN);
  } catch {
    return jsonError(503, 'API_ORIGIN_INVALID');
  }
  if (origin.username || origin.password || origin.search || origin.hash
    || (origin.pathname !== '/' && origin.pathname !== '')) {
    return jsonError(503, 'API_ORIGIN_MUST_BE_ORIGIN_ONLY');
  }
  const path = incoming.pathname;
  const target = new URL(path + incoming.search, origin);

  if (target.protocol !== 'https:' && target.hostname !== 'localhost') {
    return jsonError(500, 'API_ORIGIN_MUST_USE_HTTPS');
  }

  const cacheable = isPublicCatalogRequest(request, incoming);
  if (cacheable) {
    const cache = caches.default;
    const cacheKey = buildCacheKey(request, incoming);
    const cached = await cache.match(cacheKey);
    if (cached) {
      const hit = new Response(cached.body, cached);
      hit.headers.set('X-Breezze-Edge-Cache', 'HIT');
      hit.headers.set('X-Request-Id', crypto.randomUUID());
      return hit;
    }

    const originRequest = makeOriginRequest(target.toString(), request, env.EDGE_SHARED_SECRET);
    let upstream: Response;
    try {
      upstream = await fetch(originRequest);
    } catch {
      return jsonError(502, 'API_ORIGIN_UNAVAILABLE');
    }
    const vary = (upstream.headers.get('vary') ?? '').toLowerCase();
    const unsafeVary = vary === '*' || vary.split(',').map((name) => name.trim())
      .some((name) => name !== '' && name !== 'accept-language');
    if (upstream.status !== 200
      || upstream.headers.has('set-cookie')
      || unsafeVary
      || /private|no-store|no-cache/i.test(upstream.headers.get('cache-control') ?? '')) {
      const passthrough = new Response(upstream.body, upstream);
      passthrough.headers.delete('x-breezze-edge-secret');
      passthrough.headers.set('Cache-Control', 'private, no-store');
      passthrough.headers.set('X-Breezze-Edge-Cache', 'BYPASS');
      return passthrough;
    }

    const headers = new Headers(upstream.headers);
    headers.delete('set-cookie');
    headers.delete('x-breezze-edge-secret');
    headers.set(
      'Cache-Control',
      `public, max-age=0, s-maxage=${EDGE_TTL_SECONDS}, stale-while-revalidate=${STALE_TTL_SECONDS}`,
    );
    headers.set('X-Breezze-Edge-Cache', 'MISS');
    const response = new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers,
    });
    const cacheHeaders = new Headers(response.headers);
    cacheHeaders.delete('x-request-id');
    const cacheBody = response.clone();
    const cacheResponse = new Response(cacheBody.body, {
      status: cacheBody.status,
      statusText: cacheBody.statusText,
      headers: cacheHeaders,
    });
    ctx.waitUntil(cache.put(cacheKey, cacheResponse));
    return response;
  }

  const upstreamRequest = makeOriginRequest(target.toString(), request, env.EDGE_SHARED_SECRET);
  let upstream: Response;
  try {
    upstream = await fetch(upstreamRequest);
  } catch {
    return jsonError(502, 'API_ORIGIN_UNAVAILABLE');
  }
  const response = new Response(upstream.body, upstream);
  response.headers.delete('x-breezze-edge-secret');
  response.headers.set('X-Breezze-Edge-Cache', 'BYPASS');
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx);
  },
};
