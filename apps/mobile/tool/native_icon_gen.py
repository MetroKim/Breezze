#!/usr/bin/env python3
"""Build Breezze launchers from the exact approved pixel-B SVG; no dependencies.

Invoke only after flutter create has produced native Android/iOS runner files.
Only supported SVG M/L/Z path syntax is accepted; unknown artwork fails closed.
"""
from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
import zlib

SVG_NS = '{http://www.w3.org/2000/svg}'
ANDROID_NS = 'http://schemas.android.com/apk/res/android'
PNG_MAGIC = b'\x89PNG\r\n\x1a\n'
TOKEN = re.compile(r'[MLZ]|-?(?:\d+\.?\d*|\.\d+)')
DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
APPROVED_SVG_BLOB = 'f03421141c8486a190a93021d6e594d053dce147'


def read_official_svg(path: Path):
    data = path.read_bytes()
    blob_hash = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if blob_hash != APPROVED_SVG_BLOB:
        raise ValueError('Official SVG hash changed; owner approval required before changing the Breezze mark')
    root = ET.parse(path).getroot()
    if root.tag != SVG_NS + 'svg' or root.get('viewBox') != '0 0 1024 1024':
        raise ValueError('Unsupported canonical SVG viewport')
    group = root.find(SVG_NS + 'g')
    if group is None or group.get('transform') != 'translate(305,174) scale(1.87)':
        raise ValueError('Official pixel-B transform changed: review the icon renderer')
    elements = group.findall(SVG_NS + 'path')
    if len(elements) != 2 or any(p.get('fill-rule') != 'evenodd' for p in elements):
        raise ValueError('Canonical Breezze pixel-B must have two even-odd paths')
    paths = [p.get('d', '') for p in elements]
    polygons = []
    for data in paths:
        tokens = TOKEN.findall(data)
        if ''.join(tokens) != re.sub(r'[\s,]+', '', data):
            raise ValueError('Unsupported SVG path commands; cannot invent geometry')
        i, parts, current = 0, [], None
        while i < len(tokens):
            command = tokens[i]
            i += 1
            if command in ('M', 'L'):
                if i + 1 >= len(tokens):
                    raise ValueError('Incomplete pixel-B path')
                point = (305 + 1.87 * float(tokens[i]), 174 + 1.87 * float(tokens[i + 1]))
                i += 2
                if command == 'M':
                    if current is not None:
                        raise ValueError('Unclosed SVG subpath')
                    current = []
                if current is None:
                    raise ValueError('SVG must start each subpath with M')
                current.append(point)
            elif command == 'Z':
                if current is None or len(current) < 3:
                    raise ValueError('Empty SVG subpath')
                parts.append(current)
                current = None
            else:
                raise ValueError('Only absolute M/L/Z geometry is permitted')
        if current is not None:
            raise ValueError('SVG path did not close')
        polygons.append(parts)
    return paths, polygons


