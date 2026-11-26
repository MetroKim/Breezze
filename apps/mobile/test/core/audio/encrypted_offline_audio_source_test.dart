import 'dart:convert';
import 'dart:io';

import 'package:breezze/core/audio/encrypted_offline_audio_source.dart';
import 'package:breezze/core/audio/offline_device_key.dart';
import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyStore extends OfflineDeviceKeyStore {
  _MemoryKeyStore(this.key);

  final SecretKey key;

  @override
  Future<SecretKey> forOwner(String ownerId, {bool create = false}) async {
    return key;
  }
}

void main() {
  late Directory root;
  late File audio;
  late BreezzeOfflineAudioCipher cipher;
  late _MemoryKeyStore keyStore;
  const owner = 'listener-1';
  const catalogId = 'recording-1';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('breezze-source-');
    audio = File('${root.path}/audio.bza');
    final key = SecretKey(List<int>.filled(32, 31));
    keyStore = _MemoryKeyStore(key);
    cipher = BreezzeOfflineAudioCipher(key);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> fixture({String metaOwner = owner, DateTime? expiry}) async {
    final plain = File('${root.path}/source.m4a');
    await plain.writeAsBytes(List<int>.generate(200000, (i) => i & 0xff));
    await cipher.encryptFile(
      input: plain,
      output: audio,
      ownerId: owner,
      catalogTrackId: catalogId,
    );
    await File('${root.path}/meta.json').writeAsString(jsonEncode({
      'storageFormat': 'bza8',
      'ownerId': metaOwner,
      'catalogTrackId': catalogId,
      'rightsExpiresAtUtc':
          (expiry ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
              .toUtc().toIso8601String(),
    }));
  }

  test('just_audio seeks with authenticated plaintext ranges', () async {
    await fixture();
    final source = await BreezzeEncryptedOfflineAudioSource.open(
      path: audio.path, signedInUserId: owner, keyStore: keyStore,
    );
    final response = await source.request(65530, 65545);
    expect(response.sourceLength, 200000);
    expect(response.offset, 65530);
    expect(response.contentLength, 15);
    final chunks = await response.stream.toList();
    expect(chunks.expand((c) => c).toList(),
        List<int>.generate(15, (i) => (65530 + i) & 0xff));
  });

  test('another listener never unlocks a private encrypted source', () async {
    await fixture();
    await expectLater(
      BreezzeEncryptedOfflineAudioSource.open(
        path: audio.path, signedInUserId: 'listener-2', keyStore: keyStore,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('expired offline grants fail before decrypted data is released', () async {
    await fixture(expiry: DateTime.now().toUtc().subtract(const Duration(hours: 1)));
    await expectLater(
      BreezzeEncryptedOfflineAudioSource.open(
        path: audio.path, signedInUserId: owner, keyStore: keyStore,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('tampered encrypted chunk never reaches the player stream', () async {
    await fixture();
    final bytes = await audio.readAsBytes();
    bytes[40] ^= 0x01;
    await audio.writeAsBytes(bytes);
    final source = await BreezzeEncryptedOfflineAudioSource.open(
      path: audio.path, signedInUserId: owner, keyStore: keyStore,
    );
    final response = await source.request(0, 100);
    await expectLater(response.stream.toList(),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });
}
