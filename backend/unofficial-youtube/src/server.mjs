// Experimental permission-scoped InnerTube proxy. No public access,
// no output of signed provider URLs, no file persistence or DRM bypass.
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { Innertube } from 'youtubei.js';
import {
  VIDEO_ID, experimentEnabled, allowlistedVideo, validSecret,
  safeAudioCdn, safeByteRange,
} from './security.mjs';

const PORT = Number(process.env.PORT || '8181');
let instance;
let pending;

async function youtube() {
  if (instance) return instance;
  if (!pending) {
    pending = Innertube.create({ lang: 'en', location: 'US' })
      .then(client => (instance = client))
      .finally(() => { pending = undefined; });
  }
  return pending;
}
function json(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'private, no-store, max-age=0',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(JSON.stringify(body));
}
const server = createServer(async (req, res) => {
  // There is intentionally no CORS and no unauthenticated catalog/media proxy.
  if (req.url === '/health') {
    json(res, 200, { ok: true, service: 'breezze-innertube-experiment',
      enabled: experimentEnabled() });
    return;
  }
  const id = /^\/v1\/audio\/([A-Za-z0-9_-]{11})$/.exec(req.url || '')?.[1];
  if (req.method !== 'GET' || !id || !VIDEO_ID.test(id)) {
    json(res, 404, { error: 'NOT_FOUND' });
    return;
  }
  const bearer = (req.headers.authorization || '').startsWith('Bearer ')
    ? req.headers.authorization.slice(7) : '';
  if (!validSecret(bearer) || !experimentEnabled() ||
      !allowlistedVideo(id)) {
    json(res, 403, { error: 'EXPERIMENT_UNAVAILABLE' });
    return;
  }
  const range = safeByteRange(req.headers.range);
  if (range === false) {
    json(res, 416, { error: 'INVALID_RANGE' });
    return;
  }
  try {
    const client = await youtube();
    const info = await client.getBasicInfo(id);
    if (info.playability_status?.status !== 'OK') {
      json(res, 422, { error: 'UPSTREAM_NOT_PLAYABLE' });
      return;
    }
    const format = await client.getStreamingData(id, {
      type: 'audio', quality: 'best',
    });
    // Guard against redirecting an authenticated mobile player to a
    // different origin or permitting SSRF through upstream metadata.
    if (!format?.url || !safeAudioCdn(format.url)) {
      json(res, 422, { error: 'AUDIO_FORMAT_UNAVAILABLE' });
      return;
    }
    const controller = new AbortController();
    res.on('close', () => controller.abort());
    const response = await fetch(format.url, {
      headers: range ? { Range: range } : {},
      signal: AbortSignal.any([
        controller.signal, AbortSignal.timeout(20000),
      ]),
      redirect: 'error',
    });
    if (![200, 206].includes(response.status) ||
        (range !== null && response.status !== 206) || !response.body) {
      await response.body?.cancel();
      json(res, 502, { error: 'UPSTREAM_STREAM_UNAVAILABLE' });
      return;
    }
    const upstreamMime = (response.headers.get('content-type') || '')
      .split(';')[0].toLowerCase();
    const decodedMime = (format.mime_type || '').toLowerCase();
    if (!upstreamMime.startsWith('audio/') &&
        upstreamMime !== 'application/octet-stream' &&
        !decodedMime.startsWith('audio/')) {
      await response.body.cancel();
      json(res, 502, { error: 'UPSTREAM_NOT_AUDIO' });
      return;
    }
    const headers = {
      'Content-Type': upstreamMime.startsWith('audio/') ?
        upstreamMime : (decodedMime.split(';')[0] || 'application/octet-stream'),
      'Cache-Control': 'private, no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
      'Accept-Ranges': 'bytes',
    };
    for (const name of ['content-range', 'content-length']) {
      const value = response.headers.get(name);
      if (value) headers[name] = value;
    }
    res.writeHead(response.status, headers);
    await pipeline(Readable.fromWeb(response.body), res);
  } catch {
    if (!res.headersSent) json(res, 502, { error: 'INNER_TUBE_UNAVAILABLE' });
    else res.destroy();
  }
});
server.headersTimeout = 15000;
server.requestTimeout = 30000;
server.listen(PORT, '0.0.0.0', () => {
  console.log('Breezze experimental media sidecar listening');
});
