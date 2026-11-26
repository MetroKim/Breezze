"""Regression checks for the V8 one-design-system source guard."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT_SCRIPT = Path(__file__).with_name("check_v8_ui_single_source.py")
spec = importlib.util.spec_from_file_location("v8_ui_guard", ROOT_SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class V8SingleUiSourceTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.write(guard.TABS, "'Home', 'New', 'Library', 'Search'")
        self.write(guard.SHELL, "IndexedStack( children: [ BzGlassBudgetScope(")
        self.write(guard.THEME, "export 'src/bz_theme.dart';")
        self.write(guard.GLASS_CORE, "BackdropFilter(")
        self.write(guard.GLASS_ADAPTER, "return BzGlass(")
        self.write(guard.BRAND, "class BzBnoteMark class BzBrandLockup")
        self.write(guard.MORPH, "class BzMorphingBrandHeader BzBrandLockup")
        self.write(guard.MOOD, "class BzPinnedMoodRail")
        self.write(guard.DETAIL_BAR, "class BzBrandedAppBar BzCompactBrandMark")

        self.write(guard.PROVIDER, "BzBrandedAppBar(")
        self.write(guard.DEVICE_VIDEO,
                   "BzBrandedAppBar setLooping(next) if (!_repeat && !_closing")
        self.write(guard.OFFICIAL_VIDEO,
                   "BzBrandedAppBar BzSvgIcon(name: 'skip-previous' "
                   "BzSvgIcon(name: 'skip-next'")
        for page in guard.PRIMARY_PAGES:
            self.write(page, "BzMorphingBrandHeader(")
        self.write(guard.PRIMARY_PAGES[0], "BzMorphingBrandHeader( BzPinnedMoodRail(")
        self.write(guard.BROWSE, "BzMorphingBrandHeader( YouTubeMusicClientScreen( featuredDestinations otherDestinations")
        for page in guard.SECONDARY_PAGES:
            self.write(page, "appBar: BzBrandedAppBar(")

    def write(self, name, value):
        file = self.root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(value, encoding="utf-8")

    def test_one_unified_ui_passes(self):
        self.assertEqual(guard.violations(self.root), [])

    def test_reintroduced_blur_renderer_is_rejected(self):
        self.write(guard.GLASS_ADAPTER, "return BzGlass(; BackdropFilter(")
        self.assertIn("SECOND_GLASS_RENDERER", str(guard.violations(self.root)))

    def test_wrong_fourth_or_new_tab_is_rejected(self):
        self.write(guard.TABS, "'Home', 'Browse', 'Library', 'Search'")
        self.assertIn("FOUR_TAB_CONTRACT", str(guard.violations(self.root)))

    def test_duplicate_provider_tab_is_rejected(self):
        self.write(guard.SHELL, "IndexedStack(BzGlassBudgetScope(YouTubeMusicClientScreen()")
        self.assertIn("DUPLICATE_PROVIDER_TAB", str(guard.violations(self.root)))

    def test_provider_legacy_appbar_is_rejected(self):
        self.write(guard.PROVIDER, "BzBrandedAppBar( appBar: AppBar(")
        self.assertIn("LEGACY_PROVIDER_TOOLBAR", str(guard.violations(self.root)))

    def test_licensed_video_must_keep_opt_in_loop_and_svg_controls(self):
        self.write(guard.DEVICE_VIDEO, "BzBrandedAppBar setLooping(next)")
        self.assertIn("LOCAL_VIDEO_REPEAT_DEFAULT_MISSING",
                      str(guard.violations(self.root)))

    def test_official_video_keeps_svg_previous_next(self):
        self.write(guard.OFFICIAL_VIDEO, "BzBrandedAppBar Icons.skip_next")
        issues = str(guard.violations(self.root))
        self.assertIn("OFFICIAL_VIDEO_PREVIOUS_SVG_MISSING", issues)
        self.assertIn("OFFICIAL_VIDEO_NEXT_SVG_MISSING", issues)

    def test_old_black_badge_brand_is_rejected(self):
        self.write(guard.MORPH,
                   "class BzMorphingBrandHeader BzBrandLockup "
                   "color: compact ? Colors.black")
        self.assertIn("OBSOLETE_BLACK_BADGE_BRAND",
                      str(guard.violations(self.root)))

    def test_old_promotional_home_precedes_music_is_rejected(self):
        self.write(
            guard.PRIMARY_PAGES[0],
            "BzMorphingBrandHeader( BzPinnedMoodRail( "
            "BzDiscoverySpotlight( title: 'Recently Played'",
        )
        self.assertIn("HOME_PROMO_ABOVE_MUSIC",
                      str(guard.violations(self.root)))

    def test_old_home_without_pinned_moods_is_rejected(self):
        self.write(guard.PRIMARY_PAGES[0], "BzMorphingBrandHeader(")
        self.assertIn("HOME_PINNED_MOODS_MISSING",
                      str(guard.violations(self.root)))

    def test_two_mood_rails_are_rejected(self):
        self.write(guard.PRIMARY_PAGES[0],
                   "BzMorphingBrandHeader( BzPinnedMoodRail( BzPinnedMoodRail(")
        self.assertIn("DUPLICATE_HOME_MOOD_RAIL",
                      str(guard.violations(self.root)))

    def test_new_cannot_reintroduce_duplicate_destinations(self):
        self.write(guard.BROWSE,
                   "YouTubeMusicClientScreen( featuredDestinations")
        self.assertIn("NEW_DUPLICATE_DESTINATIONS",
                      str(guard.violations(self.root)))

    def test_legacy_static_primary_header_is_rejected(self):
        self.write(guard.PRIMARY_PAGES[0], "BzCompactBrandMark(")
        self.assertIn("OLD_PAGE_HEADER", str(guard.violations(self.root)))

    def test_duplicate_primary_logo_is_rejected(self):
        self.write(
            guard.PRIMARY_PAGES[1],
            "BzMorphingBrandHeader( BzCompactBrandMark(",
        )
        self.assertIn("DUPLICATE_PAGE_BRAND", str(guard.violations(self.root)))

    def test_old_detail_toolbar_is_rejected(self):
        target = guard.SECONDARY_PAGES[0]
        self.write(target, "appBar: AppBar(")
        issues = guard.violations(self.root)
        self.assertTrue(any("LEGACY_DETAIL_TOOLBAR" in x for x in issues))

    def test_vendored_unlicensed_ui_is_rejected(self):
        (self.root / "apps/mobile/lib/ytm_ui_clone").mkdir(parents=True)
        self.assertIn("VENDORED_UNLICENSED_UI_SOURCE",
                      guard.violations(self.root))


if __name__ == "__main__":
    unittest.main()
