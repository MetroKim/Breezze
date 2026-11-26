#!/usr/bin/env python3
"""Read-only Breezze dependency reproducibility gate.

Never prints dependency values, lockfile contents, credentials, or source.
This reports *coverage*, not a vulnerability-free verdict. The separate OSV,
Semgrep, CodeQL and Gitleaks jobs provide the actual detection layers.
"""
from __future__ import annotations

import argparse
from pathlib import Path

SKIP_DIRS = {
    ".git", ".dart_tool", ".pub-cache", ".venv", "venv",
    "node_modules", "build", "dist", "coverage", "__pycache__",
}
NODE_LOCKS = ("package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml",
              "yarn.lock", "bun.lock", "bun.lockb")


def _project_files(root: Path, filename: str) -> list[Path]:
    import os

    found: list[Path] = []
    for directory, folders, files in os.walk(root):
        folders[:] = sorted(folder for folder in folders if folder not in SKIP_DIRS)
        if filename in files:
            found.append(Path(directory) / filename)
    return sorted(found)


def dependency_inventory(root: Path) -> list[str]:
    """Return reproducibility violations for manifests in the complete tree."""
    root = root.resolve()
    failures: list[str] = []
    for manifest in _project_files(root, "package.json"):
        # npm workspaces can share a parent lockfile.
        folder = manifest.parent
        has_lock = False
        while folder == root or root in folder.parents:
            if any((folder / lock).is_file() for lock in NODE_LOCKS):
                has_lock = True
                break
            if folder == root:
                break
            folder = folder.parent
        if not has_lock:
            failures.append(f"NODE_LOCK_MISSING: {manifest.relative_to(root)}")

    mobile = root / "apps" / "mobile"
    if (mobile / "pubspec.yaml").is_file() and not (mobile / "pubspec.lock").is_file():
        failures.append("DART_LOCK_MISSING: apps/mobile/pubspec.yaml")

    for manifest in _project_files(root, "requirements.txt"):
        # A requirements file with compatible ranges is not a resolved lock.
        # A fully hashed lock file is preferred for production; a fixed,
        # direct requirement is the *minimum* this inventory can inspect.
        for line_no, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
            requirement = raw.strip()
            if (not requirement or requirement.startswith("#") or
                    requirement.startswith(("-", "--"))):
                continue
            if "==" not in requirement and "===" not in requirement:
                failures.append(
                    f"PYTHON_RANGE_UNPINNED: {manifest.relative_to(root)}:{line_no}"
                )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    args = parser.parse_args()
    if not args.root.is_dir():
        print("DEPENDENCY_INVENTORY_INVALID_ROOT")
        return 2
    failures = dependency_inventory(args.root)
    for issue in failures:
        print(issue)
    print(f"DEPENDENCY_LOCK_COVERAGE: {'PASS' if not failures else 'BLOCKED'}; "
          f"unresolved_gates={len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
