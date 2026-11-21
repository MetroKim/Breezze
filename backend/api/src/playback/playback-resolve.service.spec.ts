import { NotAcceptableException } from '@nestjs/common';
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
  it('resolves an enabled provider source without accepting a client-supplied URL', async () => {
    prisma.track.findUnique.mockResolvedValue({
      id: 'canonical-1',
      source: 'audius',
      externalId: 'bz:audius:track123',
    });
    prisma.contentTakedownCase.findFirst.mockResolvedValue(null);
    const adapter = {
      capabilities: { playback: true },
      resolvePlayback: jest.fn().mockResolvedValue({
        kind: 'ok',
        value: {
          url: 'https://api.audius.co/v1/tracks/track123/stream',
          expiresAt: new Date(Date.now() + 600_000),
          mimeType: 'audio/mpeg',
        },
        attribution: 'Audius public catalogue',
      }),
    };
    providers.get.mockReturnValue(adapter);

    await expect(service.resolveProvider({
      providerId: 'audius',
      providerTrackId: 'track123',
      canonicalTrackId: 'canonical-1',
      territory: 'TZ',
    })).resolves.toMatchObject({
      providerId: 'audius',
      providerTrackId: 'track123',
      streamUrl: 'https://api.audius.co/v1/tracks/track123/stream',
    });
    expect(adapter.resolvePlayback).toHaveBeenCalled();
  });

});
