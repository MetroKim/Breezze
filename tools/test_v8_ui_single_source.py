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
        self.write(guard.BRAND, "class BzBnoteMark")
        self.write(guard.MORPH, "class BzMorphingBrandHeader BzBnoteMark")
        self.write(guard.DETAIL_BAR, "class BzBrandedAppBar BzCompactBrandMark")
        self.write(guard.BROWSE, "YouTubeMusicClientScreen(")
        self.write(guard.PROVIDER, "BzBrandedAppBar(")

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

    def test_vendored_unlicensed_ui_is_rejected(self):
        (self.root / "apps/mobile/lib/ytm_ui_clone").mkdir(parents=True)
        self.assertIn("VENDORED_UNLICENSED_UI_SOURCE",
                      guard.violations(self.root))


if __name__ == "__main__":
    unittest.main()
