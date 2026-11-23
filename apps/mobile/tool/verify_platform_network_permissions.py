#!/usr/bin/env python3
"""Fail CI if generated native runners lack release outbound networking.

Flutter-generated debug manifest may permit Internet even when release does
not. Check main (shared) Android manifest and both macOS build entitlements.
"""
import argparse
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}name"
ANDROID_PERMISSIONS = {
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
}

def check_android(root: Path) -> list[str]:
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    if not manifest.is_file():
        return [f"Missing Android main release manifest: {manifest}"]
    try:
        xml = ET.parse(manifest).getroot()
    except (ET.ParseError, OSError) as error:
        return [f"Invalid Android main manifest: {error}"]
    present = {
        element.attrib.get(ANDROID_NS)
        for element in xml.findall("uses-permission")
    }
    return [
        f"Android release manifest lacks {permission}"
        for permission in sorted(ANDROID_PERMISSIONS - present)
    ]

def check_macos(root: Path) -> list[str]:
    errors: list[str] = []
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        path = root / "macos/Runner" / name
        if not path.is_file():
            errors.append(f"Missing macOS entitlement file: {path}")
            continue
        try:
            with path.open("rb") as f:
                entitlements = plistlib.load(f)
            if entitlements.get("com.apple.security.network.client") is not True:
                errors.append(f"macOS outbound network entitlement missing: {path}")
        except (OSError, ValueError, TypeError) as error:
            errors.append(f"Could not inspect {path}: {error}")
    return errors

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", action="store_true")
    parser.add_argument("--macos", action="store_true")
    args = parser.parse_args()
    if not (args.android or args.macos):
        parser.error("Select --android and/or --macos")
    root = Path(__file__).resolve().parents[1]
    errors = []
    if args.android:
        errors.extend(check_android(root))
    if args.macos:
        errors.extend(check_macos(root))
    if errors:
        for error in errors:
            print("RELEASE NETWORK FAIL:", error, file=sys.stderr)
        return 1
    print("Release network permission verification passed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
