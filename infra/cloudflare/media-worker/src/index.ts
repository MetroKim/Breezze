export interface Env {
  MEDIA_BUCKET: R2Bucket;
  MEDIA_SIGNING_KEY: string;
  MEDIA_CORS_ORIGINS?: string;
}

const encoder = new TextEncoder();

function toBase64Url(bytes: ArrayBuffer): string {
  const binary = String.fromCharCode(...new Uint8Array(bytes));
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function fromBase64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function sign(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return toBase64Url(await crypto.subtle.sign('HMAC', key, encoder.encode(payload)));
}

function constantTimeEqual(left: string, right: string): boolean {
  let mismatch = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i += 1) {
    mismatch |= (left.charCodeAt(i % Math.max(left.length, 1)) || 0)
      ^ (right.charCodeAt(i % Math.max(right.length, 1)) || 0);
  }
  return mismatch === 0;
}

async function validSignature(
  secret: string,
  payload: string,
  supplied: string | null,
  expires: number,
): Promise<boolean> {
  // Playback grants are at most six hours; do not accept an accidentally
  // long-lived capability even when the HMAC is otherwise valid.
  if (!secret || !supplied || !Number.isSafeInteger(expires) ||
      Date.now() >= expires || expires > Date.now() + 6 * 60 * 60 * 1000 + 60_000) {
    return false;
  }
  try {
    const expected = await sign(secret, payload);
    // Decode as well so malformed/non-base64url inputs are rejected.
    fromBase64Url(supplied);
    return constantTimeEqual(expected, supplied);
  } catch {
    return false;
  }
}

