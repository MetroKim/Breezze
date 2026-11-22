import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Characterization tests for the Liquid Glass token layer.
///
/// These pin every value in the token layer to the Apple Music spec so
/// any drift (an accidental color change, a blur value tweak, a
/// mis-mapped breakpoint) fails CI instead of silently shipping.
void main() {
  group('BzGlassColorsLight — §2.1', () {
    test('ground is the cool #f5f5f7, never warm cream', () {
      expect(BzGlassColorsLight.ground, const Color(0xFFF5F5F7));
    });

    test('surface and surfaceHover match spec', () {
      expect(BzGlassColorsLight.surface, const Color(0xFFFFFFFF));
      expect(BzGlassColorsLight.surfaceHover, const Color(0xFFFBFBFD));
    });

    test('text hierarchy uses exact spec values', () {
      expect(BzGlassColorsLight.textPrimary, const Color(0xFF1D1D1F));
      expect(BzGlassColorsLight.textBody, const Color(0xFF424245));
      expect(BzGlassColorsLight.textSecondary, const Color(0xFF6E6E73));
      expect(BzGlassColorsLight.textTertiary, const Color(0xFF86868B));
      expect(BzGlassColorsLight.textQuaternary, const Color(0xFFAEAEB2));
    });

    test('accent is #0071e3', () {
      expect(BzGlassColorsLight.accent, const Color(0xFF0071E3));
      expect(BzGlassColorsLight.accentOnTint, const Color(0xFF0066CC));
    });

    test('hairline is rgba(0,0,0,0.07)', () {
      expect(BzGlassColorsLight.hairline, const Color(0x12000000));
    });

    test('live indicator is #30d158', () {
      expect(BzGlassColorsLight.live, const Color(0xFF30D158));
    });
  });

  group('BzGlassColorsDark — §2.1', () {
    test('ground is pure black for OLED efficiency', () {
      expect(BzGlassColorsDark.ground, const Color(0xFF000000));
    });

    test('surface and surfaceHover match spec', () {
      expect(BzGlassColorsDark.surface, const Color(0xFF1C1C1E));
      expect(BzGlassColorsDark.surfaceHover, const Color(0xFF2C2C2E));
    });

    test('text hierarchy uses white at spec alphas', () {
      expect(BzGlassColorsDark.textPrimary, const Color(0xFFFFFFFF));
      expect(BzGlassColorsDark.textBody, const Color(0xD9FFFFFF)); // 85%
      expect(BzGlassColorsDark.textSecondary, const Color(0xA6FFFFFF)); // 65%
      expect(BzGlassColorsDark.textTertiary, const Color(0x73FFFFFF)); // 45%
      expect(BzGlassColorsDark.textQuaternary, const Color(0x4DFFFFFF)); // 30%
    });

    test('accent is #0a84ff', () {
      expect(BzGlassColorsDark.accent, const Color(0xFF0A84FF));
      expect(BzGlassColorsDark.accentOnTint, const Color(0xFF409CFF));
    });

    test('hairline is rgba(255,255,255,0.1)', () {
      expect(BzGlassColorsDark.hairline, const Color(0x1AFFFFFF));
    });
  });

  group('BzGlassGradients — signature gradients', () {
    test('blue-to-indigo gradient is exactly #0a84ff to #5e5ce6', () {
      expect(BzGlassGradients.blueIndigo, const [
        Color(0xFF0A84FF),
        Color(0xFF5E5CE6),
      ]);
    });

    test('warm-to-heat gradient is exactly #ff9f0a to #ff375f', () {
      expect(BzGlassGradients.warmHeat, const [
        Color(0xFFFF9F0A),
        Color(0xFFFF375F),
      ]);
    });
  });

  group('BzGlassMaterial — §2.2 the four glass states', () {
    test('pillScrolled is the .glass-pill-scrolled contract', () {
      final recipe = BzGlassRecipe.of(BzGlassMaterial.pillScrolled);
      // background: rgba(28,28,30,0.88); saturate(180%) blur(16px)
      expect(recipe.fillOpacity, 0.88);
      expect(recipe.blurSigma, 16);
      expect(recipe.saturateBoost, 1.8);
    });

    test('pillAtTop is 70-80% opacity with no blur', () {
      final recipe = BzGlassRecipe.of(BzGlassMaterial.pillAtTop);
      expect(recipe.fillOpacity, inInclusiveRange(0.70, 0.80));
      expect(recipe.blurSigma, 0);
    });

    test('mediaOverlay is the overlay-chrome-only recipe', () {
      final recipe = BzGlassRecipe.of(BzGlassMaterial.mediaOverlay);
      expect(recipe.fillOpacity, inInclusiveRange(0.4, 0.6));
      expect(recipe.blurSigma, greaterThan(0));
    });

    test('clear has no blur backing — tint/border only', () {
      final recipe = BzGlassRecipe.of(BzGlassMaterial.clear);
      expect(recipe.blurSigma, 0);
      expect(recipe.fillOpacity, 0.0);
    });

    test('dark scrolled fill resolves to rgba(28,28,30,0.88)', () {
      final fill =
          BzGlassRecipe.fillOf(Brightness.dark, BzGlassMaterial.pillScrolled);
      // Component-wise: withValues-created colors are float-backed, so
      // compare channels with tolerance instead of whole-color equality.
      expect(fill.alpha, closeTo(0.88 * 255, 1));
      expect(fill.red, 28);
      expect(fill.green, 28);
      expect(fill.blue, 30);
    });

    test('light scrolled fill resolves to rgba(255,255,255,0.88)', () {
      final fill = BzGlassRecipe.fillOf(
          Brightness.light, BzGlassMaterial.pillScrolled);
      expect(fill.alpha, closeTo(0.88 * 255, 1));
      expect(fill.red, 255);
      expect(fill.green, 255);
      expect(fill.blue, 255);
    });
  });

  group('BzGlassBudget — NFR-007 / PRT-09', () {
    test('maximum visible blurred surfaces is 2', () {
      expect(BzGlassBudget.maxVisibleBlurredSurfaces, 2);
    });
  });

  group('BzGlassSpacing — 8pt grid', () {
    test('all values are increments of 8', () {
      for (final value in const [
        BzGlassSpacing.space1,
        BzGlassSpacing.space2,
        BzGlassSpacing.space3,
        BzGlassSpacing.space4,
        BzGlassSpacing.space5,
      ]) {
        expect(value % 8, 0, reason: '$value is not an 8pt increment');
      }
    });

    test('scale matches spec: 8, 16, 24, 32, 48', () {
      expect(BzGlassSpacing.space1, 8);
      expect(BzGlassSpacing.space2, 16);
      expect(BzGlassSpacing.space3, 24);
      expect(BzGlassSpacing.space4, 32);
      expect(BzGlassSpacing.space5, 48);
    });
  });

  group('BzGlassRadius — semantic scale', () {
    test('scale matches spec: 4, 8, 12, 20, 32, pill 9999', () {
      expect(BzGlassRadius.sm, 4);
      expect(BzGlassRadius.dfault, 8);
      expect(BzGlassRadius.md, 12);
      expect(BzGlassRadius.lg, 20);
      expect(BzGlassRadius.xl, 32);
      expect(BzGlassRadius.pill, 9999);
    });
  });

  group('BzGlassMetrics — NFR-006', () {
    test('tap target is 44pt minimum, non-negotiable', () {
      expect(BzGlassMetrics.tapTarget, 44);
      expect(BzGlassMetrics.playButtonVisual, 56);
    });
  });

  group('BzGlassType — §3 typography roles', () {
    test('display role matches spec', () {
      expect(BzGlassType.display.fontSize, 34);
      expect(BzGlassType.display.fontWeight, FontWeight.w700);
      expect(BzGlassType.display.letterSpacingEm, -0.03);
      expect(BzGlassType.display.height, inInclusiveRange(1.1, 1.18));
    });

    test('h2 section title role matches spec', () {
      expect(BzGlassType.h2.fontSize, 22);
      expect(BzGlassType.h2.fontWeight, FontWeight.w700);
      expect(BzGlassType.h2.letterSpacingEm, -0.02);
      expect(BzGlassType.h2.height, 1.25);
    });

    test('h3 item title role matches spec', () {
      expect(BzGlassType.h3.fontSize, 17);
      expect(BzGlassType.h3.fontWeight, FontWeight.w600);
      expect(BzGlassType.h3.letterSpacingEm, -0.01);
      expect(BzGlassType.h3.height, inInclusiveRange(1.4, 1.45));
    });

    test('caption role is 12px 400 tracking 0', () {
      expect(BzGlassType.caption.fontSize, 12);
      expect(BzGlassType.caption.fontWeight, FontWeight.w400);
      expect(BzGlassType.caption.letterSpacingEm, 0);
      expect(BzGlassType.caption.height, 1.33);
    });

    test('button role is 15px 600', () {
      expect(BzGlassType.button.fontSize, 15);
      expect(BzGlassType.button.fontWeight, FontWeight.w600);
    });

    test('tracking resolves in logical px scaled to font size', () {
      final style = BzGlassType.display.style(const Color(0xFFFFFFFF));
      expect(style.letterSpacing, closeTo(-1.02, 0.001));
    });

    test('font family stays null — system-native stack only', () {
      final style = BzGlassType.h3.style(const Color(0xFF000000));
      expect(style.fontFamily, isNull);
      expect(style.fontFamilyFallback, isNull);
    });
  });

  group('BzGlassMotion — §6 physics-first motion', () {
    test('press spring is stiffness ~1755, damping 0.85', () {
      expect(BzGlassMotion.pressStiffness, 1755);
      expect(BzGlassMotion.pressDamping, 0.85);
    });

    test('hero spring is response 0.5, dampingFraction 0.85', () {
      expect(BzGlassMotion.heroSpringResponse, 0.5);
      expect(BzGlassMotion.heroSpringDampingFraction, 0.85);
    });

    test('duration tokens are reserved for opacity-only fades', () {
      expect(BzGlassMotion.modalFade, const Duration(milliseconds: 200));
      expect(BzGlassMotion.barAdaptMin, const Duration(milliseconds: 180));
      expect(BzGlassMotion.barAdaptMax, const Duration(milliseconds: 240));
    });

    test('immersive chrome recedes after 3s to opacity 0.15', () {
      expect(
          BzGlassMotion.immersiveRecedeDelay, const Duration(seconds: 3));
      expect(BzGlassMotion.immersiveRecedeOpacity, 0.15);
    });
  });

  group('BzGlassBreakpoints — §4.2 shell behavior', () {
    test('sidebar is 260px; icon rail is 72px; side panel is 300px', () {
      expect(BzGlassBreakpoints.sidebarWidth, 260);
      expect(BzGlassBreakpoints.sidebarIconRailWidth, 72);
      expect(BzGlassBreakpoints.sidePanelWidth, 300);
    });

    test('breakpoints are 810 and 1200', () {
      expect(BzGlassBreakpoints.medium, 810);
      expect(BzGlassBreakpoints.expanded, 1200);
    });

    test('player pill anchors at bottom 20px with 16px compact margins', () {
      expect(BzGlassBreakpoints.playerPillBottomInset, 20);
      expect(BzGlassBreakpoints.playerPillCompactHorizontalMargin, 16);
    });
  });
}
