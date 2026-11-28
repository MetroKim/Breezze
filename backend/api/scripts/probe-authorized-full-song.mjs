#!/usr/bin/env node
/**
 * V8 full-song acceptance probe for a specifically approved QA environment.
 * Does NOT download to disk or log signed media URLs, tokens or audio bytes.
 *
 * Required:
 *   BREEZZE_QA_API_ORIGIN=https://qa-api.example
 *   BREEZZE_QA_ACCESS_TOKEN=<short-lived verified listener JWT>
 *   BREEZZE_QA_TRACK_QUERY=<one approved full song title>
 *
 * This is not a catalog/license grant. It fails closed when the independent
 * legal/music-rights setup has not been completed. Do not run on production.
 */
const { BREEZZE_QA_API_ORIGIN: rawOrigin,
  BREEZZE_QA_ACCESS_TOKEN: token,
  BREEZZE_QA_TRACK_QUERY: query,
  NODE_ENV: nodeEnv,
  RAILWAY_ENVIRONMENT_NAME: railwayEnv,
} = process.env;

function fail(code) { throw new Error(code); }
function mustUrl(value, expectedOrigin) {
  let url;
  try { url = new URL(value); } catch { fail('QA_URL_INVALID'); }
  if (url.protocol !== 'https:' || url.origin !== expectedOrigin ||
      url.username || url.password || url.hash) fail('QA_URL_NOT_APPROVED');
  return url;
}
function decodeResponse(json) {
  const root = json?.data && typeof json.data === 'object'
    ? json.data : json;
  if (!root || typeof root !== 'object') fail('QA_BAD_RESPONSE');
  return root;
}
function mediaHeaders(response, status) {
  if (response.status !== status) fail('QA_MEDIA_STATUS_' + response.status);
  const type = (response.headers.get('content-type') ?? '')
    .split(';', 1)[0].trim().toLowerCase();
  if (!/^audio\/(mpeg|mp3|mp4|aac|flac|x-flac|ogg|opus|wav|x-wav)$/.test(type))
    fail('QA_MEDIA_MIME_INVALID');
  return type;
}
async function consumeAudio(response, ceilingBytes) {
  if (!response.body) fail('QA_AUDIO_BODY_MISSING');
  let count = 0;
  const reader = response.body.getReader();
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      count += chunk.value.byteLength;
      if (count > ceilingBytes) fail('QA_AUDIO_TOO_LARGE');
    }
  } finally { reader.releaseLock(); }
  return count;
}
function rangeParts(value) {
  const m = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(value ?? '');
  if (!m) fail('QA_CONTENT_RANGE_INVALID');
  const start = Number(m[1]), end = Number(m[2]), size = Number(m[3]);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
      !Number.isSafeInteger(size) || start > end || end >= size)
    fail('QA_CONTENT_RANGE_INVALID');
  return { start, end, size };
}

