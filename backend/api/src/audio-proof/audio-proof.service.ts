import { Injectable, NotFoundException } from '@nestjs/common';

/**
 * A real, rights-cleared media acceptance track. Not an unofficial YouTube
 * recording, and NOT a general-purpose streaming rights grant.
 *
 * Recording: Promise — Keith Adler (public-domain dedication / PD-self).
 * Attribution/rights: https://commons.wikimedia.org/wiki/File:Promise.ogg
 * Wikimedia's official MP3 transcode is verified live in CI.
 */
export const PUBLIC_AUDIO_PROOF_ID = 'bz:public_domain:promise';
export const PUBLIC_AUDIO_PROOF_SOURCE =
  'https://upload.wikimedia.org/wikipedia/commons/transcoded/1/1f/Promise.ogg/Promise.ogg.mp3';

export function audioProofEnabled(env = process.env): boolean {
  return env.BREEZZE_PUBLIC_AUDIO_PROOF === 'true' &&
    env.NODE_ENV !== 'production' &&
    (env.RAILWAY_ENVIRONMENT_NAME ?? '').toLowerCase() !== 'production';
}

@Injectable()
export class AudioProofService {
  private ensureAvailable(): void {
    if (!audioProofEnabled()) {
      throw new NotFoundException('AUDIO_PROOF_DISABLED');
    }
  }

  track() {
    this.ensureAvailable();
    return {
      source: 'wikimedia_commons',
      id: PUBLIC_AUDIO_PROOF_ID,
      title: 'Promise',
      artist: 'Keith Adler',
      durationSec: 148,
      artworkUrl: null,
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Promise.ogg',
      license: 'Public domain (PD-self)',
      licenseUrl: 'https://commons.wikimedia.org/wiki/File:Promise.ogg#Licensing',
      fullTrack: true,
      offlineAllowed: false,
      experimental: true,
    };
  }

  playback() {
    const track = this.track();
    return {
      ...track,
      streamUrl: PUBLIC_AUDIO_PROOF_SOURCE,
      codec: 'mp3',
      mimeType: 'audio/mpeg',
      // Freshness/revalidation horizon, not a fabricated provider signed lease.
      expiresAt: new Date(Date.now() + 15 * 60_000).toISOString(),
    };
  }
}
