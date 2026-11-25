import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy Breezze monochrome vector lockups are packaged', () async {
    final white = await rootBundle.loadString(
      'assets/icons/breezze-logo-white.svg',
    );
    final black = await rootBundle.loadString(
      'assets/icons/breezze-logo-black.svg',
    );
    expect(white, contains('<svg'));
    expect(black, contains('<svg'));
    expect(white, contains('Breezze'));
    expect(black, contains('Breezze'));
    expect(white, contains('#FFFFFF'));
    expect(black, contains('#090909'));
    expect(white, contains('viewBox="0 0 1600 400"'));
    expect(black, contains('viewBox="0 0 1600 400"'));
  });
  test('all 23 previous Breezze SVG assets are bundled', () async {
    for (final asset in <String>[
      'assets/icons/b-note-mark.svg',
      'assets/icons/breezze-app-icon.svg',
      'assets/icons/breezze-icon-app-glossy.svg',
      'assets/icons/breezze-logo-ribbon-monochrome.svg',
      'assets/icons/breezze-mark-monochrome-bnote.svg',
      'assets/icons/breezze-symbol-black.svg',
      'assets/icons/breezze-symbol-white.svg',
      'assets/icons/browse.svg',
      'assets/icons/download.svg',
      'assets/icons/edit.svg',
      'assets/icons/home.svg',
      'assets/icons/library.svg',
      'assets/icons/music-note.svg',
      'assets/icons/new.svg',
      'assets/icons/pause.svg',
      'assets/icons/play.svg',
      'assets/icons/plus.svg',
      'assets/icons/profile.svg',
      'assets/icons/radio.svg',
      'assets/icons/search.svg',
      'assets/icons/skip-next.svg',
      'assets/icons/star-filled.svg',
      'assets/icons/star.svg',
    ]) {
      final data = await rootBundle.loadString(asset);
      expect(data.trimLeft(), startsWith('<svg'), reason: asset);
      expect(data.length, greaterThan(80), reason: asset);
    }
  });

  test('all 3 previous Breezze PNG logos and launcher assets are bundled', () async {
    for (final asset in <String>[
      'assets/icons/breezze-logo-black.png',
      'assets/icons/breezze-logo-white.png',
      'assets/icons/launcher.png',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(100), reason: asset);
    }
  });

  test('legacy icon names render the exact official pixel-B geometry', () async {
    const canonicalAsset = 'assets/icons/breezze-app-icon.svg';
    final canonical = await rootBundle.loadString(canonicalAsset);
    final paths = RegExp(r'<path[^>]*d="([^"]+)"');
    final original = paths.allMatches(canonical).map((m) => m.group(1)).toList();
    expect(original, hasLength(2), reason: 'Official mark is exactly two paths');

    for (final asset in <String>[
      'assets/icons/b-note-mark.svg',
      'assets/icons/breezze-icon-app-glossy.svg',
      'assets/icons/breezze-logo-ribbon-monochrome.svg',
      'assets/icons/breezze-mark-monochrome-bnote.svg',
      'assets/icons/breezze-logo-black.svg',
      'assets/icons/breezze-symbol-black.svg',
    ]) {
      final svg = await rootBundle.loadString(asset);
      final actual = paths.allMatches(svg).map((m) => m.group(1)).toList();
      expect(actual, original, reason: 'Only official Breezze pixel-B may be used: $asset');
      expect(svg, contains('fill-rule="evenodd"'), reason: asset);
    }

    final ribbon = await rootBundle.loadString(
      'assets/icons/breezze-logo-ribbon-monochrome.svg',
    );
    expect(ribbon, contains('>Breezze</text>'));
    expect(ribbon, contains('color="#FFFFFF"'));
    expect(ribbon, isNot(contains('sound-wave ribbon')));

    final glossy = await rootBundle.loadString(
      'assets/icons/breezze-icon-app-glossy.svg',
    );
    expect(glossy, contains('id="breezzeOfficialSurface"'));
    expect(glossy, contains('color="#FFFFFF"'));

    final inverse = await rootBundle.loadString(
      'assets/icons/breezze-mark-monochrome-bnote.svg',
    );
    expect(inverse, contains('rx="218" fill="#FFFFFF"'));
    expect(inverse, contains('color="#000000"'));
  });
}
