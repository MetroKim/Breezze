import { NotAcceptableException } from '@nestjs/common';
import { AuthorizedAudioCatalogController } from './authorized-audio-catalog.controller';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';

const licensed = {
  id: 'e85df20d-45f8-4a40-a271-e00b314a47d7',
  source: 'opensubsonic',
  externalId: 'bz:opensubsonic:original-song',
  title: 'Original Full Track',
  duration: 218,
  artist: { name: 'Licensed Artist' },
};
const unlicensed = {
  ...licensed,
  id: 'a85df20d-45f8-4a40-a271-e00b314a47d7',
  externalId: 'bz:opensubsonic:unlicensed-song',
};

function setup({ enabled = true, rows = [licensed, unlicensed],
  grants = [licensed.id], available = true } = {}) {
  const prisma = {
    track: { findMany: jest.fn().mockResolvedValue(rows) },
  };
  const rights = {
    filterFullStream: jest.fn().mockResolvedValue(new Set(grants)),
  };
  const source = {
    enabled,
    getAvailability: jest.fn().mockResolvedValue({
      kind: 'ok', value: { available },
    }),
  };
  return {
    prisma, rights, source,
    controller: new AuthorizedAudioCatalogController(
      prisma as unknown as PrismaService,
      rights as unknown as RightsDecisionService,
      source as unknown as OpenSubsonicAdapter,
    ),
  };
}

describe('V8 rights-checked full-song search', () => {
  it('never exposes partner metadata when provider is disabled', async () => {
    const { controller, prisma, rights, source } = setup({ enabled: false });
    expect(await controller.search('Original', 'TZ')).toEqual({ items: [] });
    expect(prisma.track.findMany).not.toHaveBeenCalled();
    expect(rights.filterFullStream).not.toHaveBeenCalled();
    expect(source.getAvailability).not.toHaveBeenCalled();
  });

  it('rejects untrusted or absent edge territory before database search', async () => {
    const { controller, prisma } = setup();
    await expect(controller.search('Original')).rejects.toBeInstanceOf(NotAcceptableException);
    await expect(controller.search('Original', 'ZZZ')).rejects.toBeInstanceOf(NotAcceptableException);
    expect(prisma.track.findMany).not.toHaveBeenCalled();
  });

  it('does not leak unlicensed artist/song rows or issue a stream URL', async () => {
    const { controller, rights, source } = setup();
    const result = await controller.search('Original', 'TZ');
    expect(rights.filterFullStream).toHaveBeenCalledWith(
      [licensed.id, unlicensed.id], 'TZ',
    );
    expect(result.items).toEqual([{
      providerId: 'opensubsonic',
      providerTrackId: 'original-song',
      canonicalTrackId: licensed.id,
      title: 'Original Full Track',
      artist: 'Licensed Artist',
      durationSec: 218,
    }]);
    expect(source.getAvailability).toHaveBeenCalledTimes(1);
    expect(source.getAvailability).toHaveBeenCalledWith('original-song', 'TZ');
    expect(JSON.stringify(result)).not.toContain('unlicensed-song');
    expect(JSON.stringify(result)).not.toMatch(/streamUrl|apiKey|grant/);
  });

  it('hides rights-approved catalog rows if actual upstream audio is unavailable', async () => {
    const { controller } = setup({ available: false });
    expect(await controller.search('Original', 'TZ')).toEqual({ items: [] });
  });

  it('accepts only canonical namespaced partner IDs, never arbitrary media URLs', async () => {
    const { controller, source } = setup({ rows: [{
      ...licensed, externalId: 'https://other.example/file.mp3',
    }] });
    expect(await controller.search('Original', 'TZ')).toEqual({ items: [] });
    expect(source.getAvailability).not.toHaveBeenCalled();
  });

  it('rejects empty or oversized queries without searching private catalog', async () => {
    const { controller, prisma } = setup();
    expect(await controller.search('x', 'TZ')).toEqual({ items: [] });
    expect(await controller.search('a'.repeat(121), 'TZ')).toEqual({ items: [] });
    expect(prisma.track.findMany).not.toHaveBeenCalled();
  });
});