function error(status: number, message: string): Response {
  return new Response(message, {
    status,
    headers: { 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

async function playback(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return error(405, 'METHOD_NOT_ALLOWED');
  }
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 3) return error(404, 'NOT_FOUND');
  const [resource, trackId, variant] = parts;
  const video = resource === 'video';
  if (!video && resource !== 'audio') return error(404, 'NOT_FOUND');
  if (video) {
    if (!/^[0-9a-fA-F-]{36}$/.test(trackId) || !['stream', 'download'].includes(variant)) {
      return error(400, 'INVALID_VIDEO_PATH');
    }
  } else if (!/^[a-zA-Z0-9_-]{1,128}$/.test(trackId)
    || !/^[a-zA-Z0-9_-]{1,32}$/.test(variant)) {
    return error(400, 'INVALID_MEDIA_PATH');
  }

  const expires = Number(url.searchParams.get('e'));
  const signature = url.searchParams.get('s');
  const payload = video
    ? `video:${trackId}:${variant}:${expires}`
    : `${trackId}:${variant}:${expires}`;
  if (!await validSignature(env.MEDIA_SIGNING_KEY, payload, signature, expires)) {
    return error(403, 'MEDIA_SIGNATURE_INVALID_OR_EXPIRED');
  }

  // Downloads are a separate signed *purpose*, not a separate R2 encoding.
  // They serve the approved AAC_256 audio asset, not a phantom `download`
  // object that was never ingested by the media pipeline.
  const storageVariant = !video && variant === 'download' ? 'AAC_256' : variant;
  const key = video ? `video/${trackId}/original.mp4` : `audio/${trackId}/${storageVariant}`;
  const rangeHeader = request.headers.get('range');
  let object: R2ObjectBody | R2Object | null;
  let status = 200;
  let rangeStart: number | null = null;
  let rangeLength: number | null = null;
  let totalSize: number | null = null;
  if (rangeHeader) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader);
    if (!match) return error(416, 'INVALID_RANGE');
    const start = match[1] ? Number(match[1]) : null;
    const end = match[2] ? Number(match[2]) : null;
    const head = await env.MEDIA_BUCKET.head(key);
    if (!head) return error(404, 'MEDIA_NOT_FOUND');
    if (
      (start === null && (end === null || end <= 0)) ||
      (start !== null && (!Number.isSafeInteger(start) || start < 0)) ||
      (end !== null && (!Number.isSafeInteger(end) || end < 0)) ||
      (start !== null && end !== null && end < start)
    ) {
      return new Response(null, {
        status: 416,
        headers: { 'Content-Range': `bytes */${head.size}`, 'Cache-Control': 'no-store' },
      });
    }
    // RFC 9110 byte-range semantics: suffix N means exactly the final N
    // bytes (not N+1), and an explicit end beyond EOF is clamped to EOF.
    const offset = start !== null
      ? start
      : Math.max(0, head.size - (end ?? 0));
    const rangeEnd = start !== null
      ? Math.min(end ?? (head.size - 1), head.size - 1)
      : head.size - 1;
    const length = start === null
      ? Math.min(end ?? 0, head.size)
      : rangeEnd - start + 1;
    if (offset < 0 || length < 1 || offset >= head.size || offset + length > head.size) {
      return new Response(null, {
        status: 416,
        headers: { 'Content-Range': `bytes */${head.size}`, 'Cache-Control': 'no-store' },
      });
    }
    rangeStart = offset;
    rangeLength = length;
    totalSize = head.size;
    object = await env.MEDIA_BUCKET.get(key, { range: { offset, length } });
    status = 206;
  } else {
    object = request.method === 'HEAD'
      ? await env.MEDIA_BUCKET.head(key)
      : await env.MEDIA_BUCKET.get(key);
  }
  if (!object) return error(404, 'MEDIA_NOT_FOUND');

  // Video mode serves only MP4 originals already ingested to Breezze R2.
  // Metadata must never cause a YouTube URL to become an R2 media grant.
  const contentType = video ? 'video/mp4'
    : (object.httpMetadata?.contentType
      || (variant.toUpperCase().includes('LOSSLESS') || variant.toUpperCase().includes('FLAC') || variant.toUpperCase().includes('HI_RES')
        ? 'audio/flac' : 'audio/mp4'));
  const headers = new Headers({
    'Accept-Ranges': 'bytes',
    // Signed URLs must not be retained by browsers or intermediary caches: a cached
    // response could remain playable after the signature's expiry. Add edge caching
    // only with a cache key that includes the signature and a TTL capped by `expires`.
    'Cache-Control': 'private, no-store',
    'Content-Type': contentType,
    'ETag': object.httpEtag,
    'X-Content-Type-Options': 'nosniff',
  });
  if (video && variant === 'download') {
    headers.set('Content-Disposition', 'attachment; filename="breezze-video.mp4"');
  } else if (!video && variant === 'download') {
    headers.set('Content-Disposition', 'attachment; filename="breezze-audio.m4a"');
  }
  if (rangeHeader && rangeStart !== null && rangeLength !== null && totalSize !== null) {
    headers.set('Content-Range', `bytes ${rangeStart}-${rangeStart + rangeLength - 1}/${totalSize}`);
    headers.set('Content-Length', String(rangeLength));
  } else {
    headers.set('Content-Length', String(object.size));
  }
  if (request.method === 'HEAD') return new Response(null, { status, headers });
  if (!('body' in object)) return error(500, 'MEDIA_BODY_UNAVAILABLE');
  return new Response(object.body, { status, headers });
}

