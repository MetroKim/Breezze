#!/usr/bin/env python3
"""Legacy design verification entrypoint, backed by the canonical archive.

The exact original ZIPs, PNG boards and export specifications are stored once
under docs/design/reference. The old CI command remains supported.
"""
from __future__ import annotations

from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from safe_xml import parse_xml_bytes  # noqa: E402


def verify() -> None:
    # Canonical verifier checks SHA-256, ZIP integrity, all 16 screens,
    # original brand PNGs and historical alternative-concept specifications.
    runpy.run_path(
        str(ROOT / "tools" / "verify_design_handoff_archives.py"),
        run_name="__main__",
    )

    # Keep the original active Breezze logo checks from this entrypoint.
    for variant in ("black", "white"):
        path = ROOT / f"apps/mobile/assets/icons/breezze-logo-{variant}.svg"
        parse_xml_bytes(path.read_bytes())
        print(f"PASS Breezze monochrome {variant} SVG")


if __name__ == "__main__":
    verify()
