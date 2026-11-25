#!/usr/bin/env python3
"""Generate native Breezze launcher assets from the approved original pixel-B SVG.

Requires CairoSVG==2.7.1 and Pillow==11.3.0.
Run: python apps/mobile/tool/sync_native_icons.py [--check]
Do not modify/reinterpret the official pixel-B path geometry.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from cairosvg import svg2png
from PIL import Image

APP = Path(__file__).resolve().parents[1]
SVG = APP / 'assets/icons/breezze-app-icon.svg'
ANDROID = APP / 'android/app/src/main/res'
IOS = APP / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
SVG_NS = '{http://www.w3.org/2000/svg}'
PIXEL_B_BG = '#050505'
APPROVED_GIT_BLOB_SHA1 = 'f03421141c8486a190a93021d6e594d053dce147'


def verify_source(source: str) -> list[str]:
    raw = source.encode('utf-8')
    git_blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    if git_blob != APPROVED_GIT_BLOB_SHA1:
        raise RuntimeError('Official Breezze icon source changed; owner review required')
    root = ET.fromstring(source)
    if root.tag != SVG_NS + 'svg' or root.attrib.get('viewBox') != '0 0 1024 1024':
        raise RuntimeError('Invalid official Breezze SVG viewBox')
    paths = root.findall('.//' + SVG_NS + 'path')
    if len(paths) != 2 or any(p.get('fill-rule') != 'evenodd' for p in paths):
        raise RuntimeError('Expected exactly two official evenodd pixel-B paths')
    data = [p.attrib['d'] for p in paths]
    if any(not re.fullmatch(r'[MLZmlz0-9, .-]+', d) for d in data):
        raise RuntimeError('Unapproved source geometry format')
    groups = root.findall('.//' + SVG_NS + 'g')
    if len(groups) != 1 or groups[0].get('transform') != 'translate(305,174) scale(1.87)':
        raise RuntimeError('Canonical pixel-B transform changed')
    return data


def png(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(
        path, format='PNG', optimize=True)


def android_vector(paths: list[str]) -> str:
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:width="108dp" android:height="108dp"',
        '    android:viewportWidth="1024" android:viewportHeight="1024">',
        '  <group android:translateX="347" android:translateY="240"',
        '         android:scaleX="1.5" android:scaleY="1.5">'
    ]
    for path in paths:
        lines += ['    <path android:fillColor="#FFFFFFFF"',
                  '        android:fillType="evenOdd"',
                  f'        android:pathData="{path}"/>']
    return '\n'.join(lines + ['  </group>', '</vector>', ''])


def render(android: Path, ios: Path) -> None:
    source = SVG.read_text(encoding='utf-8')
    paths = verify_source(source)
    # The OS applies its own rounded mask. Composite transparent corners over
    # official #050505 for opaque iOS PNGs; never redraw the pixel-B paths.
    source_png = svg2png(bytestring=source.encode(), output_width=1024, output_height=1024)
    image = Image.open(io.BytesIO(source_png)).convert('RGBA')
    opaque = Image.new('RGB', image.size, PIXEL_B_BG)
    opaque.paste(image, mask=image.getchannel('A'))
    densities = {'mdpi':48, 'hdpi':72, 'xhdpi':96, 'xxhdpi':144, 'xxxhdpi':192}
    for density, size in densities.items():
        png(opaque, android / ('mipmap-' + density) / 'ic_launcher.png', size)
    drawable = android / 'drawable'
    drawable.mkdir(parents=True, exist_ok=True)
    for name in ('ic_breezze_foreground.xml', 'ic_breezze_monochrome.xml'):
        (drawable / name).write_text(android_vector(paths), encoding='utf-8')
    values = android / 'values'
    values.mkdir(parents=True, exist_ok=True)
    (values / 'breezze_icon_colors.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n  <color name="breezze_icon_background">#050505</color>\n'
        '</resources>\n', encoding='utf-8')
    adaptive = android / 'mipmap-anydpi-v26'
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@color/breezze_icon_background"/>\n'
        '  <foreground android:drawable="@drawable/ic_breezze_foreground"/>\n'
        '  <monochrome android:drawable="@drawable/ic_breezze_monochrome"/>\n'
        '</adaptive-icon>\n', encoding='utf-8')
    ios.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, str]] = []
    written: set[str] = set()
    combos = [
        ('iphone', 20, ('2x','3x')), ('iphone', 29, ('2x','3x')),
        ('iphone', 40, ('2x','3x')), ('iphone', 60, ('2x','3x')),
        ('ipad', 20, ('1x','2x')), ('ipad', 29, ('1x','2x')),
        ('ipad', 40, ('1x','2x')), ('ipad', 76, ('1x','2x')),
        ('ipad', 83.5, ('2x',))
    ]
    for idiom, points, scales in combos:
        for scale in scales:
            count = int(round(points * int(scale[0])))
            name = str(points)
            if '.' in name:
                name = name.rstrip('0').rstrip('.')
            filename = f'Icon-App-{name}x{name}@{scale}.png'
            if filename not in written:
                png(opaque, ios / filename, count)
                written.add(filename)
            entries.append({'filename': filename, 'idiom': idiom,
                            'scale': scale, 'size': f'{points}x{points}'})
    png(opaque, ios / 'Icon-App-1024x1024@1x.png', 1024)
    entries.append({'filename': 'Icon-App-1024x1024@1x.png',
                    'idiom':'ios-marketing', 'scale':'1x', 'size':'1024x1024'})
    (ios / 'Contents.json').write_text(json.dumps(
        {'images': entries, 'info': {'author':'xcode','version':1}}, indent=2
    ) + '\n', encoding='utf-8')
    print(f'Generated native Breezze official icons: {len(densities)} Android PNGs, '
          f'2 Android adaptive vectors, {len(written)+1} iOS PNGs and Contents.json')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not args.check:
        render(ANDROID, IOS)
        return
    with tempfile.TemporaryDirectory(prefix='breezze-icons-') as temp:
        root = Path(temp)
        render(root/'android', root/'ios')
        differences = []
        for candidate in root.rglob('*'):
            if not candidate.is_file():
                continue
            rel = candidate.relative_to(root)
            expected = (
                ANDROID / rel.relative_to('android')
                if rel.parts[0] == 'android' else
                IOS / rel.relative_to('ios')
            )
            if not expected.is_file() or candidate.read_bytes() != expected.read_bytes():
                differences.append(str(expected))
        if differences:
            raise SystemExit('Missing or altered official native assets:\n' + '\n'.join(differences))
    print('PASS: every native Breezze icon matches the canonical pixel-B source')


if __name__ == '__main__':
    main()
