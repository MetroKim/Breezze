"""V8-only plan authority must be a tested, non-destructive repository invariant."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check_v8_plan_authority.py")
spec = importlib.util.spec_from_file_location("v8_guard", SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class V8PlanAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.write("docs/BREEZZE_UNIFIED_ENGINE_V8_IMPLEMENTATION_PLAN.md", "# V8")
        self.write(
            "BREEZZE_MASTER_PLAN.txt",
            "BREEZZE UNIFIED MASTER PLAN V8\n"
            "docs/BREEZZE_UNIFIED_ENGINE_V8_IMPLEMENTATION_PLAN.md\n",
        )

    def write(self, path: str, content: str):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def test_only_v8_passes(self):
        self.assertEqual(guard.check(self.root), [])

    def test_obsolete_v7_plan_file_is_rejected(self):
        self.write("docs/BREEZZE_MASTER_PLAN_V7.md", "# Previous")
        self.assertTrue(
            any("OBSOLETE_PLAN_PRESENT" in x for x in guard.check(self.root))
        )

    def test_old_v6_reference_is_rejected(self):
        self.write("README.md", "[old](docs/architecture/BREEZZE_V6_MAINLINE_INTEGRATION.md)")
        self.assertTrue(
            any("OBSOLETE_PLAN_REFERENCE" in x for x in guard.check(self.root))
        )

    def test_broken_root_pointer_is_rejected(self):
        self.write("BREEZZE_MASTER_PLAN.txt", "BREEZZE UNIFIED MASTER PLAN V7")
        self.assertTrue(
            any("V8_ROOT_POINTER_STALE" in x for x in guard.check(self.root))
        )

    def test_historical_artifact_is_preserved(self):
        self.write(
            "docs/archive/legacy-pr-patches/README.md",
            "Past: BREEZZE_MASTER_PLAN_V7.md",
        )
        self.assertEqual(guard.check(self.root), [])

    def test_missing_master_is_rejected(self):
        (self.root / guard.CANONICAL).unlink()
        self.assertTrue(
            any("V8_PLAN_MISSING" in x for x in guard.check(self.root))
        )


if __name__ == "__main__":
    unittest.main()
