/// Breezze V8 app-private audio encryption.
 ///
 /// Format BZA8: fixed authenticated AES-256-GCM chunks (64 KiB), each with
 /// its own per-file random 96-bit nonce and 128-bit MAC. Every chunk binds
 /// to the signed-in owner, canonical recording and encoded asset identity.
 /// Ranged decryption is memory-bounded so seeking never writes plaintext to
 /// a temporary disk file. This is application encryption, not FairPlay/DRM;
 /// licensed provider-specific DRM remains a separate release requirement.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BreezzeOfflineAudioCipher {
  BreezzeOfflineAudioCipher(this.secretKey);

  /// A 256-bit device-keystore-derived symmetric key, NEVER embedded in Git.
  final SecretKey secretKey;

  static const int chunkSize = 64 * 1024;
  static const int _headerLength = 24;
  static const int _tagLength = 16;
  static const int _maximumPlaintextBytes = 32 * 1024 * 1024 * 1024;

  static const List<int> _magic = [0x42, 0x5a, 0x41, 0x38]; // "BZA8"
  final _algorithm = AesGcm.with256bits();

  static List<int> _aad(String owner, String recording, String? version) =>
      utf8.encode(jsonEncode([owner, recording, version ?? '']));

  static Uint8List _nonce(List<int> prefix, int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex > 0xffffffff) {
      throw const FormatException('Offline media has too many chunks');
    }
    final nonce = Uint8List(12)..setRange(0, 8, prefix);
    ByteData.sublistView(nonce).setUint32(8, chunkIndex, Endian.big);
    return nonce;
  }

  /// Stage to a separate file and publish it only after all authenticated
  /// chunks are flushed. The caller removes the plaintext file on success.
  Future<void> encryptFile({
    required File input,
    required File output,
    required String ownerId,
    required String catalogTrackId,
    String? assetVersion,
  }) async {
    if (ownerId.isEmpty || catalogTrackId.isEmpty) {
      throw const FormatException('Missing offline ownership binding');
    }
    final inputLength = await input.length();
    if (inputLength <= 0 || inputLength > _maximumPlaintextBytes) {
      throw const FormatException('Invalid offline media length');
    }
    final random = Random.secure();
    final prefix = List<int>.generate(8, (_) => random.nextInt(256));
    final header = Uint8List(_headerLength)
      ..setRange(0, 4, _magic)
      ..setRange(16, 24, prefix);
    final headerView = ByteData.sublistView(header);
    headerView.setUint32(4, chunkSize, Endian.big);
    headerView.setUint64(8, inputLength, Endian.big);

    final temp = File('${output.path}.tmp');
    await temp.parent.create(recursive: true);
    final aad = _aad(ownerId, catalogTrackId, assetVersion);
    RandomAccessFile? reader;
    RandomAccessFile? writer;
    try {
      reader = await input.open();
      writer = await temp.open(mode: FileMode.write);
      await writer.writeFrom(header);
      var remaining = inputLength;
      var chunkIndex = 0;
      while (remaining > 0) {
        final count = min(chunkSize, remaining);
        final plain = await reader.read(count);
        if (plain.length != count) {
          throw const FormatException('Audio transfer changed during encryption');
        }
        final nonce = _nonce(prefix, chunkIndex);
        final sealed = await _algorithm.encrypt(
          plain,
          secretKey: secretKey,
          nonce: nonce,
          aad: aad,
        );
        await writer.writeFrom(sealed.cipherText);
        await writer.writeFrom(sealed.mac.bytes);
        remaining -= count;
        chunkIndex++;
      }
      await writer.flush();
      await writer.close();
      writer = null;
      await reader.close();
      reader = null;
      // Do not truncate a working existing encrypted asset until the new
      // complete file has been written and verified as structurally sound.
      if (await output.exists()) await output.delete();
      await temp.rename(output.path);
    } finally {
      if (reader != null) await reader.close();
      if (writer != null) await writer.close();
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<_AudioHeader> _readHeader(File encrypted) async {
    final size = await encrypted.length();
    if (size < _headerLength + _tagLength + 1) {
      throw const FormatException('Truncated encrypted audio');
    }
    final raf = await encrypted.open();
    try {
      final data = await raf.read(_headerLength);
      if (data.length != _headerLength ||
          !(data[0] == _magic[0] && data[1] == _magic[1] &&
            data[2] == _magic[2] && data[3] == _magic[3])) {
        throw const FormatException('Unsupported encrypted media header');
      }
      final bytes = Uint8List.fromList(data);
      final view = ByteData.sublistView(bytes);
      final configuredChunkSize = view.getUint32(4, Endian.big);
      final plaintextLength = view.getUint64(8, Endian.big);
      if (configuredChunkSize != chunkSize ||
          plaintextLength <= 0 ||
          plaintextLength > _maximumPlaintextBytes) {
        throw const FormatException('Invalid encrypted media length');
      }
      final chunkCount = (plaintextLength + chunkSize - 1) ~/ chunkSize;
      final expected = _headerLength + plaintextLength + chunkCount * _tagLength;
      if (size != expected) {
        throw const FormatException('Encrypted media length mismatch');
      }
      return _AudioHeader(
        plaintextLength: plaintextLength,
        noncePrefix: bytes.sublist(16, 24),
      );
    } finally {
      await raf.close();
    }
  }

  Future<int> plaintextLength(File encrypted) async =>
      (await _readHeader(encrypted)).plaintextLength;

  /// The callback is suitable for just_audio StreamAudioSource: each returned
  /// chunk is authenticated BEFORE it is yielded to the decoder, including
  /// for seeks and HTTP range reads.
  Stream<List<int>> decryptRange({
    required File encrypted,
    required String ownerId,
    required String catalogTrackId,
    String? assetVersion,
    int start = 0,
    int? end,
  }) async* {
    if (ownerId.isEmpty || catalogTrackId.isEmpty) {
      throw const FormatException('Missing offline ownership binding');
    }
    final header = await _readHeader(encrypted);
    final finish = end ?? header.plaintextLength;
    if (start < 0 || finish < start || finish > header.plaintextLength) {
      throw RangeError('Requested audio range is invalid');
    }
    if (start == finish) return;

    final first = start ~/ chunkSize;
    final last = (finish - 1) ~/ chunkSize;
    final aad = _aad(ownerId, catalogTrackId, assetVersion);
    final raf = await encrypted.open();
    try {
      for (var index = first; index <= last; index++) {
        final chunkStart = index * chunkSize;
        final count = min(chunkSize, header.plaintextLength - chunkStart);
        final cipherOffset = _headerLength + index * (chunkSize + _tagLength);
        await raf.setPosition(cipherOffset);
        final serialized = await raf.read(count + _tagLength);
        if (serialized.length != count + _tagLength) {
          throw const FormatException('Missing encrypted audio chunk');
        }
        final box = SecretBox(
          serialized.sublist(0, count),
          nonce: _nonce(header.noncePrefix, index),
          mac: Mac(serialized.sublist(count)),
        );
        final plain = await _algorithm.decrypt(
          box,
          secretKey: secretKey,
          aad: aad,
        );
        final localStart = max(start - chunkStart, 0);
        final localEnd = min(finish - chunkStart, count);
        yield plain.sublist(localStart, localEnd);
      }
    } finally {
      await raf.close();
    }
  }
}

class _AudioHeader {
  const _AudioHeader({
    required this.plaintextLength,
    required this.noncePrefix,
  });
  final int plaintextLength;
  final List<int> noncePrefix;
}
