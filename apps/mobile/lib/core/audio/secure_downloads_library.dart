/// One encryption-required constructor for native Breezze music downloads.
library;

import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';

import 'offline_device_key.dart';

DownloadsLibrary secureDownloadsLibrary({
  required Directory root,
  required LyricsProvider lyrics,
}) => DownloadsLibrary(
      root: root,
      lyrics: lyrics,
      protectAudio: ({
        required File plaintextFile,
        required File encryptedFile,
        required String ownerId,
        required String catalogTrackId,
        String? assetVersion,
      }) async {
        // The key is generated only for a new authorized download or
        // deliberate legacy-file migration; never on a playback attempt.
        final secretKey = await OfflineDeviceKeyStore.shared
            .forOwner(ownerId, create: true);
        await BreezzeOfflineAudioCipher(secretKey).encryptFile(
          input: plaintextFile,
          output: encryptedFile,
          ownerId: ownerId,
          catalogTrackId: catalogTrackId,
          assetVersion: assetVersion,
        );
      },
    );
