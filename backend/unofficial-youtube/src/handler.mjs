// Testable, isolated transport for permission-scoped audio experiments.
// No public media route, cookies, persistent media, or signed URL logging.
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  experimentEnabled, allowlistedVideo, validSecret,
  safeAudioCdn, safeByteRange, validUpstreamRange,
} from './security.mjs';

function reply(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'private, no-store, max-age=0',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(JSON.stringify(body));
}

// Dependency injection permits full HTTP and byte-range acceptance without
// scraping, downloading, or authenticating against upstream YouTube.
export function createExperimentHandler({
  env = process.env,
  createClient,
  fetchAudio = fetch,
} = {}) {
  if (typeof createClient !== 'function') {
    throw new TypeError('createClient must be provided');
  }
  if (typeof fetchAudio !== 'function') {
    throw new TypeError('fetchAudio must be provided');
  }

  return async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      reply(res, 200, {
        ok: true,
        service: 'breezze-innertube-experiment',
        enabled: experimentEnabled(env),
      });
      return;
    }
    const match = /^\/v1\/audio\/([A-Za-z0-9_-]{11})$/.exec(req.url || '');
    if (req.method !== 'GET' || !match) {
      reply(res, 404, { error: 'NOT_FOUND' });
      return;
    }
    const trackId = match[1];
    const authorization = req.headers.authorization || '';
    const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
    // Auth must be checked *before* contacting upstream, even for test audio.
    if (!experimentEnabled(env) || !allowlistedVideo(trackId, env) ||
        !validSecret(bearer, env.BREEZZE_INTERNAL_AUDIO_TEST_TOKEN)) {
      reply(res, 403, { error: 'EXPERIMENT_UNAVAILABLE' });
      return;
    }
    const range = safeByteRange(req.headers.range);
    if (range === false) {
      reply(res, 416, { error: 'INVALID_RANGE' });
      return;
    }

    const abort = new AbortController();
    const disconnect = () => abort.abort();
    res.once('close', disconnect);
    try {
      const client = await createClient();
      const info = await client.getBasicInfo(trackId);
      if (info?.playability_status?.status !== 'OK') {
        reply(res, 422, { error: 'UPSTREAM_NOT_PLAYABLE' });
        return;
      }
      const format = await client.getStreamingData(trackId, {
        type: 'audio',
        quality: 'best',
      });
      if (!format?.url || !safeAudioCdn(format.url)) {
        reply(res, 422, { error: 'AUDIO_FORMAT_UNAVAILABLE' });
        return;
      }
      const request = {
        headers: {
          'Accept-Encoding': 'identity',
          ...(range ? { Range: range } : {}),
        },
        signal: AbortSignal.any([abort.signal, AbortSignal.timeout(20000)]),
        redirect: 'error',
      };
      const upstream = await fetchAudio(format.url, request);
      if (!upstream?.body || ![200, 206].includes(upstream.status) ||
          (range !== null && upstream.status !== 206)) {
        await upstream?.body?.cancel().catch(() => {});
        reply(res, 502, { error: 'UPSTREAM_STREAM_UNAVAILABLE' });
        return;
      }
      const contentRange = upstream.headers.get('content-range');
      const contentLength = upstream.headers.get('content-length');
      const contentEncoding = upstream.headers.get('content-encoding');
      if ((contentEncoding && contentEncoding.toLowerCase() !== 'identity') ||
          (upstream.status === 206 &&
            !validUpstreamRange(range, contentRange, contentLength))) {
        await upstream.body.cancel();
        reply(res, 502, { error: 'INVALID_UPSTREAM_RANGE_OR_ENCODING' });
        return;
      }
      const upstreamMime = (upstream.headers.get('content-type') || '')
        .split(';')[0].toLowerCase().trim();
      const formatMime = (format.mime_type || '')
        .split(';')[0].toLowerCase().trim();
      // Never proxy HTML/JSON or video under an audio route.
      if (!upstreamMime.startsWith('audio/') &&
          !(upstreamMime === 'application/octet-stream' &&
            formatMime.startsWith('audio/'))) {
        await upstream.body.cancel();
        reply(res, 502, { error: 'UPSTREAM_NOT_AUDIO' });
        return;
      }
      const headers = {
        'Content-Type': upstreamMime === 'application/octet-stream'
          ? formatMime : upstreamMime,
        'Cache-Control': 'private, no-store, max-age=0',
        'X-Content-Type-Options': 'nosniff',
        'Accept-Ranges': 'bytes',
      };
      for (const name of ['content-length', 'content-range']) {
        const value = upstream.headers.get(name);
        if (value && /^\d+$/.test(value) && name === 'content-length') {
          headers[name] = value;
        }
        if (name === 'content-range' && value &&
            /^bytes \d+-\d+\/\d+$/.test(value)) headers[name] = value;
      }
      if (abort.signal.aborted || res.destroyed) {
        await upstream.body.cancel();
        return;
      }
      res.writeHead(upstream.status, headers);
      await pipeline(Readable.fromWeb(upstream.body), res);
    } catch {
      if (!res.headersSent && !res.destroyed) {
        reply(res, 502, { error: 'INNER_TUBE_UNAVAILABLE' });
      } else if (!res.destroyed) {
        res.destroy();
      }
    } finally {
      res.off('close', disconnect);
    }
  };
}
