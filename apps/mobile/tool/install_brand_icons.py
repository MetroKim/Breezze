#!/usr/bin/env python3
"""Install the exact supplied Breezze SVG mark into Flutter-generated runners.

Usage: python tool/install_brand_icons.py
Requires Pillow (installed by CI's Python setup); no Figma, Flutter test
harness, web service, or hardcoded customer data is involved.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parents[1]
SOURCE = APP / "assets/icons/breezze-app-icon.svg"
SVG_NS = "{http://www.w3.org/2000/svg}"


def source_image() -> Image.Image:
    root = ET.fromstring(SOURCE.read_text(encoding="utf-8"))
    if root.attrib.get("viewBox") != "0 0 1024 1024":
        raise ValueError("Unexpected Breezze launcher SVG viewBox")
    background = root.find(f"{SVG_NS}rect")
    group = root.find(f"{SVG_NS}g")
    if background is None or group is None:
        raise ValueError("Breezze launcher icon must have background and mark")

    match = re.fullmatch(
        r"translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+)\)",
        group.attrib["transform"],
    )
    if not match:
        raise ValueError("Unsupported transform in official Breezze SVG")
    tx, ty, factor = map(float, match.groups())
    paths = list(group.findall(f"{SVG_NS}path"))
    if len(paths) != 2 or background.attrib.get("fill") != "#050505":
        raise ValueError("Breezze source paths or background have changed; verify asset")

    supersample = 2
    resolution = 1024 * supersample
    image = Image.new("RGBA", (resolution, resolution), (0, 0, 0, 0))
    painter = ImageDraw.Draw(image)
    painter.rounded_rectangle(
        (0, 0, resolution - 1, resolution - 1),
        radius=218 * supersample,
        fill=(5, 5, 5, 255),
    )

    for element in paths:
        commands = re.findall(r"[MLZ]|-?\d+(?:\.\d+)?", element.attrib["d"])
        polygons: list[list[tuple[float, float]]] = []
        polygon: list[tuple[float, float]] = []
        values: list[float] = []
        command = None
        for token in commands:
            if token in {"M", "L", "Z"}:
                if token == "Z":
                    if polygon:
                        polygons.append(polygon)
                    polygon = []
                else:
                    command = token
                continue
            if command not in {"M", "L"}:
                raise ValueError("Unsupported instruction in Breezze icon path")
            values.append(float(token))
            if len(values) == 2:
                x, y = values
                polygon.append((
                    (tx + factor * x) * supersample,
                    (ty + factor * y) * supersample,
                ))
                values.clear()
        if polygon:
            polygons.append(polygon)
        for index, polygon in enumerate(polygons):
            # The second SVG path has an even-odd interior cutout.
            fill = (255, 255, 255, 255) if index == 0 else (5, 5, 5, 255)
            painter.polygon(polygon, fill=fill)

    return image.resize((1024, 1024), Image.Resampling.LANCZOS)


def main() -> None:
    original = source_image()
    cache: dict[int, Image.Image] = {1024: original}

    def resized(size: int) -> Image.Image:
        if size not in cache:
            cache[size] = original.resize((size, size), Image.Resampling.LANCZOS)
        return cache[size]

    def write_png(path: Path, size: int, *, opaque: bool = False) -> None:
        if not path.parent.is_dir():
            return
        artwork = resized(size)
        if opaque:
            # iOS's flat AppIcon asset catalog cannot contain an alpha channel.
            # Preserve the supplied white symbol, flatten only the transparent
            # corner pixels onto the official #050505 background. iOS applies
            # its own rounded mask to the resulting opaque icon.
            canvas = Image.new("RGBA", artwork.size, (5, 5, 5, 255))
            canvas.alpha_composite(artwork)
            artwork = canvas.convert("RGB")
        artwork.save(path, format="PNG", optimize=True)
        print(f"Breezze brand icon {path.relative_to(APP)} ({size}px)")

    assets = APP / "build" / "brand"
    assets.mkdir(parents=True, exist_ok=True)
    write_png(assets / "breezze-app-icon-1024.png", 1024)

    android = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, pixels in android.items():
        write_png(
            APP / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
            pixels,
        )

    for folder in (
        APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset",
        APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset",
    ):
        contents = folder / "Contents.json"
        if not contents.is_file():
            continue
        manifest = json.loads(contents.read_text(encoding="utf-8"))
        for item in manifest.get("images", []):
            filename = item.get("filename")
            size = item.get("size")
            scale = item.get("scale")
            if not filename or not size or not scale:
                continue
            logical = float(size.split("x")[0])
            pixel_size = int(round(logical * float(scale.rstrip("x"))))
            write_png(
                folder / filename, pixel_size,
                opaque=folder.relative_to(APP).parts[0] == "ios",
            )

    write_png(APP / "web/favicon.png", 48)
    for name, pixels in (
        ("Icon-192.png", 192),
        ("Icon-512.png", 512),
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ):
        write_png(APP / "web/icons" / name, pixels)

    windows = APP / "windows/runner/resources/app_icon.ico"
    if windows.parent.is_dir():
        original.save(
            windows,
            format="ICO",
            sizes=[(n, n) for n in [16, 24, 32, 48, 64, 128, 256]],
        )
        print(f"Breezze Windows icon {windows.relative_to(APP)}")

    linux = APP / "linux"
    if linux.is_dir():
        (linux / "assets").mkdir(exist_ok=True)
        write_png(linux / "assets/breezze.png", 256)

    print("Breezze supplied SVG installed as launcher icons for generated platforms.")


if __name__ == "__main__":
    main()
