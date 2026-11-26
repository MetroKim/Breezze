import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('plain Flutter host dark theme cannot crash Breezze UI surfaces', () {
    final theme = ThemeData.dark(useMaterial3: true);
    expect(theme.bz.background, const Color(0xFF000000));
    expect(theme.bzAccent, const Color(0xFFFFFFFF));
  });

  test('plain Flutter host light theme has safe semantic fallback', () {
    final theme = ThemeData.light(useMaterial3: true);
    expect(theme.bzBackground, BzThemeColors.light.background);
  });

  test('official V8 dark tokens are true OLED black and silent white', () {
    final colors = bzDarkTheme().bz;
    expect(colors.background, const Color(0xFF000000));
    expect(colors.accent, const Color(0xFFFFFFFF));
  });
}
