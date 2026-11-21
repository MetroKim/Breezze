export interface Env {
  API_ORIGIN: string;
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
    && url.search.length <= 512;
}

function buildCacheKey(request: Request, url: URL): Request {
  const country = request.headers.get('cf-ipcountry') ?? 'XX';
  const language = (request.headers.get('accept-language') ?? 'und').slice(0, 256);
  const key = new URL(url.toString());
  key.searchParams.set('__edge_country', country);
  key.searchParams.set('__edge_language', language);
  return new Request(key.toString(), { method: 'GET' });
}

function makeOriginRequest(url: string, request: Request): Request {
  const headers = new Headers(request.headers);
  headers.delete('host');
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

  const incoming = new URL(request.url);
  const origin = new URL(env.API_ORIGIN);
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
      return hit;
    }

    const originRequest = makeOriginRequest(target.toString(), request);
    const upstream = await fetch(originRequest);
    const vary = (upstream.headers.get('vary') ?? '').toLowerCase();
    const unsafeVary = vary === '*' || vary.split(',').map((name) => name.trim())
      .some((name) => name !== '' && !['accept-language', 'accept-encoding'].includes(name));
    if (upstream.status !== 200
      || upstream.headers.has('set-cookie')
      || unsafeVary
      || /private|no-store|no-cache/i.test(upstream.headers.get('cache-control') ?? '')) {
      const passthrough = new Response(upstream.body, upstream);
      passthrough.headers.set('X-Breezze-Edge-Cache', 'BYPASS');
      return passthrough;
    }

    const headers = new Headers(upstream.headers);
    headers.delete('set-cookie');
    headers.delete('x-request-id');
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
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  }

  const upstreamRequest = makeOriginRequest(target.toString(), request);
  const upstream = await fetch(upstreamRequest);
  const response = new Response(upstream.body, upstream);
  response.headers.set('X-Breezze-Edge-Cache', 'BYPASS');
  if (request.method !== 'GET' || request.headers.has('authorization') || request.headers.has('cookie')) {
    response.headers.set('Cache-Control', 'private, no-store');
  }
  return response;
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx);
  },
};
