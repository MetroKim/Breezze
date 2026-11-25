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
    audioAssetVariant: { findMany: jest.fn() },
  };
  const providers = { get: jest.fn() };
  let service: PlaybackResolveService;

  const request = {
    trackId: 'track-1',
    requestedQuality: 'AAC_256',
    territory: 'US', // Deliberately spoofed; only the edge header is trusted.
  };
  const providerRequest = {
    providerId: 'licensed_partner',
    providerTrackId: 'track123',
    canonicalTrackId: 'canonical-1',
    territory: 'US', // Deliberately spoofed; only the edge header is trusted.
  };

  beforeEach(() => {
    jest.clearAllMocks();
    // Native signed media paths can only be used by Breezze-owned assets.
    prisma.track.findUnique.mockResolvedValue({ id: 'track-1', source: 'breezze_internal' });
    prisma.audioAssetVariant.findMany.mockResolvedValue([
      { quality: 'AAC_128', mimeType: 'audio/mp4', sizeBytes: 1024n },
      { quality: 'AAC_256', mimeType: 'audio/mp4', sizeBytes: 2048n },
    ]);
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      reason: 'OK',
      qualityRestriction: null,
      expiresAt: null,
      attribution: 'Licensed full-track grant',
    });
    service = new PlaybackResolveService(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
      signer as unknown as MediaSigner,
      providers as unknown as ProviderRegistry,
    );
  });

  it('fails closed when the trusted edge cannot determine a playback territory', async () => {
    await expect(service.resolve('user-1', request)).rejects.toThrow('PLAYBACK_TERRITORY_UNAVAILABLE');
    expect(rights.decide).not.toHaveBeenCalled();
  });

  it('rejects unknown canonical track IDs before granting a signed media URL', async () => {
    prisma.track.findUnique.mockResolvedValue(null);
    await expect(service.resolve('user-1', request, 'TZ')).rejects.toThrow('TRACK_NOT_FOUND');
    expect(rights.decide).not.toHaveBeenCalled();
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it.each(['youtube_music', 'deezer'])(
    'does not self-grant native audio for metadata-only %s catalog assets',
    async (source) => {
      prisma.track.findUnique.mockResolvedValue({ id: 'track-1', source });
      // Deliberately simulate a mistaken database rights row: it must not
      // turn third-party catalog metadata into a Breezze-hosted audio file.
      await expect(service.resolve('user-1', request, 'TZ'))
        .rejects.toThrow('USE_PROVIDER_PLAYBACK_RESOLVER');
      expect(rights.decide).not.toHaveBeenCalled();
      expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
    },
  );

  it.each(['licensed_partner', 'soundcloud', 'audius', 'unapproved_catalog'])(
    'never signs external metadata from provider %s as an internal R2 asset',
    async (source) => {
      prisma.track.findUnique.mockResolvedValue({
        id: 'track-1',
        source,
        externalId: 'bz:' + source + ':recording-1',
      });
      await expect(service.resolve('user-1', request, 'TZ'))
        .rejects.toThrow('USE_PROVIDER_PLAYBACK_RESOLVER');
      expect(rights.decide).not.toHaveBeenCalled();
      expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
    },
  );

  it('rejects legacy tracks carrying an external ID but no source', async () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'track-1', source: null, externalId: 'bz:youtube_music:dQw4w9WgXcQ',
    });
    await expect(service.resolve('user-1', request, 'TZ'))
      .rejects.toThrow('USE_PROVIDER_PLAYBACK_RESOLVER');
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
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

    await expect(service.resolve('user-1', request, 'TZ')).rejects.toBeInstanceOf(
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

    await expect(service.resolve('user-1', request, 'TZ')).rejects.toBeInstanceOf(
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

    await expect(service.resolve('user-1', request, 'TZ')).resolves.toMatchObject({
      trackId: 'track-1',
      streamUrl: 'https://cdn.example/audio/signed',
      codec: 'aac',
      attribution: 'Licensed via label',
      previewOnly: false,
    });
    expect(rights.decide).toHaveBeenCalledWith({
      userId: 'user-1', trackId: 'track-1', action: 'stream.full', territory: 'TZ',
    });
    expect(signer.createPlaybackUrl).toHaveBeenCalledWith('track-1', 'AAC_128', null);
  });

  it('rejects authorized track metadata when no verified media variant is ready', async () => {
    prisma.audioAssetVariant.findMany.mockResolvedValue([]);
    await expect(service.resolve('user-1', request, 'TZ'))
      .rejects.toThrow('LICENSED_AUDIO_VARIANT_NOT_READY');
    expect(signer.createPlaybackUrl).not.toHaveBeenCalled();
  });

  it('downgrades to the best available verified asset without signing a missing quality', async () => {
    prisma.audioAssetVariant.findMany.mockResolvedValue([
      { quality: 'AAC_128', mimeType: 'audio/mp4', sizeBytes: 1024n },
    ]);
    signer.createPlaybackUrl.mockReturnValue({
      url: 'https://cdn.example/audio/signed',
      expiresAt: new Date(Date.now() + 60_000),
    });
    await expect(service.resolve('user-1', request, 'TZ')).resolves.toMatchObject({
      quality: 'AAC_128', codec: 'aac',
    });
    expect(signer.createPlaybackUrl).toHaveBeenCalledWith('track-1', 'AAC_128', null);
  });

  const validAdapter = () => ({
    capabilities: { playback: true, availability: true },
    getAvailability: jest.fn().mockResolvedValue({
      kind: 'ok',
      value: { available: true },
      attribution: 'Approved label',
    }),
    resolvePlayback: jest.fn().mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://media.licensed.example/audio/track123',
        expiresAt: new Date(Date.now() + 600_000),
        mimeType: 'audio/mpeg',
      },
      attribution: 'Approved label',
    }),
  });

  const prepareCanonicalTrack = () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'canonical-1',
      source: 'licensed_partner',
      externalId: 'bz:licensed_partner:track123',
    });
    prisma.contentTakedownCase.findFirst.mockResolvedValue(null);
  };

  it('rechecks provider availability before resolving a playback URL', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).resolves.toMatchObject({
      providerId: 'licensed_partner',
      providerTrackId: 'track123',
      streamUrl: 'https://media.licensed.example/audio/track123',
      attribution: 'Licensed full-track grant',
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

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(adapter.resolvePlayback).not.toHaveBeenCalled();
  });

  it('fails closed when provider availability cannot be verified', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.getAvailability.mockResolvedValue({
      kind: 'error',
      code: 'PROVIDER_AVAILABILITY_FAILED',
      retryable: true,
      message: 'Provider unavailable',
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(adapter.resolvePlayback).not.toHaveBeenCalled();
  });

  it('rejects provider playback when an active takedown exists', async () => {
    prepareCanonicalTrack();
    prisma.contentTakedownCase.findFirst.mockResolvedValue({ id: 'takedown-1' });
    providers.get.mockReturnValue(validAdapter());

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
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

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
      NotAcceptableException,
    );
    expect(prisma.contentTakedownCase.findFirst).not.toHaveBeenCalled();
    expect(providers.get).not.toHaveBeenCalled();
  });

  it('rejects provider grants that expire during native player startup', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://media.licensed.example/audio/track123',
        expiresAt: new Date(Date.now() + 5_000),
        mimeType: 'audio/mpeg',
      },
    });
    providers.get.mockReturnValue(adapter);
    await expect(service.resolveProvider('user-1', providerRequest, 'TZ'))
      .rejects.toThrow('PROVIDER_SOURCE_EXPIRES_TOO_SOON');
  });

  it('never supplies video or HTML URLs to the native audio engine', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://media.licensed.example/watch',
        expiresAt: new Date(Date.now() + 60_000),
        mimeType: 'text/html',
      },
    });
    providers.get.mockReturnValue(adapter);
    await expect(service.resolveProvider('user-1', providerRequest, 'TZ'))
      .rejects.toThrow('PROVIDER_RETURNED_NON_AUDIO_SOURCE');
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

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('rejects an expired provider URL', async () => {
    prepareCanonicalTrack();
    const adapter = validAdapter();
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://media.licensed.example/audio/track123',
        expiresAt: new Date(Date.now() - 1000),
      },
    });
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
  it('denies unlicensed providers before lookup when no full-stream grant exists', async () => {
    prepareCanonicalTrack();
    prisma.track.findUnique.mockResolvedValue({
      id: 'canonical-1',
      source: 'licensed_partner',
      externalId: 'bz:licensed_partner:track123',
    });
    rights.decide.mockResolvedValue({
      allowed: false,
      previewOnly: false,
      reason: 'NO_EXPLICIT_AUTHORIZATION',
    });
    providers.get.mockReturnValue(validAdapter());

    await expect(service.resolveProvider('user-1', {
      ...providerRequest, providerId: 'licensed_partner',
    }, 'TZ')).rejects.toThrow('NO_EXPLICIT_AUTHORIZATION');
    expect(rights.decide).toHaveBeenCalledWith({
      userId: 'user-1',
      trackId: 'canonical-1',
      territory: 'TZ',
      action: 'stream.full',
    });
    expect(providers.get).not.toHaveBeenCalled();
  });

  it('refuses full provider audio even if a preview grant is active', async () => {
    prepareCanonicalTrack();
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: true,
      reason: 'OK',
    });
    providers.get.mockReturnValue(validAdapter());

    await expect(service.resolveProvider('user-1', providerRequest, 'TZ'))
      .rejects.toThrow('PREVIEW_ONLY');
    expect(providers.get).not.toHaveBeenCalled();
  });

  it('passes canonical full-stream rights expiry and attribution to provider', async () => {
    prepareCanonicalTrack();
    const expiresAt = new Date(Date.now() + 60_000);
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      reason: 'OK',
      expiresAt,
      attribution: 'Explicit license',
    });
    const adapter = validAdapter();
    // The successful fixture must not outlive the license: a longer
    // provider URL is now correctly rejected by the production resolver.
    adapter.resolvePlayback.mockResolvedValue({
      kind: 'ok',
      value: {
        url: 'https://media.licensed.example/audio/track123',
        expiresAt: new Date(Date.now() + 30_000),
        mimeType: 'audio/mpeg',
      },
      attribution: 'Approved label',
    });
    providers.get.mockReturnValue(adapter);

    await service.resolveProvider('user-1', providerRequest, 'TZ');
    expect(adapter.resolvePlayback).toHaveBeenCalledWith(expect.objectContaining({
      authorization: {
        action: 'stream.full',
        expiresAt,
        attribution: 'Explicit license',
      },
    }));
  });

  it('rejects provider URLs that outlive the explicit full-track license', async () => {
    prepareCanonicalTrack();
    rights.decide.mockResolvedValue({
      allowed: true,
      previewOnly: false,
      reason: 'OK',
      expiresAt: new Date(Date.now() + 30_000),
      attribution: 'Short license',
    });
    providers.get.mockReturnValue(validAdapter());
    await expect(service.resolveProvider('user-1', providerRequest, 'TZ'))
      .rejects.toThrow('PROVIDER_GRANT_OUTLIVES_RIGHTS');
  });

});
