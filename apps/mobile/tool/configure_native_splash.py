#!/usr/bin/env python3
"""Generate Breezze's true-black native launch from its original logo *mark*.

Works on checked-in assets and Flutter-created runner shells. No third-party
logo, extra app-icon background, external image processing tool or network call.
"""
from __future__ import annotations

import json
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("android", ANDROID_NS)


def a(name: str) -> str:
    return "{" + ANDROID_NS + "}" + name


def configure(app_dir: Path) -> None:
    symbols = app_dir / "assets/icons"
    original = ET.parse(symbols / "breezze-symbol-white.svg").getroot()
    app_icon = ET.parse(symbols / "breezze-app-icon.svg").getroot()
    paths = [p.get("d") for p in original.findall(f"{{{SVG_NS}}}path")]
    app_icon_paths = [p.get("d") for p in app_icon.findall(f"{{{SVG_NS}}}g/{{{SVG_NS}}}path")]
    if not paths or paths != app_icon_paths:
        raise ValueError("Official mark paths differ from the Breezze app icon")
    if original.attrib.get("viewBox") != "0 0 222 363":
        raise ValueError("Unexpected official mark viewport")

    # Android: the original B-note itself is white, on a separate flat-black
    # launch window. Neither branding nor source paths are redrawn.
    res = app_dir / "android/app/src/main/res"
    if (res.parent / "AndroidManifest.xml").exists():
        drawable = res / "drawable"
        drawable.mkdir(parents=True, exist_ok=True)
        vector = ET.Element("vector", {
            a("width"): "60dp", a("height"): "98dp",
            a("viewportWidth"): "222", a("viewportHeight"): "363",
        })
        for d in paths:
            ET.SubElement(vector, "path", {
                a("fillColor"): "#FFFFFFFF",
                a("fillType"): "evenOdd",
                a("pathData"): d,
            })
        ET.ElementTree(vector).write(
            drawable / "breezze_splash_mark.xml", encoding="utf-8",
            xml_declaration=True,
        )
        background = ET.Element("layer-list")
        ET.SubElement(background, "item", {
            a("drawable"): "@android:color/black",
        })
        ET.SubElement(background, "item", {
            a("drawable"): "@drawable/breezze_splash_mark",
            a("gravity"): "center",
        })
        ET.ElementTree(background).write(
            drawable / "breezze_launch_background.xml",
            encoding="utf-8", xml_declaration=True,
        )
        for folder in ("values", "values-night"):
            xml_file = res / folder / "styles.xml"
            if not xml_file.exists():
                continue
            tree = ET.parse(xml_file)
            for style in tree.getroot().findall("style"):
                name = style.get("name")
                if name not in ("LaunchTheme", "NormalTheme"):
                    continue
                window = next((item for item in style.findall("item")
                               if item.get("name") == "android:windowBackground"), None)
                if window is None:
                    window = ET.SubElement(style, "item",
                                           {"name": "android:windowBackground"})
                window.text = ("@drawable/breezze_launch_background"
                               if name == "LaunchTheme" else "@android:color/black")
            tree.write(xml_file, encoding="utf-8", xml_declaration=True)

        # Android 12+ shows a system splash *before* Flutter/launch_background.
        v31 = res / "values-v31"
        v31.mkdir(parents=True, exist_ok=True)
        v31_file = v31 / "styles.xml"
        if v31_file.exists():
            tree = ET.parse(v31_file)
            root = tree.getroot()
        else:
            root = ET.Element("resources")
            tree = ET.ElementTree(root)
        launch = next((x for x in root.findall("style")
                       if x.get("name") == "LaunchTheme"), None)
        if launch is None:
            launch = ET.SubElement(root, "style", {
                "name": "LaunchTheme",
                "parent": "@android:style/Theme.Material.Light.NoActionBar",
            })
        for key, value in {
            "android:windowSplashScreenBackground": "#000000",
            "android:windowSplashScreenAnimatedIcon":
                "@drawable/breezze_splash_mark",
            "android:windowBackground": "@drawable/breezze_launch_background",
        }.items():
            item = next((x for x in launch.findall("item")
                         if x.get("name") == key), None)
            if item is None:
                item = ET.SubElement(launch, "item", {"name": key})
            item.text = value
        normal = next((x for x in root.findall("style")
                       if x.get("name") == "NormalTheme"), None)
        if normal is None:
            normal = ET.SubElement(root, "style", {
                "name": "NormalTheme",
                "parent": "@android:style/Theme.Material.Light.NoActionBar",
            })
        item = next((x for x in normal.findall("item")
                     if x.get("name") == "android:windowBackground"), None)
        if item is None:
            item = ET.SubElement(normal, "item",
                                 {"name": "android:windowBackground"})
        item.text = "@android:color/black"
        tree.write(v31_file, encoding="utf-8", xml_declaration=True)

    # iOS: use a transparent raster of the same original SVG vector inside
    # a black native storyboard. Keep launch content still and centered.
    storyboard = app_dir / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
    if storyboard.exists():
        catalog = (app_dir /
                   "ios/Runner/Assets.xcassets/BreezzeLaunchMark.imageset")
        catalog.mkdir(parents=True, exist_ok=True)
        source = symbols / "breezze_native_launch_mark.png"
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copyfile(source, catalog / "BreezzeLaunchMark.png")
        (catalog / "Contents.json").write_text(json.dumps({
            "images": [{
                "filename": "BreezzeLaunchMark.png",
                "idiom": "universal",
            }],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")

        tree = ET.parse(storyboard)
        root = tree.getroot()
        view = next(root.iter("view"), None)
        if view is None:
            raise ValueError("Generated iOS launch storyboard is missing a view")
        for child in list(view):
            if child.tag == "color" and child.get("key") == "backgroundColor":
                view.remove(child)
        ET.SubElement(view, "color", {
            "key": "backgroundColor", "red": "0", "green": "0",
            "blue": "0", "alpha": "1", "colorSpace": "custom",
            "customColorSpace": "sRGB",
        })
        image_views = list(root.iter("imageView"))
        if not image_views:
            raise ValueError("Generated iOS storyboard is missing a launch image")
        for element in image_views:
            if element.get("image") in ("LaunchImage", "BreezzeLaunchMark"):
                element.set("image", "BreezzeLaunchMark")
                element.set("contentMode", "scaleAspectFit")
                constraints = element.find("constraints")
                if constraints is None:
                    constraints = ET.SubElement(element, "constraints")
                for attr, value in (("width", "55"), ("height", "90")):
                    if not any(c.get("firstAttribute") == attr
                               for c in constraints.findall("constraint")):
                        ET.SubElement(constraints, "constraint", {
                            "firstAttribute": attr, "constant": value,
                            "id": "breezze-splash-" + attr,
                        })
        resources = root.find("resources")
        if resources is None:
            resources = ET.SubElement(root, "resources")
        for image in list(resources.findall("image")):
            if image.get("name") == "LaunchImage":
                resources.remove(image)
        if not any(image.get("name") == "BreezzeLaunchMark"
                   for image in resources.findall("image")):
            ET.SubElement(resources, "image", {
                "name": "BreezzeLaunchMark", "width": "55", "height": "90",
            })
        tree.write(storyboard, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: configure_native_splash.py <apps/mobile>")
    configure(Path(sys.argv[1]))
    print("Breezze native launch: OLED black + original transparent white B-note")
