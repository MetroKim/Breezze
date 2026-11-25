import { NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { verifySignedMediaObject } from './signed-media-presence';

const mediaUrl = 'https://media.breezze.example/audio/track-1/AAC_256?e=9999999999999&s=signature';

describe('signed native media R2 existence guard', () => {
  const ok = (): Response => new Response(null, {
    status: 200,
    headers: { 'content-type': 'audio/mp4', 'content-length': '153600' },
  });
  const base = { force: true, expectedOrigin: 'https://media.breezze.example' };

  it('probes authorized internal media with a HEAD and never follows redirects', async () => {
    const request = jest.fn().mockResolvedValue(ok());
    await expect(verifySignedMediaObject(mediaUrl, { ...base, request }))
      .resolves.toBeUndefined();
    expect(request).toHaveBeenCalledWith(mediaUrl, expect.objectContaining({
      method: 'HEAD', redirect: 'error', cache: 'no-store',
    }));
  });

  it('fails before network access for foreign, local or unsigned URLs', async () => {
    const request = jest.fn();
    for (const url of [
      'https://evil.example/audio/track-1/AAC_256?e=1&s=x',
      'https://127.0.0.1/audio/track-1/AAC_256?e=1&s=x',
      'http://media.breezze.example/audio/track-1/AAC_256?e=1&s=x',
      'https://media.breezze.example/watch?v=dQw4w9WgXcQ',
      'https://user:pass@media.breezze.example/audio/track-1/AAC_256?e=1&s=x',
      'https://media.breezze.example/audio/track-1/AAC_256',
    ]) {
      await expect(verifySignedMediaObject(url, { ...base, request }))
        .rejects.toBeInstanceOf(ServiceUnavailableException);
    }
    expect(request).not.toHaveBeenCalled();
  });

  it('reports a missing R2 asset before Flutter gets an unusable grant', async () => {
    const request = jest.fn().mockResolvedValue(new Response(null, { status: 404 }));
    await expect(verifySignedMediaObject(mediaUrl, { ...base, request }))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects empty, non-audio, forbidden, redirect or unreachable responses', async () => {
    for (const response of [
      new Response(null, { status: 200, headers: { 'content-type': 'text/html', 'content-length': '100' } }),
      new Response(null, { status: 200, headers: { 'content-type': 'audio/mpeg', 'content-length': '0' } }),
      new Response(null, { status: 403 }),
      new Response(null, { status: 302, headers: { location: 'https://evil.example' } }),
    ]) {
      const request = jest.fn().mockResolvedValue(response);
      await expect(verifySignedMediaObject(mediaUrl, { ...base, request }))
        .rejects.toBeInstanceOf(ServiceUnavailableException);
    }
    const request = jest.fn().mockRejectedValue(new Error('network error containing secrets'));
    await expect(verifySignedMediaObject(mediaUrl, { ...base, request }))
      .rejects.toThrow('MEDIA_CDN_HEAD_UNAVAILABLE');
  });
});
