import 'dart:io';
import 'dart:typed_data';

import 'package:breezze_api_client/src/offline_audio_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late File plain;
  late File encrypted;
  late BreezzeOfflineAudioCipher cipher;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('breezze-aes-gcm-');
    plain = File('${folder.path}/audio.m4a');
    encrypted = File('${folder.path}/audio.bza');
    cipher = BreezzeOfflineAudioCipher(SecretKey(List<int>.filled(32, 0x42)));
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  Future<List<int>> decrypted({
    int start = 0,
    int? end,
    String owner = 'listener-a',
    String recording = 'recording-1',
    String version = 'sha256-asset-1',
    BreezzeOfflineAudioCipher? usingCipher,
  }) async {
    final chunks = await (usingCipher ?? cipher).decryptRange(
      encrypted: encrypted,
      ownerId: owner,
      catalogTrackId: recording,
      assetVersion: version,
      start: start,
      end: end,
    ).toList();
    return chunks.expand((e) => e).toList();
  }

  Future<List<int>> fixture() async {
    final bytes = List<int>.generate(
      BreezzeOfflineAudioCipher.chunkSize * 2 + 73,
      (i) => (i * 19 + 5) & 0xff,
    );
    await plain.writeAsBytes(bytes);
    await cipher.encryptFile(
      input: plain,
      output: encrypted,
      ownerId: 'listener-a',
      catalogTrackId: 'recording-1',
      assetVersion: 'sha256-asset-1',
    );
    return bytes;
  }

  test('encrypts two full chunks and tail without writing plaintext payload', () async {
    final source = await fixture();
    expect(await cipher.plaintextLength(encrypted), source.length);
    final cipherBytes = await encrypted.readAsBytes();
    expect(cipherBytes.sublist(0, 4), [0x42, 0x5a, 0x41, 0x38]);
    expect(cipherBytes.sublist(24, 24 + 24), isNot(source.sublist(0, 24)));
    expect(await decrypted(), source);
  });

  test('authenticates arbitrary seek ranges across chunk boundaries', () async {
    final source = await fixture();
    final start = BreezzeOfflineAudioCipher.chunkSize - 3;
    final end = BreezzeOfflineAudioCipher.chunkSize * 2 + 17;
    expect(await decrypted(start: start, end: end), source.sublist(start, end));
    expect(await decrypted(start: 12, end: 12), isEmpty);
    expect(await decrypted(start: source.length - 7), source.sublist(source.length - 7));
  });

  test('wrong listener, recording, asset identity or key cannot decrypt', () async {
    await fixture();
    for (final params in [
      ('listener-b', 'recording-1', 'sha256-asset-1'),
      ('listener-a', 'recording-2', 'sha256-asset-1'),
      ('listener-a', 'recording-1', 'old-version'),
    ]) {
      await expectLater(
        decrypted(owner: params.$1, recording: params.$2, version: params.$3),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    }
    final wrong = BreezzeOfflineAudioCipher(SecretKey(List<int>.filled(32, 0x99)));
    await expectLater(decrypted(usingCipher: wrong),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('modified ciphertext and truncated media are rejected', () async {
    await fixture();
    final bytes = await encrypted.readAsBytes();
    bytes[30] ^= 0x01;
    await encrypted.writeAsBytes(bytes);
    await expectLater(decrypted(),
        throwsA(isA<SecretBoxAuthenticationError>()));

    await encrypted.writeAsBytes(bytes.sublist(0, bytes.length - 20));
    await expectLater(cipher.plaintextLength(encrypted),
        throwsA(isA<FormatException>()));
  });

  test('missing, zero length and invalid range are rejected', () async {
    await plain.writeAsBytes(Uint8List(0));
    await expectLater(
      cipher.encryptFile(
        input: plain,
        output: encrypted,
        ownerId: 'listener-a',
        catalogTrackId: 'recording-1',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await encrypted.exists(), isFalse);
    final source = await fixture();
    await expectLater(
      decrypted(start: source.length + 1),
      throwsA(isA<RangeError>()),
    );
  });
}
