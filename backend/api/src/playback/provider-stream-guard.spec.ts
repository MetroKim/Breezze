import { NotAcceptableException, ServiceUnavailableException } from '@nestjs/common';
import type { ProviderPlaybackSource } from '../providers/provider-adapter.interface';
import { MIN_PROVIDER_STREAM_LEASE_MS, validateProviderAudioSource } from './provider-stream-guard';

describe('validateProviderAudioSource', () => {
  const now = new Date('2026-11-25T16:00:00.000Z');
  const valid = (): ProviderPlaybackSource => ({
    url: 'https://media.licensed.example/stream.m4a?token=secret',
    expiresAt: new Date(now.getTime() + 90_000),
    mimeType: 'audio/mp4; codecs="mp4a.40.2"',
  });

  it('accepts an authorized HTTPS audio source without altering its signed query', () => {
    const result = validateProviderAudioSource(valid(), new Date(now.getTime() + 120_000), now);
    expect(result.toString()).toBe(valid().url);
  });

  it.each([
    'http://media.licensed.example/a.mp3',
    'https://user:password@media.licensed.example/a.mp3',
    'https://localhost/a.mp3',
    'https://127.0.0.1/a.mp3',
    'https://[::1]/a.mp3',
    'https://host.internal/a.mp3',
    'https://media.licensed.example/a.mp3#fragment',
    'not a URL',
  ])('rejects untrusted remote media URL %s', (url) => {
    expect(() => validateProviderAudioSource({ ...valid(), url }, null, now))
      .toThrow(ServiceUnavailableException);
  });

  it('rejects missing, invalid or nearly expired leases', () => {
    for (const expiresAt of [
      new Date(now.getTime() - 1),
      new Date(now.getTime() + MIN_PROVIDER_STREAM_LEASE_MS),
      new Date(NaN),
      undefined,
    ]) {
      expect(() => validateProviderAudioSource(
        { ...valid(), expiresAt } as ProviderPlaybackSource, null, now,
      )).toThrow('PROVIDER_SOURCE_EXPIRES_TOO_SOON');
    }
  });

  it('enforces a real upstream authorization window', () => {
    expect(() => validateProviderAudioSource(valid(), new Date(now.getTime() + 30_000), now))
      .toThrow(NotAcceptableException);
  });

  it.each(['video/mp4', 'text/html', 'application/json'])(
    'rejects non-audio response types %s', (mimeType) => {
      expect(() => validateProviderAudioSource({ ...valid(), mimeType }, null, now))
        .toThrow('PROVIDER_RETURNED_NON_AUDIO_SOURCE');
    },
  );

  it.each(['audio/ogg', 'application/vnd.apple.mpegurl', 'application/dash+xml'])(
    'allows supported audio transport %s', (mimeType) => {
      expect(() => validateProviderAudioSource({ ...valid(), mimeType }, null, now))
        .not.toThrow();
    },
  );
});
