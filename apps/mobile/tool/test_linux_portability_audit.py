"""Offline security/structure regression tests for the Linux release bundle."""
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from linux_portability_audit import (
    BundleAuditError, audit_bundle, strip_unneeded_linux_jni_bridge,
)


def fake_elf(machine=62):
    header = bytearray(24)
    header[:4] = b"\x7fELF"
    header[4] = 2
    header[5] = 1
    struct.pack_into("<H", header, 18, machine)
    return bytes(header)


class LinuxBundleAuditTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.bundle = Path(self.directory.name) / "bundle"
        (self.bundle / "data" / "flutter_assets").mkdir(parents=True)
        (self.bundle / "lib").mkdir()
        (self.bundle / "data" / "icudtl.dat").write_bytes(b"icu")
        (self.bundle / "breezze").write_bytes(fake_elf())
        (self.bundle / "lib" / "libflutter_linux_gtk.so").write_bytes(fake_elf())

    def test_valid_fake_bundle_is_structurally_accepted(self):
        result = audit_bundle(self.bundle, "x86_64")
        self.assertEqual(result["checked_native_objects"], 2)
        self.assertFalse(result["release_approved"])

    def test_absent_assets_fail_closed(self):
        (self.bundle / "data" / "icudtl.dat").unlink()
        with self.assertRaisesRegex(BundleAuditError, "Missing"):
            audit_bundle(self.bundle, "x86_64")

    def test_wrong_elf_architecture_fails(self):
        (self.bundle / "breezze").write_bytes(fake_elf(machine=183))
        with self.assertRaisesRegex(BundleAuditError, "Wrong ELF machine"):
            audit_bundle(self.bundle, "x86_64")

    def test_source_or_key_in_release_bundle_fails(self):
        (self.bundle / "data" / "flutter_assets" / "private.pem").write_text("test")
        with self.assertRaisesRegex(BundleAuditError, "source, keys"):
            audit_bundle(self.bundle, "x86_64")

    def test_non_elf_library_fails(self):
        (self.bundle / "lib" / "libflutter_linux_gtk.so").write_bytes(b"BAD")
        with self.assertRaisesRegex(BundleAuditError, "Not an ELF"):
            audit_bundle(self.bundle, "x86_64")

    def test_versioned_shared_library_is_validated(self):
        (self.bundle / "lib" / "libcodec.so.2").write_bytes(fake_elf())
        report = audit_bundle(self.bundle, "x86_64")
        self.assertEqual(report["checked_native_objects"], 3)
        (self.bundle / "lib" / "libcodec.so.2").write_bytes(fake_elf(183))
        with self.assertRaisesRegex(BundleAuditError, "Wrong ELF machine"):
            audit_bundle(self.bundle, "x86_64")

    @patch("linux_portability_audit.subprocess.run")
    def test_android_jni_bridge_only_removed_after_dependency_audit(self, run):
        bridge = self.bundle / "lib" / "libdartjni.so"
        bridge.write_bytes(fake_elf())
        run.return_value.returncode = 0
        run.return_value.stdout = (
            "0x0000000000000001 (NEEDED) Shared library: [libc.so.6]"
        )
        self.assertTrue(strip_unneeded_linux_jni_bridge(self.bundle))
        self.assertFalse(bridge.exists())
        self.assertGreaterEqual(run.call_count, 2)
        self.assertEqual(audit_bundle(self.bundle, "x86_64")["checked_native_objects"], 2)

    @patch("linux_portability_audit.subprocess.run")
    def test_required_jni_linkage_stops_strip_and_preserves_bridge(self, run):
        bridge = self.bundle / "lib" / "libdartjni.so"
        bridge.write_bytes(fake_elf())
        run.return_value.returncode = 0
        run.return_value.stdout = (
            "0x0000000000000001 (NEEDED) Shared library: [libdartjni.so]"
        )
        with self.assertRaisesRegex(BundleAuditError, "Required JNI bridge"):
            strip_unneeded_linux_jni_bridge(self.bundle)
        self.assertTrue(bridge.exists())

    @patch("linux_portability_audit.subprocess.run")
    def test_failed_elf_dependency_scan_cannot_strip_bridge(self, run):
        bridge = self.bundle / "lib" / "libdartjni.so"
        bridge.write_bytes(fake_elf())
        run.return_value.returncode = 1
        run.return_value.stdout = ""
        with self.assertRaisesRegex(BundleAuditError, "Cannot inspect"):
            strip_unneeded_linux_jni_bridge(self.bundle)
        self.assertTrue(bridge.exists())

    @patch("linux_portability_audit.subprocess.run")
    def test_missing_android_bridge_is_safe_noop(self, run):
        self.assertFalse(strip_unneeded_linux_jni_bridge(self.bundle))
        run.assert_not_called()

    def test_rejects_symlink_escaping_release_bundle(self):
        (self.bundle / "lib" / "libescape.so").symlink_to("/etc/passwd")
        with self.assertRaisesRegex(BundleAuditError, "symlink escapes"):
            audit_bundle(self.bundle, "x86_64")


if __name__ == "__main__":
    unittest.main()
