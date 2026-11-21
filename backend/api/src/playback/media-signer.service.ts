import { createHmac, timingSafeEqual } from 'crypto';

export class MediaSigner {
  constructor(
    private readonly signingKey: string,
    private readonly cdnBaseUrl: string,
  ) {}

  private sign(payload: string): string {
    return createHmac('sha256', this.signingKey)
      .update(payload)
      .digest('base64url');
  }

  private edgeUrl(path: string): string {
    return `${this.cdnBaseUrl.replace(/\\/$/, '')}${path}`;
  }

  createPlaybackUrl(
    trackId: string,
    variant: string,
    rightsExpiresAt: Date | null = null,
  ): { url: string; expiresAt: Date } {
    const now = Date.now();
    const defaultExpiry = now + 6 * 3600 * 1000;
    const expires = Math.min(
      defaultExpiry,
      rightsExpiresAt?.getTime() ?? defaultExpiry,
    );
    if (expires <= now) {
      throw new Error('MEDIA_URL_EXPIRY_INVALID');
    }
    const signature = this.sign(`${trackId}:${variant}:${expires}`);
    return {
      url: `${this.edgeUrl(`/audio/${encodeURIComponent(trackId)}/${encodeURIComponent(variant)}`)}?e=${expires}&s=${signature}`,
      expiresAt: new Date(expires),
    };
  }

  createUploadUrl(
    userId: string,
    jobId: string,
    originalFilename: string,
    bytes: number,
  ): { url: string; expiresAt: Date; objectKey: string } {
    const filename = originalFilename.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120);
    if (!filename || filename === '.' || filename === '..'
      || !Number.isSafeInteger(bytes) || bytes < 1 || bytes > 100 * 1024 * 1024) {
      throw new Error('MEDIA_UPLOAD_METADATA_INVALID');
    }
    const expires = Date.now() + 15 * 60 * 1000;
    const payload = `upload:${userId}:${jobId}:${filename}:${bytes}:${expires}`;
    const signature = this.sign(payload);
    const path = `/upload/${encodeURIComponent(userId)}/${encodeURIComponent(jobId)}/${encodeURIComponent(filename)}`;
    return {
      url: `${this.edgeUrl(path)}?b=${bytes}&e=${expires}&s=${signature}`,
      expiresAt: new Date(expires),
      objectKey: `quarantine/${userId}/${jobId}/${filename}`,
    };
  }

  signPlaybackUrl(
    trackId: string,
    variant: string,
    rightsExpiresAt: Date | null = null,
  ): string {
    return this.createPlaybackUrl(trackId, variant, rightsExpiresAt).url;
  }

  verify(trackId: string, variant: string, expires: number, sig: string): boolean {
    if (!Number.isSafeInteger(expires) || Date.now() >= expires) return false;
    const expected = Buffer.from(
      this.sign(`${trackId}:${variant}:${expires}`),
      'utf8',
    );
    const actual = Buffer.from(sig, 'utf8');
    if (actual.length !== expected.length) return false;
    return timingSafeEqual(expected, actual);
  }
}
