"""The XML audit parser must reject entities and XML-bomb primitives."""
import unittest
from safe_xml import SafeXmlError, parse_xml_bytes


class SafeXmlTest(unittest.TestCase):
    def test_preserves_svg_namespace_and_viewbox(self):
        root = parse_xml_bytes(
            b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 844"/>'
        )
        self.assertTrue(root.tag.endswith("}svg"))
        self.assertEqual(root.attrib["viewBox"], "0 0 390 844")

    def test_android_namespaced_attributes_are_recognized(self):
        root = parse_xml_bytes(
            b'<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            b'<uses-permission android:name="android.permission.INTERNET"/>'
            b'</manifest>'
        )
        permissions = root.findall("uses-permission")
        self.assertEqual(len(permissions), 1)
        self.assertEqual(
            permissions[0].attrib["{http://schemas.android.com/apk/res/android}name"],
            "android.permission.INTERNET",
        )

    def test_rejects_doctype_and_entity_expansion(self):
        malicious = (
            b'<!DOCTYPE svg [<!ENTITY x "huge">]>'
            b'<svg xmlns="http://www.w3.org/2000/svg">&x;</svg>'
        )
        with self.assertRaises(SafeXmlError):
            parse_xml_bytes(malicious)

    def test_rejects_external_entity_reference(self):
        malicious = (
            b'<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
            b'<svg>&x;</svg>'
        )
        with self.assertRaises(SafeXmlError):
            parse_xml_bytes(malicious)

    def test_bounded_input_and_depth(self):
        with self.assertRaises(SafeXmlError):
            parse_xml_bytes(b"<svg/>", max_bytes=2)
        nested = b"<a>" * 130 + b"</a>" * 130
        with self.assertRaises(SafeXmlError):
            parse_xml_bytes(nested)

    def test_malformed_and_multi_root_rejected(self):
        for payload in (b"", b"<svg", b"<a/><b/>"):
            with self.subTest(payload=payload):
                with self.assertRaises(SafeXmlError):
                    parse_xml_bytes(payload)


if __name__ == "__main__":
    unittest.main()