async function run() {
  if (nodeEnv === 'production' ||
      (railwayEnv ?? '').toLowerCase() === 'production') fail('QA_PRODUCTION_FORBIDDEN');
  if (!rawOrigin || !token || !query || query.trim().length < 2) fail('QA_CONFIGURATION_MISSING');
  const origin = new URL(rawOrigin).origin;
  const root = mustUrl(rawOrigin, origin);
  if (root.pathname !== '/' || root.search) fail('QA_ORIGIN_MUST_BE_BARE');
  const endpoint = (route) => new URL('/api/v1/' + route, origin);
  const auth = { Authorization: 'Bearer ' + token, Accept: 'application/json' };
  const api = async (route, options = {}) => {
    const response = await fetch(endpoint(route), {
      ...options, headers: { ...auth, ...(options.headers ?? {}) },
      redirect: 'error', signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) fail('QA_API_' + response.status + '_' + route.split('?')[0]);
    return decodeResponse(await response.json());
  };

  const results = await api(
    'catalog/authorized-audio/search?q=' + encodeURIComponent(query.trim()),
  );
  const songs = Array.isArray(results.items) ? results.items : [];
  if (songs.length < 1) fail('QA_NO_AUTHORIZED_FULL_SONG_FOUND');
  const song = songs.find(item =>
    item.providerId === 'opensubsonic' &&
    typeof item.providerTrackId === 'string' &&
    /^[A-Za-z0-9_-]{1,128}$/.test(item.providerTrackId) &&
    typeof item.canonicalTrackId === 'string' &&
    /^[0-9a-fA-F-]{36}$/.test(item.canonicalTrackId) &&
    typeof item.durationSec === 'number' && item.durationSec >= 60,
  );
  if (!song) fail('QA_NO_ELIGIBLE_FULL_TRACK');
  const session = await api('playback/sessions', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      providerId: 'opensubsonic',
      providerTrackId: song.providerTrackId,
      canonicalTrackId: song.canonicalTrackId,
    }),
  });
  const playback = session.playback;
  if (!session.id || typeof playback?.streamUrl !== 'string')
    fail('QA_NO_PLAYBACK_SESSION');
  let streamBytes = 0, totalBytes = 0;
  try {
    const audioUrl = mustUrl(playback.streamUrl, origin);
    if (!audioUrl.pathname.startsWith('/api/v1/providers/opensubsonic/audio/'))
      fail('QA_UNEXPECTED_MEDIA_ROUTE');
    const expiresMs = Date.parse(playback.expiresAt);
    if (!Number.isFinite(expiresMs) || expiresMs < Date.now() + 15_000)
      fail('QA_PLAYBACK_LEASE_TOO_SHORT');
    // Never print the signed grant from the URL.
    const audioReq = async (method, headers = {}, deadline = 180_000) =>
      fetch(audioUrl, {
        method, headers: { ...headers, Accept: 'audio/*' },
        redirect: 'error', signal: AbortSignal.timeout(deadline),
      });
    const head = await audioReq('HEAD');
    mediaHeaders(head, 200);
    const len = Number(head.headers.get('content-length'));
    if (!Number.isSafeInteger(len) || len < 8192 || len > 150_000_000)
      fail('QA_MEDIA_SIZE_INVALID');
    totalBytes = len;
    const first = await audioReq('GET', { Range: 'bytes=0-4095' });
    mediaHeaders(first, 206);
    const range = rangeParts(first.headers.get('content-range'));
    if (range.start !== 0 || range.end !== 4095 || range.size !== len)
      fail('QA_FIRST_RANGE_INVALID');
    if (await consumeAudio(first, 4096) !== 4096) fail('QA_FIRST_RANGE_TRUNCATED');

    const offset = Math.max(0, Math.min(len - 4096, Math.floor(len / 2)));
    const last = offset + 4095;
    const mid = await audioReq('GET', { Range: 'bytes=' + offset + '-' + last });
    mediaHeaders(mid, 206);
    const middleRange = rangeParts(mid.headers.get('content-range'));
    if (middleRange.start !== offset || middleRange.end !== last ||
        middleRange.size !== len) fail('QA_SEEK_RANGE_INVALID');
    if (await consumeAudio(mid, 4096) !== 4096) fail('QA_SEEK_RANGE_TRUNCATED');

    const full = await audioReq('GET', {}, 240_000);
    mediaHeaders(full, 200);
    streamBytes = await consumeAudio(full, 150_000_000);
    if (streamBytes !== totalBytes) fail('QA_FULL_SONG_TRUNCATED');
  } finally {
    // Session cleanup is best-effort even after a probe failure.
    await fetch(endpoint('playback/sessions/' + encodeURIComponent(session.id) + '/stop'), {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: '{}', redirect: 'error',
      signal: AbortSignal.timeout(7_000),
    }).catch(() => {});
  }
  // Never claim audible playback, gapless, licensing or device acceptance:
  // these are independent gates. This proves HTTP bytes, not a user's ears.
  console.log(JSON.stringify({
    status: 'QA_HTTP_FULL_SONG_BYTES_PASS',
    kind: 'synthetic-or-approved-QA-only',
    mimeType: playback.mimeType,
    declaredDurationSec: song.durationSec,
    bytesRead: streamBytes, rangeStart: true, rangeSeek: true,
    nativePlaybackVerified: false, commercialCatalogVerified: false,
  }));
}

if (process.argv[1] && import.meta.url === new URL('file://' + process.argv[1]).href) {
  run().catch(error => {
    // Only stable error codes; never dump URLs, bearer values or stack traces.
    const message = error instanceof Error && /^QA_[A-Z0-9_]+$/.test(error.message)
      ? error.message : 'QA_UNKNOWN_FAILURE';
    console.error(message);
    process.exitCode = 1;
  });
}

export { decodeResponse, mustUrl, mediaHeaders, rangeParts, consumeAudio };
