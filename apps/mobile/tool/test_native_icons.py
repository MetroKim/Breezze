"""Offline regression tests for the canonical Breezze native icon generator."""
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

from native_icon_gen import generate, read_official_svg


class NativeIconTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app_dir = Path(self.tmp.name)
        root = Path(__file__).resolve().parents[1]
        src = root / 'assets/icons/breezze-app-icon.svg'
        icons = self.app_dir / 'assets/icons'
        icons.mkdir(parents=True)
        shutil.copyfile(src, icons / src.name)
        ios = self.app_dir / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
        ios.mkdir(parents=True)
        (ios / 'Contents.json').write_text(json.dumps({'images': [
            {'filename': 'Icon-App-20x20@2x.png', 'size': '20x20', 'scale': '2x'},
            {'filename': 'Icon-App-60x60@3x.png', 'size': '60x60', 'scale': '3x'},
            {'filename': 'Icon-App-1024x1024@1x.png', 'size': '1024x1024', 'scale': '1x'},
        ]}), encoding='utf-8')

    def test_native_assets_match_only_official_svg(self):
        paths, _ = read_official_svg(self.app_dir / 'assets/icons/breezze-app-icon.svg')
        files = generate(self.app_dir)
        self.assertEqual(len(files), 14)
        self.assertEqual(generate(self.app_dir, verify=True), files)
        for name in ('android/app/src/main/res/drawable/breezze_launcher_monochrome.xml',
                     'android/app/src/main/res/drawable/breezze_launcher_foreground.xml'):
            xml = (self.app_dir / name).read_text()
            for path in paths:
                self.assertIn(path, xml)
        for name, size in [('assets/icons/launcher.png', 1024),
                           ('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72),
                           ('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png', 180)]:
            data = (self.app_dir / name).read_bytes()
            self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            self.assertEqual(struct.unpack('!II', data[16:24]), (size, size))
            self.assertEqual(data[25], 2, 'Opaque RGB avoids rejected iOS alpha channels')
        launcher = self.app_dir / 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png'
        launcher.write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'Native launcher mismatch'):
            generate(self.app_dir, verify=True)

    def test_unknown_geometry_fails_closed(self):
        source = self.app_dir / 'assets/icons/breezze-app-icon.svg'
        source.write_text(source.read_text().replace('M162,183', 'M162,183 C 0,0 1,1 2,2'))
        with self.assertRaisesRegex(ValueError, 'Official SVG hash changed'):
            generate(self.app_dir)


if __name__ == '__main__':
    unittest.main()
