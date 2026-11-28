"""Regression tests for the repo-wide dependency lock coverage gate."""
import tempfile
import unittest
from pathlib import Path

from v8_dependency_inventory import dependency_inventory


class DependencyInventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def create(self, relative: str, content: str = "") -> Path:
        file = self.root / relative
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")
        return file

    def test_node_package_without_lock_is_blocking(self):
        self.create("backend/api/package.json", '{"name":"breezze"}')
        self.assertEqual(
            dependency_inventory(self.root),
            ["NODE_LOCK_MISSING: backend/api/package.json"],
        )

    def test_root_workspace_lock_can_cover_nested_package(self):
        self.create("backend/api/package.json", '{"name":"breezze"}')
        self.create("package-lock.json", "{}")
        self.assertEqual(dependency_inventory(self.root), [])

    def test_dart_app_without_lock_is_blocking_but_library_is_not(self):
        self.create("apps/mobile/pubspec.yaml", "name: breezze")
        self.create("packages/api_client/pubspec.yaml", "name: breezze_api_client")
        self.assertEqual(
            dependency_inventory(self.root),
            ["DART_LOCK_MISSING: apps/mobile/pubspec.yaml"],
        )
        self.create("apps/mobile/pubspec.lock")
        self.assertEqual(dependency_inventory(self.root), [])

    def test_unpinned_python_runtime_is_flagged(self):
        self.create(
            "backend/ytmusicapi/requirements.txt",
            "# comment\nfastapi>=0.115,<1\nuvicorn==0.30.0\n",
        )
        self.assertEqual(
            dependency_inventory(self.root),
            ["PYTHON_RANGE_UNPINNED: backend/ytmusicapi/requirements.txt:2"],
        )

    def test_generated_and_cached_manifests_are_excluded(self):
        self.create("node_modules/fixture/package.json", "{}")
        self.create("apps/mobile/build/test/package.json", "{}")
        self.assertEqual(dependency_inventory(self.root), [])


if __name__ == "__main__":
    unittest.main()
