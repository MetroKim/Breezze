import 'package:breezze/core/audio/native_source_guard.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 25, 15);
  PlayableSource source(
    String location, {
    DateTime? expiry,
    bool isLocal = false,
  }) =>
      PlayableSource(
        trackId: 'breezze-track-1',
        streamUrl: location,
        expiresAtUtc: expiry ?? now.add(const Duration(minutes: 20)),
        isLocal: isLocal,
      );

  Matcher rejectedAs(String code) =>
      isA<StateError>().having((error) => error.message, 'code', code);

  group('native audio transport boundary', () {
    test('accepts active HTTPS signed media without modifying its query', () {
      expect(
        () => validateNativeAudioSource(
          source('https://cdn.breezze.test/audio/track?e=123&s=signed-value'),
          nowUtc: now,
        ),
        returnsNormally,
      );
    });

    test('rejects an expired grant before opening the audio decoder', () {
      expect(
        () => validateNativeAudioSource(
          source(
            'https://cdn.breezze.test/audio/track?s=sensitive',
            expiry: now.subtract(const Duration(seconds: 1)),
          ),
          nowUtc: now,
        ),
        throwsA(rejectedAs('AUDIO_SOURCE_EXPIRED')),
      );
    });

    test('rejects arbitrary remote HTTP, data and file schemes', () {
      for (final url in <String>[
        'http://cdn.example.test/audio/track',
        'data:audio/mpeg;base64,AAAA',
        'file:///etc/passwd',
      ]) {
        expect(
          () => validateNativeAudioSource(source(url), nowUtc: now),
          throwsStateError,
          reason: url,
        );
      }
    });

    test('rejects credentials and fragments without echoing signed URLs', () {
      for (final url in <String>[
        'https://user:password@cdn.example.test/audio',
        'https://cdn.example.test/audio?token=sensitive#fragment',
      ]) {
        expect(
          () => validateNativeAudioSource(source(url), nowUtc: now),
          throwsA(rejectedAs('AUDIO_SOURCE_INVALID_URL')),
        );
      }
    });

    test('allows plaintext media only on a deliberate dev loopback', () {
      final local = source('http://127.0.0.1:8787/audio');
      expect(
        () => validateNativeAudioSource(local, nowUtc: now),
        throwsA(rejectedAs('AUDIO_SOURCE_REQUIRES_HTTPS')),
      );
      expect(
        () => validateNativeAudioSource(
          local, nowUtc: now, allowDevelopmentLoopback: true,
        ),
        returnsNormally,
      );
      expect(
        () => validateNativeAudioSource(
          source('http://public.example.test/audio'),
          nowUtc: now, allowDevelopmentLoopback: true,
        ),
        throwsA(rejectedAs('AUDIO_SOURCE_REQUIRES_HTTPS')),
      );
    });

    test('accepts platform-native paths but not URLs mislabeled local', () {
      for (final path in <String>[
        '/app/private/music/recording.flac',
        r'C:\Music\recording.flac',
        'content://com.android.providers.media.documents/document/audio%3A42',
      ]) {
        expect(
          () => validateNativeAudioSource(
            source(path, isLocal: true), nowUtc: now,
          ),
          returnsNormally,
          reason: path,
        );
      }
      expect(
        () => validateNativeAudioSource(
          source('https://example.test/remote.mp3', isLocal: true),
          nowUtc: now,
        ),
        throwsA(rejectedAs('AUDIO_LOCAL_SOURCE_INVALID')),
      );
    });

    test('rejects blank identifiers and dangerous local paths', () {
      final unnamed = PlayableSource(
        trackId: ' ',
        streamUrl: 'https://cdn.breezze.test/audio',
        expiresAtUtc: now.add(const Duration(minutes: 5)),
      );
      expect(
        () => validateNativeAudioSource(unnamed, nowUtc: now),
        throwsA(rejectedAs('AUDIO_SOURCE_INVALID')),
      );
      expect(
        () => validateNativeAudioSource(
          source('../relative/audio.flac', isLocal: true), nowUtc: now,
        ),
        throwsA(rejectedAs('AUDIO_LOCAL_SOURCE_INVALID')),
      );
    });
  });
}
