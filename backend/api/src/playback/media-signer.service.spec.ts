import { MediaSigner } from './media-signer.service';

describe('MediaSigner', () => {
  it('signs a URL that verifies for the same track and variant', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');
    const url = new URL(signer.signPlaybackUrl('track-1', 'AAC_256'));

    expect(
      signer.verify(
        'track-1',
        'AAC_256',
        Number(url.searchParams.get('e')),
        url.searchParams.get('s')!,
      ),
    ).toBe(true);
  });

  it('rejects a signature for a different track or variant', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');
    const url = new URL(signer.signPlaybackUrl('track-1', 'AAC_256'));
    const expires = Number(url.searchParams.get('e'));
    const signature = url.searchParams.get('s')!;

    expect(signer.verify('track-2', 'AAC_256', expires, signature)).toBe(false);
    expect(signer.verify('track-1', 'LOSSLESS', expires, signature)).toBe(false);
  });

  it('limits default playback grants to 15 minutes', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');
    const before = Date.now();
    const signed = signer.createPlaybackUrl('track-1', 'AAC_256');

    expect(signed.expiresAt.getTime()).toBeGreaterThanOrEqual(before + 15 * 60 * 1000 - 1000);
    expect(signed.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 15 * 60 * 1000);
  });

  it('caps signed URL expiry at the rights end time', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');
    const rightsExpiry = new Date(Date.now() + 60_000);
    const signed = signer.createPlaybackUrl(
      'track-1',
      'AAC_256',
      rightsExpiry,
    );
    const url = new URL(signed.url);

    expect(signed.expiresAt).toEqual(rightsExpiry);
    expect(Number(url.searchParams.get('e'))).toBe(rightsExpiry.getTime());
  });

  it('refuses to issue a URL for already expired rights', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');

    expect(() =>
      signer.createPlaybackUrl(
        'track-1',
        'AAC_256',
        new Date(Date.now() - 1),
      ),
    ).toThrow('MEDIA_URL_EXPIRY_INVALID');
  });

  it('creates short-lived R2 quarantine upload URLs with an exact object key', () => {
    const signer = new MediaSigner('test-signing-key', 'https://media.breezze.app');
    const upload = signer.createUploadUrl('user-1', 'job-1', 'mix final.wav', 1024);
    const url = new URL(upload.url);

    expect(url.pathname).toBe('/upload/user-1/job-1/mix_final.wav');
    expect(url.searchParams.get('b')).toBe('1024');
    expect(upload.objectKey).toBe('quarantine/user-1/job-1/mix_final.wav');
    expect(upload.expiresAt.getTime()).toBeGreaterThan(Date.now());
    expect(upload.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 15 * 60 * 1000);
    expect(url.searchParams.get('s')).toBeTruthy();
  });

  it('rejects invalid upload size metadata', () => {
    const signer = new MediaSigner('test-signing-key', 'https://media.breezze.app');
    expect(() => signer.createUploadUrl('user-1', 'job-1', 'track.wav', 0))
      .toThrow('MEDIA_UPLOAD_METADATA_INVALID');
    expect(() => signer.createUploadUrl('user-1', 'job-1', 'track.wav', 101 * 1024 * 1024))
      .toThrow('MEDIA_UPLOAD_METADATA_INVALID');
  });

  it('rejects expired signatures and malformed signature lengths', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');

    expect(signer.verify('track-1', 'AAC_256', Date.now() - 1, 'expired')).toBe(false);
    expect(signer.verify('track-1', 'AAC_256', Date.now() + 60_000, 'x')).toBe(false);
  });
});
