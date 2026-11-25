import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recovered Breezze monochrome vector lockups are bundled', () async {
    final white = await rootBundle.loadString(
      'assets/icons/breezze-logo-white.svg',
    );
    final black = await rootBundle.loadString(
      'assets/icons/breezze-logo-black.svg',
    );
    for (final markup in [white, black]) {
      expect(markup, contains('<svg'));
      expect(markup, contains('viewBox="0 0 1600 400"'));
      expect(markup, contains('Breezze'));
      expect(markup, contains('M162,183'));
    }
    expect(white, contains('fill="#FFFFFF"'));
    expect(black, contains('fill="#090909"'));
    expect(white, isNot(equals(black)));
  });

  test('the selected monochrome app icon and symbol remain bundled', () async {
    final icon = await rootBundle.loadString(
      'assets/icons/breezze-app-icon.svg',
    );
    final symbol = await rootBundle.loadString(
      'assets/icons/breezze-symbol-white.svg',
    );
    expect(icon, contains('fill="#050505"'));
    expect(icon, contains('M162,183'));
    expect(symbol, contains('<svg'));
    expect(symbol, contains('M162,183'));
  });
}