async function ingestAudio(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== 'PUT') return error(405, 'METHOD_NOT_ALLOWED');
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 4 || parts[0] !== 'ingest' || parts[1] !== 'audio') {
    return error(404, 'NOT_FOUND');
  }
  const [, , trackId, variant] = parts;
  if (!/^[0-9a-fA-F-]{36}$/.test(trackId) ||
      !['AAC_128','AAC_256','LOSSLESS','HI_RES'].includes(variant)) {
    return error(400, 'INVALID_INGEST_PATH');
  }
  const mime = url.searchParams.get('m') ?? '';
  const expectedSize = Number(url.searchParams.get('b'));
  const expires = Number(url.searchParams.get('e'));
  if (!Number.isSafeInteger(expectedSize) || expectedSize < 12 ||
      expectedSize > 95_000_000 ||
      !((variant === 'LOSSLESS' || variant === 'HI_RES')
        ? ['audio/flac', 'audio/x-flac'].includes(mime)
        : ['audio/mp4', 'audio/aac'].includes(mime))) {
    return error(400, 'INVALID_INGEST_METADATA');
  }
  if (!await validSignature(
    env.MEDIA_SIGNING_KEY,
    `ingest:${trackId}:${variant}:${mime}:${expectedSize}:${expires}`,
    url.searchParams.get('s'), expires,
  )) return error(403, 'INGEST_SIGNATURE_INVALID_OR_EXPIRED');

  // Content length and type are part of the signed capability, not trusted
  // arbitrary client metadata. Require exact byte length; no chunked unknowns.
  if (request.headers.get('content-type') !== mime ||
      Number(request.headers.get('content-length')) !== expectedSize ||
      request.body === null) return error(400, 'INGEST_REQUEST_MISMATCH');

  const key = `audio/${trackId}/${variant}`;
  if (await env.MEDIA_BUCKET.head(key)) return error(409, 'MEDIA_VARIANT_ALREADY_EXISTS');
  let created: R2Object | null = null;
  try {
    created = await env.MEDIA_BUCKET.put(key, request.body, {
      httpMetadata: { contentType: mime },
    });
    if (!created || created.size !== expectedSize) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'MEDIA_UPLOAD_SIZE_INVALID');
    }
    // Inspect format magic before marking the uploaded object provisioned.
    // Full codec/transcode validation is still a separate ingestion gate.
    const prefix = await env.MEDIA_BUCKET.get(key, {
      range: { offset: 0, length: 12 },
    });
    if (!prefix || !('body' in prefix)) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'MEDIA_FORMAT_UNREADABLE');
    }
    const leading = new Uint8Array(await new Response(prefix.body).arrayBuffer());
    const isFlac = leading.length >= 4 && String.fromCharCode(...leading.slice(0, 4)) === 'fLaC';
    const isMp4 = leading.length >= 8 && String.fromCharCode(...leading.slice(4, 8)) === 'ftyp';
    const isAdts = leading.length >= 2 && leading[0] === 0xff && (leading[1] & 0xf6) === 0xf0;
    const valid = mime.includes('flac') ? isFlac : (mime === 'audio/mp4' ? isMp4 : isAdts);
    if (!valid) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'MEDIA_FORMAT_SIGNATURE_INVALID');
    }
  } catch {
    // Do not reveal internal object keys, signed URLs or cloud errors.
    return error(503, 'MEDIA_INGEST_UNAVAILABLE');
  }
  return new Response(null, {
    status: 201,
    headers: { 'Cache-Control': 'no-store', 'Content-Type': 'text/plain' },
  });
}

/**
 * Privileged video ingest. This path is not a public user upload API.
 * Only the backend signs a grant for an internal, rights-cleared asset.
 * A successful PUT does not mark it playable: admin verification must
 * perform a signed HEAD check and promote the database row separately.
 */
