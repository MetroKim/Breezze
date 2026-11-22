import { GUARDS_METADATA } from '@nestjs/common/constants';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CatalogService } from './catalog.service';
import { CatalogController } from './catalog.controller';

describe('CatalogController', () => {
  it('requires authentication before creating or mapping catalog tracks', () => {
    const guards = Reflect.getMetadata(
      GUARDS_METADATA,
      CatalogController.prototype.resolve,
    );

    expect(guards).toContain(JwtAuthGuard);
  });

  it('delegates catalog convergence to CatalogService', async () => {
    const track = { id: 'catalog-track-1' };
    const catalog = { resolve: jest.fn().mockResolvedValue(track) };
    const controller = new CatalogController(
      catalog as unknown as CatalogService,
    );
    const dto = {
      externalId: 'bz:video-1',
      source: 'youtube',
      title: 'Track title',
      artistName: 'Artist',
      durationSec: 180,
    };

    await expect(controller.resolve(dto)).resolves.toBe(track);
    expect(catalog.resolve).toHaveBeenCalledWith(dto);
  });

  it('passes normalized trusted edge territory to public catalogue reads', async () => {
    const catalog = {
      song: jest.fn().mockResolvedValue({ id: 'track-1' }),
      album: jest.fn(),
      artist: jest.fn(),
    };
    const controller = new CatalogController(catalog as unknown as CatalogService);
    await controller.song('track-1', 'tz');
    expect(catalog.song).toHaveBeenCalledWith('track-1', 'TZ');
  });

  it('fails closed when the trusted edge country is missing', () => {
    const catalog = { song: jest.fn(), album: jest.fn(), artist: jest.fn() };
    const controller = new CatalogController(catalog as unknown as CatalogService);
    expect(() => controller.album('album-1', undefined))
      .toThrow('CATALOG_TERRITORY_UNAVAILABLE');
    expect(catalog.album).not.toHaveBeenCalled();
  });

});
