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
    return this.cdnBaseUrl.replace(/\/$/, '') + path;
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

  /**
   * R2 only: signed delivery for explicitly ingested and rights-authorized
   * Breezze-controlled video assets. Never feed this a YouTube video ID.
   */
  createVideoUrl(
    videoAssetId: string,
    mode: 'stream' | 'download',
    rightsExpiresAt: Date | null = null,
  ): { url: string; expiresAt: Date } {
    if (!/^[a-f0-9-]{36}$/i.test(videoAssetId)) {
      throw new Error('VIDEO_ASSET_ID_INVALID');
    }
    const now = Date.now();
    const expires = Math.min(
      now + (mode === 'stream' ? 2 * 60 * 60 * 1000 : 15 * 60 * 1000),
      rightsExpiresAt?.getTime() ?? Number.POSITIVE_INFINITY,
    );
    if (!Number.isFinite(expires) || expires <= now) {
      throw new Error('MEDIA_URL_EXPIRY_INVALID');
    }
    const signature = this.sign(`video:${videoAssetId}:${mode}:${expires}`);
    return {
      url: `${this.edgeUrl(`/video/${encodeURIComponent(videoAssetId)}/${mode}`)}?e=${expires}&s=${signature}`,
      expiresAt: new Date(expires),
    };
  }

  verifyVideo(videoAssetId: string, mode: 'stream' | 'download', expires: number, sig: string): boolean {
    if (!Number.isSafeInteger(expires) || Date.now() >= expires) return false;
    const expected = Buffer.from(this.sign(`video:${videoAssetId}:${mode}:${expires}`), 'utf8');
    const actual = Buffer.from(sig, 'utf8');
    return actual.length === expected.length && timingSafeEqual(expected, actual);
  }

  /**
   * A short-lived, upload-only capability for a verified internal catalog
   * recording. A public music provider URL is never accepted as an input.
   */
  createAudioIngestUrl(
    trackId: string, variant: string, mimeType: string, sizeBytes: number,
  ): { url: string; expiresAt: Date } {
    if (!/^[0-9a-fA-F-]{36}$/.test(trackId) ||
        !['AAC_128','AAC_256','LOSSLESS','HI_RES'].includes(variant) ||
        !Number.isSafeInteger(sizeBytes) || sizeBytes < 12 || sizeBytes > 95_000_000 ||
        !((variant === 'LOSSLESS' || variant === 'HI_RES')
          ? ['audio/flac', 'audio/x-flac'].includes(mimeType)
          : ['audio/mp4','audio/aac'].includes(mimeType))) {
      throw new Error('MEDIA_INGEST_METADATA_INVALID');
    }
    const expires = Date.now() + 10 * 60 * 1000;
    const signature = this.sign(`ingest:${trackId}:${variant}:${mimeType}:${sizeBytes}:${expires}`);
    return {
      url: `${this.edgeUrl(`/ingest/audio/${encodeURIComponent(trackId)}/${variant}`)}?b=${sizeBytes}&m=${encodeURIComponent(mimeType)}&e=${expires}&s=${signature}`,
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
