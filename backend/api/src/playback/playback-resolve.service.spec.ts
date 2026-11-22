import {
  NotAcceptableException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from './media-signer.service';
import { ProviderRegistry } from '../providers/provider-registry.service';
import { PlaybackResolveService } from './playback-resolve.service';

describe('PlaybackResolveService', () => {
  const rights = { decide: jest.fn() };
  const signer = { createPlaybackUrl: jest.fn() };
  const prisma = {
    track: { findUnique: jest.fn() },
    contentTakedownCase: { findFirst: jest.fn() },
  };
  const providers = { get: jest.fn() };
  let service: PlaybackResolveService;

  const request = {
    trackId: 'track-1',
    territory: 'TZ',
    requestedQuality: 'AAC_256',
  };
  const providerRequest = {
    providerId: 'audius',
    providerTrackId: 'track123',
    canonicalTrackId: 'canonical-1',
    territory: 'TZ',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    service = new PlaybackResolveService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
      signer as unknown as MediaSigner,
      providers as unknown as ProviderRegistry,
    );
  });

  it('never signs a full playback URL for a preview-only grant', async () => {
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: true,
      reason: 'OK',
      qualityRestriction: null,
      expiresAt: new Date(Date.now() + 60_000),
      attribution: 'Licensed via label',
    });

    await expect(service.resolve('user-1', request)).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('does not sign a URL when rights are denied', async () => {
    rights.decide.mockResolvedValue({
      allowed: false,
      previewOnly: false,
      reason: 'NO_EXPLICIT_AUTHORIZATION',
      qualityRestriction: null,
      expiresAt: null,
      attribution: null,
    });

    await expect(service.resolve('user-1', request)).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('signs only an explicitly authorized full-stream variant', async () => {
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      reason: 'OK',
      qualityRestriction: 'AAC_128',
      expiresAt: null,
      attribution: 'Licensed via label',
    });
    signer.createPlaybackUrl.mockReturnValue({
      url: 'https://cdn.example/audio/signed',
      expiresAt: new Date(Date.now() + 60_000),
    });

    await expect(service.resolve('user-1', request)).resolves.toMatchObject({
      trackId: 'track-1',
      streamUrl: 'https://cdn.example/audio/signed',
      codec: 'aac',
      attribution: 'Licensed via label',
      previewOnly: false,
    });
    expect(signer.createPlaybackUrl).toHaveBeenCalledWith('track-1', 'AAC_128', null);
  });

  const validAdapter = () => ({
    capabilities: { playback: true, availability: true },
    getAvailability: jest.fn().mockResolvedValue({
      kind: 'ok',
      value: { available: true },
      attribution: 'Audius public catalogue',
    }),
    resolvePlayback: jest.fn().mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://api.audius.co/v1/tracks/track123/stream',
        expiresAt: new Date(Date.now() + 600_000),
        mimeType: 'audio/mpeg',
      },
      attribution: 'Audius public catalogue',
    }),
  });

  const prepareCanonicalTrack = () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'canonical-1',
      source: 'audius',
      externalId: 'bz:audius:track123',
    });
    prisma.contentTakedownCase.findFirst.mockResolvedValue(null);
  };

  it('rechecks provider availability before resolving a playback URL', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider(providerRequest)).resolves.toMatchObject({
      providerId: 'audius',
      providerTrackId: 'track123',
      streamUrl: 'https://api.audius.co/v1/tracks/track123/stream',
      attribution: 'Audius public catalogue',
    });
    expect(adapter.getAvailability).toHaveBeenCalledWith('track123', 'TZ');
    expect(adapter.resolvePlayback).toHaveBeenCalledWith(expect.objectContaining({
      providerTrackId: 'track123',
      canonicalTrackId: 'canonical-1',
      territory: 'TZ',
      authorization: expect.objectContaining({ action: 'stream.full' }),
    }));
  });

  it('rejects gated or unavailable provider tracks before resolving playback', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.getAvailability.mockResolvedValue({
      kind: 'ok',
      value: { available: false },
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(adapter.resolvePlayback).not.toHaveBeenCalled();
  });

  it('fails closed when provider availability cannot be verified', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.getAvailability.mockResolvedValue({
      kind: 'error',
      code: 'AUDIUS_AVAILABILITY_FAILED',
      retryable: true,
      message: 'Provider unavailable',
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(adapter.resolvePlayback).not.toHaveBeenCalled();
  });

  it('rejects provider playback when an active takedown exists', async () => {
    prepareCanonicalTrack();
    prisma.contentTakedownCase.findFirst.mockResolvedValue({ id: 'takedown-1' });
    providers.get.mockReturnValue(validAdapter());

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(providers.get).not.toHaveBeenCalled();
  });

  it('rejects a provider ID that does not match the canonical source mapping', async () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'canonical-1',
      source: 'youtube_music',
      externalId: 'bz:youtube_music:track123',
    });

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(prisma.contentTakedownCase.findFirst).not.toHaveBeenCalled();
    expect(providers.get).not.toHaveBeenCalled();
  });

  it('rejects an insecure URL returned by a provider adapter', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'http://example.com/audio',
        expiresAt: new Date(Date.now() + 600_000),
      },
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('rejects an expired provider URL', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://api.audius.co/v1/tracks/track123/stream',
        expiresAt: new Date(Date.now() - 1000),
      },
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider(providerRequest)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
