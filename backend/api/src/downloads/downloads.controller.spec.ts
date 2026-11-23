import { DownloadsController } from './downloads.controller';

describe('DownloadsController trusted territory boundary', () => {
  const service = {
    authorizeAndRecord: jest.fn(),
    revalidateOfflineLease: jest.fn(),
  };
  let controller: DownloadsController;

  beforeEach(() => {
    jest.clearAllMocks();
    controller = new DownloadsController(service as any);
  });

  it('takes download authorization territory from the edge header, not the body', async () => {
    service.authorizeAndRecord.mockResolvedValue({ allowed: true });
    await controller.authorize('user-1', 'TZ', { trackId: 'track-1' });
    expect(service.authorizeAndRecord).toHaveBeenCalledWith('user-1', {
      trackId: 'track-1',
      territory: 'TZ',
    });
  });

  it('uses edge territory when revalidating an offline lease', async () => {
    service.revalidateOfflineLease.mockResolvedValue({ allowed: true });
    await controller.revalidate('user-1', 'KE', 'track-1');
    expect(service.revalidateOfflineLease).toHaveBeenCalledWith(
      'user-1',
      'track-1',
      'KE',
    );
  });
});
