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
      configured.length < 32 || provided.length !== configured.length) return false;
  return timingSafeEqual(Buffer.from(provided), Buffer.from(configured));
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
