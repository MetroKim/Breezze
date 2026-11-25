import { isIP } from 'node:net';
import { NotAcceptableException, ServiceUnavailableException } from '@nestjs/common';
import type { ProviderPlaybackSource } from '../providers/provider-adapter.interface';

// Stream URLs are bearer credentials: never log or persist their query strings.
// Require a short usable lease so native players do not start with expiring URLs.
export const MIN_PROVIDER_STREAM_LEASE_MS = 15_000;

export function validateProviderAudioSource(
  source: ProviderPlaybackSource,
  rightsExpiresAt: Date | null,
  now: Date = new Date(),
): URL {
  let url: URL;
  try {
    url = new URL(source.url);
  } catch {
    throw new ServiceUnavailableException('PROVIDER_RETURNED_INVALID_URL');
  }

  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== 'https:' ||
    !host ||
    url.username !== '' ||
    url.password !== '' ||
    url.hash !== '' ||
    isIP(host) !== 0 ||
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host.endsWith('.internal')
  ) {
    throw new ServiceUnavailableException('PROVIDER_RETURNED_INVALID_SOURCE');
  }

  if (
    !(source.expiresAt instanceof Date) ||
    !Number.isFinite(source.expiresAt.getTime()) ||
    source.expiresAt.getTime() <= now.getTime() + MIN_PROVIDER_STREAM_LEASE_MS
  ) {
    throw new ServiceUnavailableException('PROVIDER_SOURCE_EXPIRES_TOO_SOON');
  }

  if (
    rightsExpiresAt !== null &&
    (!(rightsExpiresAt instanceof Date) ||
      !Number.isFinite(rightsExpiresAt.getTime()) ||
      source.expiresAt.getTime() > rightsExpiresAt.getTime())
  ) {
    throw new NotAcceptableException('PROVIDER_GRANT_OUTLIVES_RIGHTS');
  }

  // Native audio, HLS and DASH are allowed. Video-only responses are not
  // an audio playback grant, even if a provider mistakenly advertises one.
  if (source.mimeType) {
    const mime = source.mimeType.split(';', 1)[0].trim().toLowerCase();
    if (
      !mime.startsWith('audio/') &&
      mime !== 'application/vnd.apple.mpegurl' &&
      mime !== 'application/x-mpegurl' &&
      mime !== 'application/dash+xml'
    ) {
      throw new ServiceUnavailableException('PROVIDER_RETURNED_NON_AUDIO_SOURCE');
    }
  }

  return url;
}
