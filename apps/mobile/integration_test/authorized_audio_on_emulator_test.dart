import 'dart:convert';
import 'dart:io';

import 'package:breezze/core/audio/encrypted_offline_audio_source.dart';
import 'package:breezze/core/audio/just_audio_engine_adapter.dart';
import 'package:breezze/core/audio/offline_device_key.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_api_client/breezze_api_client.dart'
    show BreezzeOfflineAudioCipher;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

class _AcceptanceKeyStore extends OfflineDeviceKeyStore {
  _AcceptanceKeyStore(this.secret);
  final SecretKey secret;

  @override
  Future<SecretKey> forOwner(String ownerId, {bool create = false}) async {
    if (ownerId != 'qa-owner') throw StateError('OFFLINE_ACCOUNT_MISMATCH');
    return secret;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native player decodes a real public-domain full song over HTTPS',
      (tester) async {
    // Author Keith Adler released "Promise" into the public domain.
    // Source: https://commons.wikimedia.org/wiki/File:Promise.ogg
    // This asserts actual network audio and native MP3 decoding, NOT a
    // YouTube Music, Spotify or commercial-catalog entitlement.
    expect(defaultTargetPlatform, TargetPlatform.android);
    const fullSongUrl =
        'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
        '1/1f/Promise.ogg/Promise.ogg.mp3';
    final engine = JustAudioEngineAdapter();
    addTearDown(engine.dispose);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('Breezze real licensed song playback')),
    ));
    await tester.runAsync(() async {
      await engine.prepare(PlayableSource(
        trackId: 'qa:public-domain:promise',
        streamUrl: fullSongUrl,
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      )).timeout(const Duration(seconds: 45));
    });

    expect(engine.duration, greaterThan(const Duration(seconds: 120)),
        reason: 'ExoPlayer must parse the entire recording, not a preview');
    await engine.play();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 900));
    });
    expect(engine.position, greaterThan(Duration.zero),
        reason: 'Full-song native playback clock must actually advance');
    await tester.runAsync(() async {
      await engine.seek(const Duration(seconds: 65));
      await Future<void>.delayed(const Duration(milliseconds: 850));
    });
    expect(engine.position, greaterThan(const Duration(seconds: 64)),
        reason: 'A mid-track remote seek must reach actual decoded media');
    await engine.pause();
    final pausedAt = engine.position;
    expect(pausedAt, greaterThan(const Duration(seconds: 64)));
    await engine.stop();
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('native player decrypts and seeks protected offline AAC, no plaintext persisted',
      (tester) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    const encoded = String.fromEnvironment('BREEZZE_AUDIO_QA_AAC_BASE64');
    expect(encoded, isNotEmpty,
        reason: 'CI must generate original AAC audio rather than use catalog content');

    const owner = 'qa-owner';
    const catalogTrack = 'qa:licensed-offline-audio';
    final dir = await getTemporaryDirectory();
    final folder = await Directory(
        '${dir.path}/breezze-audio-qa-${DateTime.now().microsecondsSinceEpoch}'
    ).create(recursive: true);
    final original = File('${folder.path}/original.m4a');
    final encrypted = File('${folder.path}/audio.bza');
    await original.writeAsBytes(base64Decode(encoded), flush: true);

    final secretKey = SecretKey(List<int>.generate(32, (i) => i + 1));
    final keyStore = _AcceptanceKeyStore(secretKey);
    final cipher = BreezzeOfflineAudioCipher(secretKey);
    await cipher.encryptFile(
      input: original,
      output: encrypted,
      ownerId: owner,
      catalogTrackId: catalogTrack,
    );
    await original.delete();
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await File('${folder.path}/meta.json').writeAsString(jsonEncode({
      'storageFormat': 'bza8',
      'ownerId': owner,
      'catalogTrackId': catalogTrack,
      'rightsExpiresAtUtc': expiry.toIso8601String(),
    }));
    final bytes = await encrypted.readAsBytes();
    expect(bytes.length, greaterThan(100));
    expect(bytes.sublist(4, 8), isNot(equals('ftyp'.codeUnits)),
        reason: 'Encrypted bytes must not be the plaintext AAC container');
    await expectLater(
      BreezzeEncryptedOfflineAudioSource.open(
        path: encrypted.path,
        signedInUserId: 'other-listener',
        keyStore: keyStore,
      ),
      throwsStateError,
    );

    final engine = JustAudioEngineAdapter(
      encryptedSourceFactory: (path) =>
          BreezzeEncryptedOfflineAudioSource.open(
            path: path, signedInUserId: owner, keyStore: keyStore,
          ),
    );
    addTearDown(() async {
      await engine.dispose();
      if (await folder.exists()) await folder.delete(recursive: true);
    });
    await tester.runAsync(() async {
      await engine.prepare(PlayableSource(
        trackId: catalogTrack,
        streamUrl: encrypted.path,
        expiresAtUtc: expiry,
        isLocal: true,
      )).timeout(const Duration(seconds: 50));
    });
    expect(engine.duration, greaterThan(const Duration(seconds: 7)),
        reason: 'Native audio must decode authenticated plaintext chunks');
    await engine.play();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await engine.seek(const Duration(seconds: 4));
    });
    expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 4)));
    await engine.pause();
    await engine.stop();
    expect(await original.exists(), isFalse,
        reason: 'Plaintext must not remain on disk after encryption');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
