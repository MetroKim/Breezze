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
}
