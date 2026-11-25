import { isIP } from 'node:net';
import { ServiceUnavailableException, NotFoundException } from '@nestjs/common';

export interface MediaProbeOptions {
  /** Explicitly test the production check without enabling production mode. */
  force?: boolean;
  expectedOrigin?: string;
  request?: typeof fetch;
  mediaKind?: 'audio' | 'video';
}

/**
 * A valid media signature is not enough: the actual R2 audio object must
 * exist. Validate one signed Breezze CDN URL by asking our Worker for HEAD.
 *
 * Production always fails closed. No third-party URL or untrusted redirect
 * is followed and signed bearer URLs never appear in error messages/logs.
 */
export async function inspectSignedMediaObject(
  signedUrl: string,
  options: MediaProbeOptions = {},
): Promise<{ mimeType: string; sizeBytes: number } | null> {
  if (process.env.NODE_ENV !== 'production' && options.force !== true) return null;

  const base = options.expectedOrigin ?? process.env.CDN_BASE_URL;
  if (!base) throw new ServiceUnavailableException('MEDIA_CDN_NOT_CONFIGURED');

  let target: URL;
  let expected: URL;
  try {
    target = new URL(signedUrl);
    expected = new URL(base);
  } catch {
    throw new ServiceUnavailableException('MEDIA_CDN_URL_INVALID');
  }

  const host = target.hostname.toLowerCase();
  if (
    target.protocol !== 'https:' ||
    expected.protocol !== 'https:' ||
    target.origin !== expected.origin ||
    !host ||
    host === 'localhost' ||
    host.endsWith('.local') ||
    host.endsWith('.internal') ||
    isIP(host) !== 0 ||
    target.username !== '' ||
    target.password !== '' ||
    target.hash !== '' ||
    !(options.mediaKind === 'video'
      ? /^\/video\/[0-9a-fA-F-]{36}\/(stream|download)$/.test(target.pathname)
      : /^\/audio\/[A-Za-z0-9_-]{1,128}\/[A-Za-z0-9_-]{1,32}$/.test(target.pathname)) ||
    !target.searchParams.has('e') ||
    !target.searchParams.has('s')
  ) {
    throw new ServiceUnavailableException('MEDIA_CDN_URL_INVALID');
  }

  let response: Response;
  try {
    response = await (options.request ?? fetch)(target.toString(), {
      method: 'HEAD',
      signal: AbortSignal.timeout(4_000),
      redirect: 'error',
      // CDN response is private/no-store; signed capabilities are never shared.
    });
  } catch {
    throw new ServiceUnavailableException('MEDIA_CDN_HEAD_UNAVAILABLE');
  }

  if (response.status === 404) {
    throw new NotFoundException('LICENSED_MEDIA_ASSET_NOT_INGESTED');
  }
  if (response.status !== 200) {
    throw new ServiceUnavailableException('MEDIA_CDN_HEAD_FAILED');
  }

  const length = Number(response.headers.get('content-length'));
  const mime = (response.headers.get('content-type') ?? '').split(';', 1)[0].trim().toLowerCase();
  const mediaMatches = options.mediaKind === 'video'
    ? mime === 'video/mp4'
    : mime.startsWith('audio/') ||
      mime === 'application/vnd.apple.mpegurl' ||
      mime === 'application/x-mpegurl' ||
      mime === 'application/dash+xml';
  if (!Number.isSafeInteger(length) || length < 1 || !mediaMatches) {
    throw new ServiceUnavailableException('MEDIA_CDN_INVALID_AUDIO_OBJECT');
  }
  return { mimeType: mime, sizeBytes: length };
}

/** Legacy no-metadata wrapper used by playback grants and existing tests. */
export async function verifySignedMediaObject(
  signedUrl: string,
  options: MediaProbeOptions = {},
): Promise<void> {
  await inspectSignedMediaObject(signedUrl, options);
}

/** R2 readiness gate for one owned MP4; never probes public YouTube URLs. */
export async function inspectSignedVideoObject(
  signedUrl: string,
  options: MediaProbeOptions = {},
): Promise<{ mimeType: string; sizeBytes: number } | null> {
  return inspectSignedMediaObject(signedUrl, { ...options, mediaKind: 'video' });
}
