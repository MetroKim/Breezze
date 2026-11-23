import { LyricsController } from './lyrics.controller';

describe('LyricsController trusted territory boundary', () => {
  const service = {
    getLyrics: jest.fn(),
    getTranslations: jest.fn(),
  };
  let controller: LyricsController;

  beforeEach(() => {
    jest.clearAllMocks();
    controller = new LyricsController(service as any);
  });

  it('uses only the trusted edge country for lyric rights decisions', async () => {
    service.getLyrics.mockResolvedValue({ trackId: 'track-1' });
    await controller.getLyrics('user-1', 'tz', { trackId: 'track-1' });
    expect(service.getLyrics).toHaveBeenCalledWith('user-1', {
      trackId: 'track-1',
      territory: 'TZ',
    });
  });

  it('fails closed when the edge country is unavailable', () => {
    expect(() => controller.getLyrics('user-1', undefined, {
      trackId: 'track-1',
    })).toThrow('LYRICS_TERRITORY_UNAVAILABLE');
    expect(service.getLyrics).not.toHaveBeenCalled();
  });

  it('uses the trusted edge country for translation rights decisions', async () => {
    service.getTranslations.mockResolvedValue([]);
    await controller.translations('user-1', 'KE', {
      lyricsId: 'lyrics-1',
      language: 'sw',
    });
    expect(service.getTranslations).toHaveBeenCalledWith(
      'user-1',
      'lyrics-1',
      'KE',
      'sw',
    );
  });
});
