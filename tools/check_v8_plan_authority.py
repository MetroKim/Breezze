#!/usr/bin/env python3
"""Prevent obsolete Breezze master-plan versions from re-entering main.

This checks only working-tree active documentation, not historical Git commits.
It never scans or logs credentials, source contents, or media assets.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CANONICAL = Path("docs/BREEZZE_UNIFIED_ENGINE_V8_IMPLEMENTATION_PLAN.md")
ROOT_POINTER = Path("BREEZZE_MASTER_PLAN.txt")
OLD_PLAN_NAME = re.compile(
    r"(?:BREEZZE_MASTER_PLAN_V[1-7]|BREEZZE_V[1-7]_MAINLINE_INTEGRATION)\.md",
    flags=re.IGNORECASE,
)
DOCUMENT_EXTENSIONS = {".md", ".txt", ".yml", ".yaml", ".html"}
SKIP_DIRS = {".git", ".dart_tool", "node_modules", "build", "dist", ".venv", "__pycache__"}


def check(root: Path) -> list[str]:
    issues = []
    plan = root / CANONICAL
    pointer = root / ROOT_POINTER
    if not plan.is_file():
        issues.append(f"V8_PLAN_MISSING: {CANONICAL}")
    if not pointer.is_file():
        issues.append(f"V8_ROOT_POINTER_MISSING: {ROOT_POINTER}")
    elif (str(CANONICAL) not in pointer.read_text(encoding="utf-8")
          or "MASTER PLAN V8" not in pointer.read_text(encoding="utf-8")):
        issues.append(f"V8_ROOT_POINTER_STALE: {ROOT_POINTER}")

    import os
    for base, subdirs, files in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if d not in SKIP_DIRS)
        directory = Path(base)
        for name in sorted(files):
            file = directory / name
            relative = file.relative_to(root)
            if "docs/archive/" in relative.as_posix() or "docs/design/reference/" in relative.as_posix():
                # Immutable historic evidence is not a live master plan.
                continue
            if OLD_PLAN_NAME.search(name) and file.suffix == ".md":
                issues.append(f"OBSOLETE_PLAN_PRESENT: {relative}")
            if file.suffix.lower() not in DOCUMENT_EXTENSIONS:
                continue
            # Scanning only active text docs: avoid images, ZIPs, binaries,
            # generated source and any secrets or local environment files.
            try:
                lines = file.read_text(encoding="utf-8").splitlines()
            except UnicodeError:
                issues.append(f"ACTIVE_DOCUMENT_UNREADABLE: {relative}")
                continue
            for number, line in enumerate(lines, 1):
                if OLD_PLAN_NAME.search(line):
                    issues.append(f"OBSOLETE_PLAN_REFERENCE: {relative}:{number}")
    return issues


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    issues = check(root)
    for issue in issues:
        print(issue)
    print("BREEZZE_CANONICAL_PLAN: " + ("V8_ONLY" if not issues else "FAIL"))
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