async function ingestVideo(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== 'PUT') return error(405, 'METHOD_NOT_ALLOWED');
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 3 || parts[0] !== 'ingest' || parts[1] !== 'video' ||
      !/^[0-9a-fA-F-]{36}$/.test(parts[2])) return error(400, 'INVALID_VIDEO_INGEST_PATH');
  const assetId = parts[2];
  const size = Number(url.searchParams.get('b'));
  const expires = Number(url.searchParams.get('e'));
  const mime = 'video/mp4';
  if (!Number.isSafeInteger(size) || size < 16 || size > 95_000_000) {
    return error(400, 'INVALID_VIDEO_INGEST_SIZE');
  }
  if (!await validSignature(
    env.MEDIA_SIGNING_KEY, `ingest:video:${assetId}:${mime}:${size}:${expires}`,
    url.searchParams.get('s'), expires,
  ) || expires > Date.now() + 10 * 60 * 1000) {
    return error(403, 'VIDEO_INGEST_SIGNATURE_INVALID_OR_EXPIRED');
  }
  if (request.headers.get('content-type') !== mime ||
      Number(request.headers.get('content-length')) !== size ||
      request.body === null) return error(400, 'VIDEO_INGEST_REQUEST_MISMATCH');

  const key = `video/${assetId}/original.mp4`;
  if (await env.MEDIA_BUCKET.head(key)) return error(409, 'VIDEO_ALREADY_INGESTED');
  try {
    const created = await env.MEDIA_BUCKET.put(key, request.body, {
      httpMetadata: { contentType: mime },
    });
    if (!created || created.size !== size) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'VIDEO_SIZE_MISMATCH');
    }
    // MP4 has a box-size prefix followed by the ftyp box. This is only
    // a signature sanity check, NOT a codec/rights/malware certification.
    const prefix = await env.MEDIA_BUCKET.get(key, {
      range: { offset: 0, length: 16 },
    });
    if (!prefix || !('body' in prefix)) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'VIDEO_FORMAT_UNREADABLE');
    }
    const bytes = new Uint8Array(await new Response(prefix.body).arrayBuffer());
    const isMp4 = bytes.length >= 12 &&
      String.fromCharCode(...bytes.slice(4, 8)) === 'ftyp';
    if (!isMp4) {
      await env.MEDIA_BUCKET.delete(key);
      return error(422, 'VIDEO_FORMAT_SIGNATURE_INVALID');
    }
    return new Response(null, { status: 201, headers: { 'Cache-Control': 'no-store' } });
  } catch {
    // Never log object keys, signing grants or upstream storage errors.
    return error(503, 'VIDEO_INGEST_UNAVAILABLE');
  }
}

/** Browser origin allowlisting is not media authorization; the HMAC still is. */
function allowedMediaOrigin(request: Request, env: Env): string | null {
  const origin = request.headers.get('origin');
  if (!origin || origin === 'null') return null;
  const listed = (env.MEDIA_CORS_ORIGINS ?? '').split(',').map(v => v.trim());
  return listed.includes(origin) ? origin : null;
}

function withPlaybackCors(response: Response, origin: string | null): Response {
  if (!origin) return response;
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', origin);
  headers.set('Access-Control-Expose-Headers',
    'Accept-Ranges, Content-Range, Content-Length, Content-Type, ETag');
  headers.append('Vary', 'Origin');
  return new Response(response.body, { status: response.status, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.MEDIA_SIGNING_KEY || !env.MEDIA_BUCKET) return error(503, 'MEDIA_STORAGE_NOT_CONFIGURED');
    const url = new URL(request.url);
    // Configuration health, not an assertion that any recording is ingested.
    // This endpoint never reports or probes private object keys or secrets.
    if (url.pathname === '/health') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return error(405, 'METHOD_NOT_ALLOWED');
      }
      return new Response(request.method === 'HEAD' ? null : JSON.stringify({
        status: 'configured', service: 'breezze-media',
      }), {
        status: 200,
        headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json' },
      });
    }
    if (url.pathname.startsWith('/ingest/video/')) {
      return ingestVideo(request, url, env);
    }
    if (url.pathname.startsWith('/ingest/audio/')) {
      return ingestAudio(request, url, env);
    }
    if (url.pathname.startsWith('/audio/') || url.pathname.startsWith('/video/')) {
      const origin = allowedMediaOrigin(request, env);
      if (request.method === 'OPTIONS') {
        if (!origin) return error(403, 'MEDIA_CORS_ORIGIN_DENIED');
        return new Response(null, { status: 204, headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
          'Access-Control-Allow-Headers': 'Range',
          'Access-Control-Max-Age': '600',
          'Cache-Control': 'no-store',
          'Vary': 'Origin',
        } });
      }
      return withPlaybackCors(await playback(request, url, env), origin);
    }
    return error(404, 'NOT_FOUND');
  },
};
