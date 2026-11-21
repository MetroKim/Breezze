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

  it('rejects expired signatures and malformed signature lengths', () => {
    const signer = new MediaSigner('test-signing-key', 'https://cdn.example');

    expect(signer.verify('track-1', 'AAC_256', Date.now() - 1, 'expired')).toBe(false);
    expect(signer.verify('track-1', 'AAC_256', Date.now() + 60_000, 'x')).toBe(false);
  });
});
