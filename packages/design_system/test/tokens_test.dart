import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Locks the Apple Music "Liquid Glass" token contract (§2/§3/§4/§6).
/// If one of these values changes by accident, this suite fails CI.
void main() {
  group('BzColorsLight — §2.1 palette contract', () {
    test('ground is cool #f5f5f7, never warm cream', () {
      expect(BzColorsLight.background, const Color(0xFFF5F5F7));
    });

    test('surface and hover ladder', () {
      expect(BzColorsLight.surfacePrimary, const Color(0xFFFFFFFF));
      expect(BzColorsLight.surfaceSecondary, const Color(0xFFFBFBFD));
    });

    test('accent is #0071e3, reserved for primary actions and active nav', () {
      expect(BzColorsLight.accent, const Color(0xFF0071E3));
      expect(BzColorsLight.accentOnTint, const Color(0xFF0066CC));
    });

    test('text hierarchy follows the grayscale ladder', () {
      expect(BzColorsLight.textPrimary, const Color(0xFF1D1D1F));
      expect(BzColorsLight.textSecondary, const Color(0xFF6E6E73));
      expect(BzColorsLight.textTertiary, const Color(0xFF86868B));
      expect(BzColorsLight.textQuaternary, const Color(0xFFAEAEB2));
    });

    test('hairline separator is 7% black', () {
      expect(BzColorsLight.separator, const Color(0x12000000));
    });
  });

  group('BzColorsDark — §2.1 palette contract', () {
    test('ground collapses to pure black for OLED efficiency', () {
      expect(BzColorsDark.background, const Color(0xFF000000));
    });

    test('surface ladder', () {
      expect(BzColorsDark.surfacePrimary, const Color(0xFF1C1C1E));
      expect(BzColorsDark.surfaceSecondary, const Color(0xFF2C2C2E));
    });

    test('accent is #0a84ff', () {
      expect(BzColorsDark.accent, const Color(0xFF0A84FF));
      expect(BzColorsDark.accentOnTint, const Color(0xFF409CFF));
    });

    test('glass fills follow the material state opacities', () {
      // pill-scrolled: 85–95% near-opaque surface fill.
      expect(BzColorsDark.atmoRegular, const Color(0xE01C1C1E));
      // media-overlay: demoted canvas-55% recipe, overlay chrome only.
      expect(BzColorsDark.atmoClear, const Color(0x8C1C1C1E));
    });
  });

  group('BzGradients — signature gradients only', () {
    test('hero gradient is blue-to-indigo', () {
      expect(BzGradients.hero.colors, const [
        Color(0xFF0A84FF),
        Color(0xFF5E5CE6),
      ]);
    });

    test('warm gradient is warm-to-heat', () {
      expect(BzGradients.warm.colors, const [
        Color(0xFFFF9F0A),
        Color(0xFFFF375F),
      ]);
    });
  });

  group('BzSpacing — 8pt grid (§2.3)', () {
    test('spec scale is increments of 8', () {
      for (final v in [
        BzSpacing.space1,
        BzSpacing.space2,
        BzSpacing.space3,
        BzSpacing.space4,
        BzSpacing.space5,
      ]) {
        expect(v % 8, 0, reason: '$v must be an increment of 8');
      }
    });

    test('spec scale values', () {
      expect(BzSpacing.space1, 8);
      expect(BzSpacing.space2, 16);
      expect(BzSpacing.space3, 24);
      expect(BzSpacing.space4, 32);
      expect(BzSpacing.space5, 48);
    });

    test('tap targets are 44pt minimum — non-negotiable (NFR-006)', () {
      expect(BzSpacing.tapTarget, greaterThanOrEqualTo(44));
    });
  });

  group('BzRadius — semantic scale (§2.3)', () {
    test('semantic values', () {
      expect(BzRadius.sm, 4);
      expect(BzRadius.standard, 8);
      expect(BzRadius.md, 12);
      expect(BzRadius.lg, 20);
      expect(BzRadius.xl, 32);
      expect(BzRadius.pill, 999);
    });

    test('legacy aliases resolve to the semantic scale', () {
      expect(BzRadius.button, BzRadius.standard);
      expect(BzRadius.input, BzRadius.md);
      expect(BzRadius.card, BzRadius.md);
      expect(BzRadius.sheet, BzRadius.lg);
      expect(BzRadius.modal, BzRadius.xl);
      expect(BzRadius.capsule, BzRadius.pill);
    });
  });

  group('BzShadow — depth, not decoration (§2.4)', () {
    test('glass soft is low-opacity, large-radius, downward', () {
      expect(BzShadow.glassSoft.offset.dy, 8);
      expect(BzShadow.glassSoft.blurRadius, 32);
      expect(BzShadow.glassSoft.color, const Color(0x1F000000));
    });

    test('glass medium lifts modals and overlay chrome', () {
      expect(BzShadow.glassMedium.offset.dy, 12);
      expect(BzShadow.glassMedium.blurRadius, 48);
      expect(BzShadow.glassMedium.color, const Color(0x2E000000));
    });
  });

  group('BzSprings — physics-based motion (§6)', () {
    test('press/pill spring is stiffness 1755 at damping ratio 0.85', () {
      expect(BzSprings.press.stiffness, 1755);
      expect(BzSprings.pill.stiffness, 1755);
      expect(BzSprings.press.dampingRatio, closeTo(0.85, 0.01));
      expect(BzSprings.pill.dampingRatio, closeTo(0.85, 0.01));
    });

    test('hero/glass-morph spring is response 0.5 at damping ratio 0.85', () {
      expect(BzSprings.hero.stiffness, closeTo(157.9, 0.1));
      expect(BzSprings.glassMorph.stiffness, closeTo(157.9, 0.1));
      expect(BzSprings.hero.dampingRatio, closeTo(0.85, 0.01));
      expect(BzSprings.glassMorph.dampingRatio, closeTo(0.85, 0.01));
    });
  });

  group('BzTypography — fluid roles (§3)', () {
    test('display clamps to 27–46', () {
      expect(BzTypography.displaySize(320), 27);
      expect(BzTypography.displaySize(1200), 46);
      final mid = BzTypography.displaySize(800);
      expect(mid, inInclusiveRange(27, 46));
    });

    test('h2 clamps to 20–26', () {
      expect(BzTypography.h2Size(320), 20);
      expect(BzTypography.h2Size(1400), 26);
      expect(BzTypography.h2Size(800), inInclusiveRange(20, 26));
    });

    test('caption is 12pt, button/action is 15pt w600', () {
      expect(BzTypography.caption.fontSize, 12);
      expect(BzTypography.action.fontSize, 15);
      expect(BzTypography.action.fontWeight, FontWeight.w600);
    });
  });

  group('BzBreakpoints — responsive shell (§4.1/§4.2)', () {
    test('breakpoints match the shell contract', () {
      expect(BzBreakpoints.medium, 810); // < 810: bottom tab bar
      expect(BzBreakpoints.expanded, 1200); // >= 1200: full sidebar
    });

    test('shell geometry', () {
      expect(BzBreakpoints.sidebarWidth, 260);
      expect(BzBreakpoints.iconRailWidth, 72);
      expect(BzBreakpoints.sidePanelWidth, 300);
      expect(BzBreakpoints.playerPillBottomInset, 20);
      expect(BzBreakpoints.playerPillHorizontalMargin, 16);
    });
  });

  group('BzThemeColors — theme extension wiring', () {
    testWidgets('light theme exposes the Liquid Glass tokens', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzLightTheme(),
          home: Builder(
            builder: (context) {
              final c = Theme.of(context).bz;
              expect(c.background, BzColorsLight.background);
              expect(c.accent, BzColorsLight.accent);
              expect(c.text3, BzColorsLight.textTertiary);
              expect(c.text4, BzColorsLight.textQuaternary);
              expect(c.hairline, BzColorsLight.separator);
              expect(c.accentOnTint, BzColorsLight.accentOnTint);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('dark theme exposes the Liquid Glass tokens', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: Builder(
            builder: (context) {
              final c = Theme.of(context).bz;
              expect(c.background, BzColorsDark.background);
              expect(c.accent, BzColorsDark.accent);
              expect(c.text3, BzColorsDark.textTertiary);
              expect(c.text4, BzColorsDark.textQuaternary);
              expect(c.hairline, BzColorsDark.separator);
              expect(c.accentOnTint, BzColorsDark.accentOnTint);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('BzThemeX aliases resolve the new tokens', (tester) async {
      late ThemeData captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: bzDarkTheme(),
          home: Builder(
            builder: (context) {
              captured = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured.bzText3, BzColorsDark.textTertiary);
      expect(captured.bzText4, BzColorsDark.textQuaternary);
      expect(captured.bzHairline, BzColorsDark.separator);
      expect(captured.bzAccentOnTint, BzColorsDark.accentOnTint);
    });
  });
}
