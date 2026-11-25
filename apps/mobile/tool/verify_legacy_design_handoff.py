#!/usr/bin/env python3
"""Verify Breezze's archived original design handoffs (Python stdlib only).

These are *historical sources*, never a production Flutter/catalog dependency.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
from struct import unpack_from
from xml.etree import ElementTree
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[3]
ARCHIVE = ROOT / "docs/design/legacy-handoff/originals"
EXPECTED = {
    "Breezze_Frontend_Figma_Import_Pack.zip": "6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435",
    "breezze_flutter(1).zip": "140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40",
    "Breezze Music Brand Styleboard.png": "d8e02e118262add42e598892bfcd2fef0239d07d6d7df5a53f92c9a2b6a0887c",
    "Breezze Music Brand Guideline Board.png": "393b6cf6572ed03051e329b87b067e1070b95d684308547b642593c51e4ba231",
    "Breezze Music Branding Collection.png": "92c76ef08b277acd5f38d191f0148d9d76977cf12c9e485d60098f0f39427eb0",
}


def verify() -> None:
    for name, expected in EXPECTED.items():
        path = ARCHIVE / name
        assert path.is_file(), f"Missing historical source: {path}"
        data = path.read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        assert actual == expected, f"SHA-256 mismatch for {name}: {actual}"
        if path.suffix == ".png":
            assert data.startswith(b"\x89PNG\r\n\x1a\n"), f"Not PNG: {name}"
            assert unpack_from(">II", data, 16) == (1536, 1024), f"Board dimensions: {name}"
        if path.suffix == ".zip":
            with ZipFile(path) as archive:
                assert archive.testzip() is None, f"Corrupt ZIP: {name}"
                if name.startswith("Breezze_Frontend"):
                    screens = [entry for entry in archive.namelist()
                               if entry[:2].isdigit() and entry.endswith(".svg")]
                    assert len(screens) == 16, f"Expected 16 Figma screens, got {len(screens)}"
                    svgs = [entry for entry in archive.namelist() if entry.endswith(".svg")]
                    assert len(svgs) == 17, f"Expected 17 editable Figma SVGs, got {len(svgs)}"
                    for entry in svgs:
                        ElementTree.fromstring(archive.read(entry))
        print(f"PASS {name}: {len(data)} original bytes, exact SHA-256")

    for variant in ("black", "white"):
        path = ROOT / f"apps/mobile/assets/icons/breezze-logo-{variant}.svg"
        ElementTree.fromstring(path.read_bytes())
        print(f"PASS Breezze monochrome {variant} SVG")


if __name__ == "__main__":
    verify()