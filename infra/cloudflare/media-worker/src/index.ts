export interface Env {
  MEDIA_BUCKET: R2Bucket;
  MEDIA_SIGNING_KEY: string;
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
  if (!secret || !supplied || !Number.isSafeInteger(expires) || Date.now() >= expires) {
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

async function upload(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== 'PUT') return error(405, 'METHOD_NOT_ALLOWED');
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 4) return error(404, 'NOT_FOUND');

  let userId: string;
  let filename: string;
  try {
    userId = decodeURIComponent(parts[1]);
    filename = decodeURIComponent(parts[3]);
  } catch {
    return error(400, 'INVALID_PATH');
  }

  const jobId = parts[2];
  const bytes = Number(url.searchParams.get('b'));
  const expires = Number(url.searchParams.get('e'));
  const signature = url.searchParams.get('s');
  const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120);
  if (!userId || !jobId || !safeName || safeName !== filename
    || !Number.isSafeInteger(bytes) || bytes < 1 || bytes > 100 * 1024 * 1024) {
    return error(400, 'INVALID_UPLOAD');
  }

  const payload = `upload:${userId}:${jobId}:${filename}:${bytes}:${expires}`;
  if (!await validSignature(env.MEDIA_SIGNING_KEY, payload, signature, expires)) {
    return error(403, 'UPLOAD_SIGNATURE_INVALID_OR_EXPIRED');
  }

  const declaredLength = Number(request.headers.get('content-length'));
  if (declaredLength !== bytes) return error(413, 'CONTENT_LENGTH_MISMATCH');
  const key = `quarantine/${userId}/${jobId}/${filename}`;
  await env.MEDIA_BUCKET.put(key, request.body, {
    httpMetadata: {
      contentType: request.headers.get('content-type') || 'application/octet-stream',
      cacheControl: 'private, no-store',
    },
    customMetadata: { userId, jobId, originalFilename: filename },
  });
  return new Response(null, {
    status: 201,
    headers: { 'Cache-Control': 'no-store', 'X-Upload-Object': key },
  });
}

async function playback(request: Request, url: URL, env: Env): Promise<Response> {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return error(405, 'METHOD_NOT_ALLOWED');
  }
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 3) return error(404, 'NOT_FOUND');
  const [, trackId, variant] = parts;
  if (!/^[a-zA-Z0-9_-]{1,128}$/.test(trackId)
    || !/^[a-zA-Z0-9_-]{1,32}$/.test(variant)) return error(400, 'INVALID_MEDIA_PATH');

  const expires = Number(url.searchParams.get('e'));
  const signature = url.searchParams.get('s');
  const payload = `${trackId}:${variant}:${expires}`;
  if (!await validSignature(env.MEDIA_SIGNING_KEY, payload, signature, expires)) {
    return error(403, 'MEDIA_SIGNATURE_INVALID_OR_EXPIRED');
  }

  const key = `audio/${trackId}/${variant}`;
  const rangeHeader = request.headers.get('range');
  let object: R2ObjectBody | R2Object | null;
  let status = 200;
  if (rangeHeader) {
    const match = /^bytes=(\\d*)-(\\d*)$/.exec(rangeHeader);
    if (!match) return error(416, 'INVALID_RANGE');
    const start = match[1] ? Number(match[1]) : null;
    const end = match[2] ? Number(match[2]) : null;
    const head = await env.MEDIA_BUCKET.head(key);
    if (!head) return error(404, 'MEDIA_NOT_FOUND');
    const offset = start ?? Math.max(0, head.size - (end ?? 0) - 1);
    const length = start !== null && end !== null
      ? end - start + 1
      : start !== null ? head.size - start : (end ?? 0) + 1;
    if (offset < 0 || length < 1 || offset + length > head.size) {
      return new Response(null, {
        status: 416,
        headers: { 'Content-Range': `bytes */${head.size}`, 'Cache-Control': 'no-store' },
      });
    }
    object = await env.MEDIA_BUCKET.get(key, { range: { offset, length } });
    status = 206;
  } else {
    object = request.method === 'HEAD'
      ? await env.MEDIA_BUCKET.head(key)
      : await env.MEDIA_BUCKET.get(key);
  }
  if (!object) return error(404, 'MEDIA_NOT_FOUND');

  const contentType = object.httpMetadata?.contentType
    || (variant.toUpperCase().includes('LOSSLESS') || variant.toUpperCase().includes('FLAC')
      ? 'audio/flac' : 'audio/mp4');
  const headers = new Headers({
    'Accept-Ranges': 'bytes',
    'Cache-Control': rangeHeader ? 'private, no-store' : 'public, max-age=60, s-maxage=60',
    'Content-Type': contentType,
    'ETag': object.httpEtag,
    'X-Content-Type-Options': 'nosniff',
  });
  if (rangeHeader && 'range' in object && object.range) {
    const range = object.range;
    headers.set('Content-Range', `bytes ${range.offset}-${range.offset + range.length - 1}/${object.size}`);
    headers.set('Content-Length', String(range.length));
  } else {
    headers.set('Content-Length', String(object.size));
  }
  if (request.method === 'HEAD') return new Response(null, { status, headers });
  if (!('body' in object)) return error(500, 'MEDIA_BODY_UNAVAILABLE');
  return new Response(object.body, { status, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.MEDIA_SIGNING_KEY || !env.MEDIA_BUCKET) return error(503, 'MEDIA_STORAGE_NOT_CONFIGURED');
    const url = new URL(request.url);
    if (url.pathname.startsWith('/upload/')) return upload(request, url, env);
    if (url.pathname.startsWith('/audio/')) return playback(request, url, env);
    return error(404, 'NOT_FOUND');
  },
};
