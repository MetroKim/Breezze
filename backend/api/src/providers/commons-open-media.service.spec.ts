import { BadRequestException } from '@nestjs/common';
import { CommonsOpenMediaService } from './commons-open-media.service';

describe('CommonsOpenMediaService — no server audio storage', () => {
  let service: CommonsOpenMediaService;
  let response: jest.SpyInstance;
  const previous = process.env.BREEZZE_OPEN_MEDIA_ENABLED;
  const validAudio = {
    title: 'File:Example song.mp3',
    imageinfo: [{
      url: 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_song.mp3',
      mime: 'audio/mpeg', size: 1048576,
      extmetadata: {
        LicenseUrl: { value: 'https://creativecommons.org/licenses/by/4.0/' },
        Artist: { value: '<a href="https://example.org">A &amp; B</a>' },
      },
    }],
  };
  beforeEach(() => {
    jest.restoreAllMocks();
    process.env.BREEZZE_OPEN_MEDIA_ENABLED = 'true';
    service = new CommonsOpenMediaService();
    response = jest.spyOn(global, 'fetch').mockResolvedValue(new Response(
      JSON.stringify({ query: { pages: [validAudio] } }), {
        status: 200, headers: { 'content-type': 'application/json' },
      },
    ));
  });
  afterAll(() => {
    if (previous === undefined) delete process.env.BREEZZE_OPEN_MEDIA_ENABLED;
    else process.env.BREEZZE_OPEN_MEDIA_ENABLED = previous;
  });

  it('is opt-in and does not use the provider at all when disabled', async () => {
    delete process.env.BREEZZE_OPEN_MEDIA_ENABLED;
    await expect(service.search('example', 'audio')).resolves.toEqual({
      provider: 'wikimedia_commons', enabled: false, items: [],
    });
    expect(response).not.toHaveBeenCalled();
  });

  it('searches full-file audio and reports a direct listener-device download, not R2', async () => {
    const result = await service.search('Example song', 'audio');
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      provider: 'wikimedia_commons', kind: 'audio', downloadAllowed: true,
      saveTarget: 'listener_device', license: 'CC BY 4.0', fullLengthVerified: false,
      creator: 'A & B',
      streamUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_song.mp3',
      downloadUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_song.mp3',
    });
    const request = new URL(response.mock.calls[0][0] as string);
    expect(request.hostname).toBe('commons.wikimedia.org');
    expect(request.searchParams.get('gsrsearch')).toBe('Example song filetype:audio');
    expect(request.searchParams.get('gsrnamespace')).toBe('6');
  });

  it('accepts actual Commons Ogg audio MIME, media kind, URL UTM tags and duration', async () => {
    response.mockResolvedValue(new Response(JSON.stringify({
      query: { pages: [{
        title: 'File:Beethoven Prometheus Creatures.oga',
        imageinfo: [{
          url: 'https://upload.wikimedia.org/wikipedia/commons/b/b1/Beethoven_Prometheus_Creatures.oga?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=original',
          mime: 'application/ogg',
          mediatype: 'AUDIO',
          duration: 292.596,
          size: 8207409,
          extmetadata: {
            LicenseUrl: { value: 'https://creativecommons.org/licenses/by-sa/2.0' },
            Artist: { value: 'Ludwig van Beethoven' },
          },
        }],
      }] },
    })));
    const result = await service.search('Beethoven', 'audio');
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      mimeType: 'application/ogg', durationSec: 292.596,
      downloadAllowed: true, saveTarget: 'listener_device',
      streamUrl: 'https://upload.wikimedia.org/wikipedia/commons/b/b1/Beethoven_Prometheus_Creatures.oga',
      license: 'CC BY-SA 2.0',
    });
    const request = new URL(response.mock.calls[0][0] as string);
    expect(request.searchParams.get('iiprop')).toContain('mediatype');
  });

  it('rejects suspicious Commons URL query parameters and misclassified Ogg video', async () => {
    const audio = {
      title: 'File:Not real audio.ogg',
      imageinfo: [{
        mime: 'application/ogg', mediatype: 'VIDEO', size: 1024,
        url: 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Not_real_audio.ogg',
        extmetadata: {
          LicenseUrl: { value: 'https://creativecommons.org/licenses/by/4.0/' },
        },
      }],
    };
    response.mockResolvedValue(new Response(JSON.stringify({
      query: { pages: [audio] },
    })));
    await expect(service.search('Not real audio', 'audio'))
      .resolves.toMatchObject({ items: [] });

    response.mockResolvedValue(new Response(JSON.stringify({
      query: { pages: [{
        ...audio,
        imageinfo: [{
          ...audio.imageinfo[0],
          mediatype: 'AUDIO',
          url: audio.imageinfo[0].url + '?redirect=https://attacker.example/media',
        }],
      }] },
    })));
    await expect(service.search('Not real audio', 'audio'))
      .resolves.toMatchObject({ items: [] });
  });

  it('resolves an available CC0 video file and checks its license again', async () => {
    response.mockResolvedValue(new Response(JSON.stringify({
      query: { pages: [{
        title: 'File:Public example.webm',
        imageinfo: [{
          url: 'https://upload.wikimedia.org/wikipedia/commons/1/12/Public_example.webm',
          mime: 'video/webm', size: 8_000_000,
          extmetadata: {
            LicenseUrl: { value: 'https://creativecommons.org/publicdomain/zero/1.0/' },
          },
        }],
      }] },
    })));
    await expect(service.resolve('File:Public example.webm', 'video'))
      .resolves.toMatchObject({
        kind: 'video', downloadAllowed: true, license: 'CC0 1.0',
        sourcePage: expect.stringContaining('commons.wikimedia.org/wiki/'),
      });
    expect(response).toHaveBeenCalledTimes(1);
  });

  it('rejects restricted, unknown, and incomplete copyright grants', async () => {
    for (const grant of [
      'https://creativecommons.org/licenses/by-nc/4.0/',
      'https://example.com/pseudo-license',
      '',
    ]) {
      response.mockResolvedValue(new Response(JSON.stringify({
        query: { pages: [{
          ...validAudio,
          imageinfo: [{
            ...validAudio.imageinfo[0],
            extmetadata: { LicenseUrl: { value: grant } },
          }],
        }] },
      })));
      const result = await service.search('Example song', 'audio');
      expect(result.items).toEqual([]);
    }
  });

  it('rejects third-party media hosts even when API metadata claims CC0', async () => {
    response.mockResolvedValue(new Response(JSON.stringify({
      query: { pages: [{
        ...validAudio,
        imageinfo: [{
          ...validAudio.imageinfo[0],
          url: 'https://bad.example.org/song.mp3',
        }],
      }] },
    })));
    await expect(service.resolve('File:Example song.mp3', 'audio'))
      .rejects.toThrow('OPEN_MEDIA_FILE_UNAVAILABLE');
  });

  it('does not allow arbitrary file titles, kind injection or search syntax', async () => {
    await expect(service.resolve('https://bad.example/file.mp3', 'audio'))
      .rejects.toBeInstanceOf(BadRequestException);
    await expect(service.search('x AND filetype:video', 'audio'))
      .rejects.toBeInstanceOf(BadRequestException);
    await expect(service.search('Example song', '../video'))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(response).not.toHaveBeenCalled();
  });

  it('fails closed when a requested media type differs from the file MIME', async () => {
    await expect(service.resolve('File:Example song.mp3', 'video'))
      .rejects.toThrow('OPEN_MEDIA_FILE_UNAVAILABLE');
  });
});
