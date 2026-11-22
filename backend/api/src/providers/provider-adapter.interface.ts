import { ProviderResult } from './provider-result';

// Plan §7.2 — a provider must declare its identity, capabilities, and
// the metadata operations it supports. Playback resolution is only
// implemented by providers that explicitly authorize it.
export interface ProviderCapabilities {
  search: boolean;
  metadata: boolean;
  availability: boolean;
  playback: boolean;
  download: boolean;
  albums?: boolean;
  artists?: boolean;
  playlists?: boolean;
  videos?: boolean;
  charts?: boolean;
  genres?: boolean;
  moods?: boolean;
  radio?: boolean;
  lyrics?: boolean;
}

export interface ProviderPlaybackRequest {
  canonicalTrackId?: string;
  providerTrackId: string;
  territory: string;
  requestedQuality?: string;
  authorization: {
    action: 'stream.full';
    expiresAt: Date | null;
    attribution: string | null;
  };
}

export interface ProviderPlaybackSource {
  url: string;
  expiresAt: Date;
  mimeType?: string;
  codec?: string;
  bitrateKbps?: number;
  sampleRateHz?: number;
  bitDepth?: number;
}

export interface ProviderTrack {
  providerTrackId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  sourceUrl?: string;
  durationSec?: number;
}

export interface ProviderAdapter {
  readonly providerId: string;
  readonly capabilities: ProviderCapabilities;
  readonly adapterVersion?: string;
  readonly displayName?: string;
  readonly priority?: number;
  readonly enabled?: boolean;

  search(query: string): Promise<ProviderResult<ProviderTrack[]>>;

  getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>>;

  getAvailability(
    providerTrackId: string,
    territory: string,
  ): Promise<ProviderResult<{ available: boolean }>>;

  /** Called only by the backend after a successful rights decision. */
  resolvePlayback(
    request: ProviderPlaybackRequest,
  ): Promise<ProviderResult<ProviderPlaybackSource>>;
}
