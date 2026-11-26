import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';

/// Shared user-initiated image picker for account avatars and playlist covers.
/// File bytes are decoded and re-encoded as a small PNG; never upload the
/// untrusted original file or use source-provider artwork as a profile photo.
/// A null return means the user cancelled the system file chooser.
Future<String?> pickBreezzePngThumbnail({
  String label = 'Breezze picture',
  int side = 224,
}) async {
  final selected = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: label,
        extensions: const ['png', 'jpg', 'jpeg', 'webp'],
      ),
    ],
  );
  if (selected == null) return null;

  final bytes = await selected.readAsBytes();
  if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Image must be smaller than 10 MB');
  }
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: side,
    targetHeight: side,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null || png.lengthInBytes > 256000) {
        throw const FormatException('Choose a smaller image');
      }
      return base64Encode(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
