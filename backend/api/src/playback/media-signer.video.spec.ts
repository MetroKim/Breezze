import { MediaSigner } from './media-signer.service';

describe('MediaSigner video contract', () => {
  const id = '123e4567-e89b-42d3-a456-426614174000';
  const signer = new MediaSigner('test-signing-key', 'https://media.breezze.test');

  it('makes purpose-scoped MP4 playback and download grants', () => {
    const stream = new URL(signer.createVideoUrl(id, 'stream').url);
    const download = new URL(signer.createVideoUrl(id, 'download').url);
    const e = Number(stream.searchParams.get('e'));
    const signature = stream.searchParams.get('s')!;

    expect(stream.pathname).toBe('/video/' + id + '/stream');
    expect(download.pathname).toBe('/video/' + id + '/download');
    expect(signer.verifyVideo(id, 'stream', e, signature)).toBe(true);
    expect(signer.verifyVideo(id, 'download', e, signature)).toBe(false);
    expect(signer.verifyVideo('123e4567-e89b-42d3-a456-426614174001', 'stream', e, signature)).toBe(false);
  });

  it('expires video grants within 15 minutes and never beyond rights', () => {
    const rightsEnd = new Date(Date.now() + 30_000);
    const signed = signer.createVideoUrl(id, 'stream', rightsEnd);
    expect(signed.expiresAt).toEqual(rightsEnd);
    const ordinary = signer.createVideoUrl(id, 'download');
    expect(ordinary.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 900_000);
    expect(() => signer.createVideoUrl(id, 'stream', new Date(Date.now() - 1000)))
      .toThrow('MEDIA_URL_EXPIRY_INVALID');
  });

  it('rejects upstream video IDs and expired signatures', () => {
    expect(() => signer.createVideoUrl('dQw4w9WgXcQ', 'stream'))
      .toThrow('VIDEO_ASSET_ID_INVALID');
    expect(signer.verifyVideo(id, 'stream', Date.now() - 1, 'expired')).toBe(false);
  });
});
