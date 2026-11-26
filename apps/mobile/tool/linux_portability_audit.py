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

    elf_paths = [bundle / "breezze"]
    elf_paths.extend(sorted((bundle / "lib").rglob("*.so")))
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
    args = parser.parse_args(argv)
    try:
        report = audit_bundle(args.bundle, args.arch, args.check_linker)
    except (BundleAuditError, OSError) as exc:
        print(f"LINUX BUNDLE FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
