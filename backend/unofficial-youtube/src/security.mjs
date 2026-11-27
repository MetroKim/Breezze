import { timingSafeEqual } from 'node:crypto';

export const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
export const MAX_RANGE_NUMBER = 1_000_000_000_000;

export function experimentEnabled(env = process.env) {
  return env.BREEZZE_INNERTUBE_AUDIO_EXPERIMENT === 'true' &&
    env.NODE_ENV !== 'production' &&
    String(env.RAILWAY_ENVIRONMENT_NAME ?? '').toLowerCase() !== 'production';
}

export function allowlistedVideo(id, env = process.env) {
  return VIDEO_ID.test(id) &&
    (env.BREEZZE_AUDIO_TEST_ALLOWLIST || '')
      .split(',').map(x => x.trim()).filter(Boolean).includes(id);
}

export function validSecret(provided, configured = process.env.BREEZZE_INTERNAL_AUDIO_TEST_TOKEN) {
  if (typeof provided !== 'string' || typeof configured !== 'string' ||
      configured.length < 32) return false;
  const actual = Buffer.from(provided, 'utf8');
  const expected = Buffer.from(configured, 'utf8');
  if (actual.length !== expected.length) return false;
  return timingSafeEqual(actual, expected);
}

export function safeAudioCdn(raw) {
  try {
    const url = new URL(raw);
    return url.protocol === 'https:' && !url.username && !url.password &&
      !url.hash && (
        url.hostname === 'googlevideo.com' ||
        url.hostname.endsWith('.googlevideo.com')
      );
  } catch {
    return false;
  }
}

export function safeByteRange(range) {
  if (range == null) return null;
  const match = /^bytes=(\d{1,12})-(\d{0,12})$/.exec(range);
  if (!match) return false;
  const start = Number(match[1]);
  const end = match[2] === '' ? null : Number(match[2]);
  if (!Number.isSafeInteger(start) || start > MAX_RANGE_NUMBER ||
      (end !== null && (!Number.isSafeInteger(end) || end < start ||
      end > MAX_RANGE_NUMBER))) return false;
  return range;
}


/**
 * Strictly verify that upstream 206 bytes match the client's requested
 * seek range. Prevent returning the wrong segment or a misleading length.
 * No upstream-provided URL or playback token is returned to the client.
 */
export function validUpstreamRange(requestedRange, contentRange, contentLength) {
  if (typeof contentRange !== 'string') return false;
  const parsed = /^bytes (\d+)-(\d+)\/(\d+|\*)$/.exec(contentRange);
  if (!parsed) return false;
  const start = Number(parsed[1]);
  const end = Number(parsed[2]);
  const total = parsed[3] === '*' ? null : Number(parsed[3]);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
      start < 0 || end < start ||
      (total !== null && (!Number.isSafeInteger(total) || end >= total))) {
    return false;
  }
  if (requestedRange) {
    const request = /^bytes=(\d+)-(\d*)$/.exec(requestedRange);
    if (!request || start !== Number(request[1])) return false;
    if (request[2] !== '' && end > Number(request[2])) return false;
  }
  if (contentLength !== null) {
    if (!/^\d+$/.test(contentLength)) return false;
    const length = Number(contentLength);
    if (!Number.isSafeInteger(length) || length !== end - start + 1) return false;
  }
  return true;
}