def render_pixel_b(size: int, polygons) -> bytes:
    # Opaque square: the OS supplies outer launcher corner masking.
    samples = 3 if size >= 512 else 4
    coverage = [0.0] * (size * size)
    factor = size / 1024.0
    for subrow in range(size * samples):
        y = (subrow + 0.5) / (factor * samples)
        start = (subrow // samples) * size
        for component in polygons:
            xs = []
            for polygon in component:
                for a, b in zip(polygon, polygon[1:] + polygon[:1]):
                    if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                        xs.append((a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])) * factor)
            xs.sort()
            if len(xs) % 2:
                raise ValueError('Invalid polygon scanline intersections')
            for index in range(0, len(xs), 2):
                left, right = max(0.0, xs[index]), min(float(size), xs[index + 1])
                if right <= left:
                    continue
                for x in range(int(left), min(size, math.ceil(right))):
                    coverage[start + x] += max(0.0, min(x + 1.0, right) - max(x, left)) / samples
    rgb = bytearray(size * size * 3)
    for index, value in enumerate(coverage):
        shade = round(5 + 250 * min(1.0, value))
        rgb[index * 3:index * 3 + 3] = bytes((shade, shade, shade))
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack('!I', len(payload)) + kind + payload + struct.pack('!I', binascii.crc32(kind + payload) & 0xFFFFFFFF)
    rows = b''.join(b'\x00' + rgb[i * size * 3:(i + 1) * size * 3] for i in range(size))
    return PNG_MAGIC + chunk(b'IHDR', struct.pack('!2I5B', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')


def vector_xml(paths) -> bytes:
    ET.register_namespace('android', ANDROID_NS)
    ns = '{%s}' % ANDROID_NS
    vector = ET.Element('vector', {ns+'width': '108dp', ns+'height': '108dp', ns+'viewportWidth': '1024', ns+'viewportHeight': '1024'})
    safe = ET.SubElement(vector, 'group', {ns+'pivotX': '512', ns+'pivotY': '512', ns+'scaleX': '0.88', ns+'scaleY': '0.88'})
    mark = ET.SubElement(safe, 'group', {ns+'translateX': '305', ns+'translateY': '174', ns+'scaleX': '1.87', ns+'scaleY': '1.87'})
    for data in paths:
        ET.SubElement(mark, 'path', {ns+'fillColor': '#FFFFFFFF', ns+'fillType': 'evenOdd', ns+'pathData': data})
    return ET.tostring(vector, encoding='utf-8', xml_declaration=True)


def generate(app_dir: Path, verify=False) -> list[str]:
    icons = app_dir / 'assets/icons'
    paths, polygons = read_official_svg(icons / 'breezze-app-icon.svg')
    outputs = {}
    for density, size in DENSITIES.items():
        outputs[app_dir / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'] = render_pixel_b(size, polygons)
    resources = app_dir / 'android/app/src/main/res'
    vector = vector_xml(paths)
    outputs[resources / 'drawable/ic_breezze_foreground.xml'] = vector
    outputs[resources / 'drawable/ic_breezze_monochrome.xml'] = vector
    outputs[resources / 'values/breezze_icon_colors.xml'] = b'<?xml version="1.0" encoding="utf-8"?><resources><color name="breezze_icon_background">#050505</color></resources>'
    adaptive = (b'<?xml version="1.0" encoding="utf-8"?>'
                b'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
                b'<background android:drawable="@color/breezze_icon_background"/>'
                b'<foreground android:drawable="@drawable/ic_breezze_foreground"/>'
                b'<monochrome android:drawable="@drawable/ic_breezze_monochrome"/>'
                b'</adaptive-icon>')
    outputs[resources / 'mipmap-anydpi-v26/ic_launcher.xml'] = adaptive
    outputs[resources / 'mipmap-anydpi-v26/ic_launcher_round.xml'] = adaptive
    ios_icons = app_dir / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    manifest = ios_icons / 'Contents.json'
    if not manifest.is_file():
        raise FileNotFoundError(f'Generate the iOS Flutter runner before icon sync: {manifest}')
    entries = json.loads(manifest.read_text(encoding='utf-8')).get('images', [])
    for entry in entries:
        name = entry.get('filename')
        if not name:
            continue
        size = float(entry['size'].split('x')[0]) * float(entry['scale'].removesuffix('x'))
        pixels = round(size)
        if abs(pixels - size) > 0.01 or pixels < 16 or pixels > 1024:
            raise ValueError(f'Unexpected iOS launcher size: {entry!r}')
        outputs[ios_icons / name] = render_pixel_b(pixels, polygons)
    if not any(path.suffix == '.png' for path in outputs if ios_icons in path.parents):
        raise ValueError('No generated iOS icon entries detected')
    outputs[icons / 'launcher.png'] = render_pixel_b(1024, polygons)
    for dest, content in outputs.items():
        if verify:
            if not dest.is_file() or dest.read_bytes() != content:
                raise ValueError(f'Native launcher mismatch: {dest}')
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(content)
    return [str(p.relative_to(app_dir)) for p in outputs]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-dir', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--verify', action='store_true', help='Fail if native files differ from canonical SVG')
    args = parser.parse_args()
    files = generate(args.app_dir, args.verify)
    print(f'Breezze official pixel-B native icon {"verification PASS" if args.verify else "generation PASS"}: {len(files)} files')


if __name__ == '__main__':
    main()
