import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:breezze_design_system/breezze_design_system.dart';

void main() {
  test('dark theme matches exact black/white Breezze app icon identity', () {
    final dark = bzDarkTheme();
    expect(dark.bzBackground, const Color(0xFF050505));
    expect(dark.bzText1, const Color(0xFFFFFFFF));
    expect(dark.bzAccent, const Color(0xFFFFFFFF));
    expect(dark.colorScheme.primary, dark.bzText1);
    expect(dark.colorScheme.secondary, dark.bzText1);
    expect(dark.scaffoldBackgroundColor, dark.bzBackground);
    expect(dark.filledButtonTheme.style!.backgroundColor!
        .resolve(<WidgetState>{}), dark.bzText1);
    expect(dark.filledButtonTheme.style!.foregroundColor!
        .resolve(<WidgetState>{}), dark.bzBackground);
  });

  test('light theme uses brand charcoal accents and cool grey ground', () {
    final light = bzLightTheme();
    expect(light.bzBackground, const Color(0xFFF6F6F8));
    expect(light.bzText1, const Color(0xFF111114));
    expect(light.bzAccent, const Color(0xFF111114));
    expect(light.colorScheme.primary, light.bzText1);
    expect(light.colorScheme.secondary, light.bzText1);
    expect(light.colorScheme.onPrimary, light.bzBackground);
    expect(light.filledButtonTheme.style!.backgroundColor!
        .resolve(<WidgetState>{}), light.bzText1);
    expect(light.filledButtonTheme.style!.foregroundColor!
        .resolve(<WidgetState>{}), light.bzBackground);
  });

  test('old blue glass accents are replaced by matching neutral accents', () {
    expect(BzLiquidColorsLight.accent, const Color(0xFF111114));
    expect(BzLiquidColorsDark.accent, const Color(0xFFFFFFFF));
    expect(BzLiquidColorsDark.ground, const Color(0xFF050505));
    expect(BzGlassBase.dark, const Color(0xFF171719));
  });
}
