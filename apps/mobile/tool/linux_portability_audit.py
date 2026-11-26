#!/usr/bin/env python3
"""Pre-release Linux Flutter bundle audit.

This checks structural integrity, ELF architecture and dynamic link dependencies
without launching a GUI or publishing an installer. It cannot prove that audio,
desktop portals, media keys or every Linux distribution works.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import sys
from pathlib import Path

MACHINES = {"x86_64": 62, "aarch64": 183}
NEEDED = (
    "breezze",
    "data/icudtl.dat",
    "data/flutter_assets",
    "lib/libflutter_linux_gtk.so",
)
FORBIDDEN_SUFFIXES = {".dart", ".ts", ".map", ".pem", ".key"}
FORBIDDEN_NAMES = {".env", ".env.production", "credentials.json"}


class BundleAuditError(RuntimeError):
    pass


def elf_machine(path: Path) -> int:
    with path.open("rb") as handle:
        header = handle.read(20)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise BundleAuditError(f"Not an ELF binary: {path}")
    if header[4] != 2 or header[5] != 1:
        raise BundleAuditError(f"Only little-endian 64-bit ELF is audited: {path}")
    return struct.unpack_from("<H", header, 18)[0]


def strip_unneeded_linux_jni_bridge(bundle: Path) -> bool:
    """Remove Android's JNI bridge only if no packaged ELF links against it.

    The Flutter dependency graph may copy libdartjni.so into Linux bundles
    even though Linux playback uses its own media engine and no JVM.
    We cannot waive unresolved dependencies in the final bundle audit:
    instead, prove no ELF DT_NEEDED references before removing the exact
    unused bridge. A live launch/MPRIS probe follows in CI.
    Dynamic FFI/Java use still needs separate playback acceptance.
    """
    bundle = bundle.resolve()
    bridge = bundle / "lib" / "libdartjni.so"
    if not bridge.exists() and not bridge.is_symlink():
        return False
    if bridge.is_symlink() or not bridge.is_file():
        raise BundleAuditError("JNI bridge must be a regular bundled file")
    native_objects = [bundle / "breezze"]
    native_objects.extend(sorted(
        path for path in (bundle / "lib").rglob("*")
        if path.is_file() and path != bridge
        and (path.name.endswith(".so") or ".so." in path.name)
    ))
    for path in native_objects:
        result = subprocess.run(
            ["readelf", "-d", str(path)],
            text=True, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise BundleAuditError(
                f"Cannot inspect native dependencies for {path.name}"
            )
        if "Shared library: [libdartjni.so]" in result.stdout:
            raise BundleAuditError(
                f"Required JNI bridge cannot be stripped: {path.name}"
            )
    bridge.unlink()
    return True


def audit_bundle(bundle: Path, arch: str, check_linker: bool = False) -> dict:
    bundle = bundle.resolve()
    if not bundle.is_dir():
        raise BundleAuditError(f"Flutter release bundle not found: {bundle}")
    if arch not in MACHINES:
        raise BundleAuditError(f"Unsupported Linux bundle architecture: {arch}")
    for relative in NEEDED:
        if not (bundle / relative).exists():
            raise BundleAuditError(f"Missing release bundle component: {relative}")
    assets = bundle / "data" / "flutter_assets"
    if not assets.is_dir():
        raise BundleAuditError("flutter_assets must be a directory")

    # No packaged symlink may escape the bundle. That would both break
    # portability and potentially dereference host files in an installer.
    for candidate in bundle.rglob("*"):
        if candidate.is_symlink():
            try:
                target = candidate.resolve(strict=True)
            except (OSError, RuntimeError) as exc:
                raise BundleAuditError(
                    f"Broken or cyclic release symlink: {candidate}"
                ) from exc
            if not target.is_relative_to(bundle):
                raise BundleAuditError(
                    f"Release symlink escapes bundle: {candidate}"
                )

    elf_paths = [bundle / "breezze"]
    # Check versioned ELF libraries too, not just '*.so' soname symlinks.
    elf_paths.extend(sorted(
        path for path in (bundle / "lib").rglob("*")
        if path.is_file() and (
            path.name.endswith(".so") or ".so." in path.name
        )
    ))
    for path in elf_paths:
        actual = elf_machine(path)
        if actual != MACHINES[arch]:
            raise BundleAuditError(
                f"Wrong ELF machine for {path.name}: {actual}, expected {MACHINES[arch]}"
            )

    leaked = [
        str(path.relative_to(bundle))
        for path in bundle.rglob("*")
        if path.is_file()
        and (path.suffix.lower() in FORBIDDEN_SUFFIXES
             or path.name.lower() in FORBIDDEN_NAMES)
    ]
    if leaked:
        raise BundleAuditError(
            "Developer source, keys or maps in release bundle: " + ", ".join(leaked[:10])
        )

    if check_linker:
        for path in elf_paths:
            # Shared-library checks need the exact Flutter bundle lib dir,
            # just as the installed executable would supply it via RPATH.
            env = dict(os.environ)
            env["LD_LIBRARY_PATH"] = (
                str(bundle / "lib") + ":" + env.get("LD_LIBRARY_PATH", "")
            )
            result = subprocess.run(
                ["ldd", str(path)], text=True, capture_output=True,
                check=False, env=env,
            )
            output = result.stdout + result.stderr
            if result.returncode != 0 or "not found" in output:
                raise BundleAuditError(
                    f"Unresolved native dependency: {path.name}: {output[-1800:]}"
                )

    return {
        "format": "Breezze Linux ELF QA v1",
        "arch": arch,
        "executable": "breezze",
        "checked_native_objects": len(elf_paths),
        "linker_checked": check_linker,
        "release_approved": False,
        "claims": ["bundle structure", "ELF architecture", "no source/key files"]
        + (["host dynamic dependencies resolved"] if check_linker else []),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--arch", choices=sorted(MACHINES), required=True)
    parser.add_argument("--check-linker", action="store_true")
    parser.add_argument(
        "--strip-unused-linux-jni", action="store_true",
        help="Prove no ELF uses the Android-only JNI bridge, then remove it",
    )
    args = parser.parse_args(argv)
    try:
        stripped = False
        if args.strip_unused_linux_jni:
            # Validate the original artifact before changing its contents.
            audit_bundle(args.bundle, args.arch)
            stripped = strip_unneeded_linux_jni_bridge(args.bundle)
        report = audit_bundle(args.bundle, args.arch, args.check_linker)
        report["stripped_unused_linux_jni"] = stripped
    except (BundleAuditError, OSError) as exc:
        print(f"LINUX BUNDLE FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
