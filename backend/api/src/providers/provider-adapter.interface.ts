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
}

export interface ProviderTrack {
  providerTrackId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  durationSec?: number;
}

/**
 * A launch descriptor is not a stream URL or a playback entitlement.
 * It points the client to the provider's own official player.
 */
export interface ProviderPlaybackLaunch {
  mode: 'external_official_player';
  providerId: string;
  providerTrackId: string;
  watchUrl: string;
  embedUrl: string;
  requiresUserGesture: true;
  supportsBackgroundAudio: false;
  supportsNativeQueueControls: false;
}

export interface ProviderAdapter {
  readonly providerId: string;
  readonly capabilities: ProviderCapabilities;

  search(query: string): Promise<ProviderResult<ProviderTrack[]>>;

  getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>>;

  getAvailability(
    providerTrackId: string,
    territory: string,
  ): Promise<ProviderResult<{ available: boolean }>>;

  /** Optional provider-owned player handoff; never returns extracted media URLs. */
  getPlaybackLaunch?(
    providerTrackId: string,
  ): ProviderResult<ProviderPlaybackLaunch>;
}
