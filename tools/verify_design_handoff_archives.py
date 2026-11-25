#!/usr/bin/env python3
"""Verify exact original Breezze design references, never deploy mock code."""
from __future__ import annotations

from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile, BadZipFile
from xml.etree import ElementTree
from pathlib import PurePosixPath
import sys

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "docs" / "design" / "reference"
DESIGN = REF / "Breezze_Frontend_Figma_Import_Pack.zip"
FLUTTER = REF / "breezze_flutter_ui_reference.zip"
CHECKSUMS = {
    DESIGN.name: "6a9fdb04a023ef99c074d23a3deef98b67935067f6df85734603509a7afe5435",
    FLUTTER.name: "140eafd2a95cc9edacd20816861eccd94a28acad1c7ab3d09647ff92af831c40",
}
SCREENS = (
    "01_Home", "02_Browse", "03_Library", "04_Search",
    "05_Now_Playing", "06_Lyrics", "07_Artist", "08_Album",
    "09_Playlist", "10_Sign_In", "11_Settings", "12_Downloads",
    "13_Queue", "14_Onboarding", "15_Replay", "16_Account",
)
EXPECTED_DESIGN = {name + ".svg" for name in SCREENS} | {
    "Breezze_Frontend_16_Screen_Board.svg",
    "Breezze_Frontend_16_Screen_Board.png",
    "README.md",
}


def verify_zip(path: Path, expected_hash: str) -> ZipFile:
    if not path.is_file():
        raise AssertionError(f"Missing original source archive: {path}")
    digest = sha256(path.read_bytes()).hexdigest()
    if digest != expected_hash:
        raise AssertionError(f"{path.name}: SHA-256 mismatch")
    archive = ZipFile(path)
    if archive.testzip() is not None:
        raise AssertionError(f"{path.name}: corrupt ZIP entry")
    for name in archive.namelist():
        part = PurePosixPath(name)
        if part.is_absolute() or ".." in part.parts:
            raise AssertionError(f"Unsafe ZIP entry: {name}")
    return archive


def main() -> None:
    try:
        with verify_zip(DESIGN, CHECKSUMS[DESIGN.name]) as design:
            if set(design.namelist()) != EXPECTED_DESIGN:
                raise AssertionError("Design pack expected original 16 screens, board SVG/PNG and README")
            for name in sorted(EXPECTED_DESIGN):
                if not name.endswith(".svg"):
                    continue
                svg = ElementTree.fromstring(design.read(name))
                if not svg.tag.endswith("}svg"):
                    raise AssertionError(f"{name}: not SVG XML")
                expected = "0 0 1780 3850" if "Board" in name else "0 0 390 844"
                if svg.attrib.get("viewBox") != expected:
                    raise AssertionError(f"{name}: unexpected viewport")
            if not design.read("Breezze_Frontend_16_Screen_Board.png").startswith(
                b"\\x89PNG\\r\\n\\x1a\\n"
            ):
                raise AssertionError("Invalid Figma board PNG")
        with verify_zip(FLUTTER, CHECKSUMS[FLUTTER.name]) as reference:
            original = set(reference.namelist())
            for path in (
                "bitchord_flutter/lib/screens/now_playing_screen.dart",
                "bitchord_flutter/lib/screens/artist_screen.dart",
                "bitchord_flutter/lib/screens/lyrics_screen.dart",
                "bitchord_flutter/lib/data/mock_catalog.dart",
                "bitchord_flutter/lib/state/player_state.dart",
                "bitchord_flutter/README.md",
            ):
                if path not in original:
                    raise AssertionError(f"Missing historical UI reference: {path}")
        print("Breezze design handoff verified: 16 SVG screens, board SVG/PNG and Flutter reference")
    except (AssertionError, BadZipFile, ValueError) as exc:
        print(f"Design source verification failed: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
