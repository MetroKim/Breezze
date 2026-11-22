import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// Executed explicitly AFTER flutter create and flutter pub get:
///   flutter test tool/brand_launcher_icons_test.dart
///
/// Build-time rasterization uses the supplied vector as the single source of
/// truth. No online image service, proprietary icon generator or checked-in
/// platform runner directory is required. Files created by flutter create are
/// overwritten with matching Breezze icons before packaging each platform.
void main() {
  testWidgets('install supplied Breezze mark as native platform launcher icons',
      (tester) async {
    const boundaryKey = ValueKey('breezze-launcher-render');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 512,
                height: 512,
                child: SvgPicture.asset('assets/icons/breezze-app-icon.svg'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final rendered = await boundary.toImage(pixelRatio: 2);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    expect(data, isNotNull, reason: 'Supplied Breezze SVG failed to rasterize');

    final source = img.decodePng(data!.buffer.asUint8List());
    expect(source, isNotNull);
    expect(source!.width, 1024);
    expect(source.height, 1024);

    final pngCache = <int, Uint8List>{};
    Uint8List png(int size) => pngCache.putIfAbsent(
          size,
          () => Uint8List.fromList(img.encodePng(
            size == 1024
                ? source
                : img.copyResize(source, width: size, height: size,
                    interpolation: img.Interpolation.cubic),
          )),
        );

    Future<void> put(String name, Uint8List bytes) async {
      final file = File(name);
      if (!await file.parent.exists()) return;
      await file.writeAsBytes(bytes, flush: true);
    }

    await Directory('build/brand').create(recursive: true);
    await put('build/brand/breezze-app-icon-1024.png', png(1024));

    const androidSizes = <String, int>{
      'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
      'xxhdpi': 144, 'xxxhdpi': 192,
    };
    for (final entry in androidSizes.entries) {
      await put('android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
          png(entry.value));
    }

    Future<void> writeAppleCatalog(String folder) async {
      final manifest = File('$folder/Contents.json');
      if (!await manifest.exists()) return;
      final json = jsonDecode(await manifest.readAsString());
      if (json is! Map || json['images'] is! List) {
        throw StateError('Invalid Apple icon asset catalog: $folder');
      }
      for (final raw in json['images'] as List) {
        if (raw is! Map || raw['filename'] is! String) continue;
        final sizeText = raw['size'] as String?;
        final scaleText = raw['scale'] as String?;
        if (sizeText == null || scaleText == null) continue;
        final logicalSize = double.tryParse(sizeText.split('x').first);
        final scale = double.tryParse(scaleText.replaceAll('x', ''));
        if (logicalSize == null || scale == null) continue;
        final pixels = (logicalSize * scale).round().clamp(1, 1024);
        await put('$folder/${raw['filename']}', png(pixels));
      }
    }
    await writeAppleCatalog('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    await writeAppleCatalog('macos/Runner/Assets.xcassets/AppIcon.appiconset');

    if (await Directory('web').exists()) {
      await put('web/favicon.png', png(48));
      await put('web/icons/Icon-192.png', png(192));
      await put('web/icons/Icon-512.png', png(512));
      await put('web/icons/Icon-maskable-192.png', png(192));
      await put('web/icons/Icon-maskable-512.png', png(512));
    }

    if (await File('windows/runner/resources/app_icon.ico').exists()) {
      const sizes = [16, 24, 32, 48, 64, 128, 256];
      final layers = [for (final size in sizes) png(size)];
      final bytes = BytesBuilder();
      final header = ByteData(6);
      header.setUint16(0, 0, Endian.little);
      header.setUint16(2, 1, Endian.little);
      header.setUint16(4, layers.length, Endian.little);
      bytes.add(header.buffer.asUint8List());
      var offset = 6 + layers.length * 16;
      for (var i = 0; i < layers.length; i++) {
        final entry = ByteData(16);
        entry.setUint8(0, sizes[i] == 256 ? 0 : sizes[i]);
        entry.setUint8(1, sizes[i] == 256 ? 0 : sizes[i]);
        entry.setUint8(2, 0);
        entry.setUint8(3, 0);
        entry.setUint16(4, 1, Endian.little);
        entry.setUint16(6, 32, Endian.little);
        entry.setUint32(8, layers[i].length, Endian.little);
        entry.setUint32(12, offset, Endian.little);
        offset += layers[i].length;
        bytes.add(entry.buffer.asUint8List());
      }
      for (final layer in layers) {
        bytes.add(layer);
      }
      await put('windows/runner/resources/app_icon.ico', bytes.takeBytes());
    }

    if (await Directory('linux').exists()) {
      await Directory('linux/assets').create(recursive: true);
      await put('linux/assets/breezze.png', png(256));
    }
    expect(pngCache[1024], isNotEmpty);
  });
}
