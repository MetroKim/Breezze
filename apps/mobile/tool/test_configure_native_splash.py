"""Acceptance regression for native OLED splash generation (no Flutter needed)."""
from __future__ import annotations

import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from shutil import copyfile

from configure_native_splash import configure, ANDROID_NS, SVG_NS


class NativeSplashTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="breezze-native-launch-")
        self.addCleanup(self.temp.cleanup)
        self.mobile = Path(self.temp.name) / "mobile"
        icons = self.mobile / "assets/icons"
        icons.mkdir(parents=True)
        original_icons = Path(__file__).resolve().parents[1] / "assets/icons"
        for name in (
            "breezze-symbol-white.svg",
            "breezze-app-icon.svg",
            "breezze_native_launch_mark.png",
        ):
            copyfile(original_icons / name, icons / name)
        res = self.mobile / "android/app/src/main/res"
        res.mkdir(parents=True)
        (res.parent / "AndroidManifest.xml").write_text(
            "<manifest><application /></manifest>"
        )
        for folder in ("values", "values-night"):
            place = res / folder
            place.mkdir()
            (place / "styles.xml").write_text("""
              <resources>
                <style name="LaunchTheme">
                  <item name="android:windowBackground">@drawable/launch_background</item>
                </style>
                <style name="NormalTheme">
                  <item name="android:windowBackground">?android:colorBackground</item>
                </style>
              </resources>
            """)
        storyboard = self.mobile / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
        storyboard.parent.mkdir(parents=True)
        storyboard.write_text("""
        <document>
          <scenes><scene><objects><viewController><view>
            <subviews><imageView image="LaunchImage" id="old" /></subviews>
            <color key="backgroundColor" systemColor="systemBackgroundColor"/>
          </view></viewController></objects></scene></scenes>
          <resources><image name="LaunchImage" width="120" height="120"/></resources>
        </document>
        """)

    def test_original_vector_and_black_android_theme_are_idempotent(self):
        configure(self.mobile)
        configure(self.mobile)
        res = self.mobile / "android/app/src/main/res"
        svg = ET.parse(self.mobile / "assets/icons/breezze-symbol-white.svg").getroot()
        vector = ET.parse(res / "drawable/breezze_splash_mark.xml").getroot()
        expected = [p.get("d") for p in svg.findall(f"{{{SVG_NS}}}path")]
        self.assertEqual(
            [p.get(f"{{{ANDROID_NS}}}pathData") for p in vector.findall("path")],
            expected,
        )
        self.assertEqual(len(vector.findall("path")), 2)
        layer = ET.parse(res / "drawable/breezze_launch_background.xml").getroot()
        self.assertEqual(layer[0].get(f"{{{ANDROID_NS}}}drawable"), "@android:color/black")
        v31 = ET.parse(res / "values-v31/styles.xml").getroot()
        launch = next(s for s in v31.findall("style") if s.get("name") == "LaunchTheme")
        attrs = {x.get("name"): x.text for x in launch.findall("item")}
        self.assertEqual(attrs["android:windowSplashScreenBackground"], "#000000")
        self.assertEqual(attrs["android:windowSplashScreenAnimatedIcon"],
                         "@drawable/breezze_splash_mark")

    def test_ios_uses_transparent_official_image_on_pure_black(self):
        configure(self.mobile)
        configure(self.mobile)
        storyboard = ET.parse(
            self.mobile / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
        ).getroot()
        view = next(storyboard.iter("view"))
        bg = [x for x in view.findall("color") if x.get("key") == "backgroundColor"]
        self.assertEqual(len(bg), 1)
        self.assertEqual([bg[0].get(c) for c in ("red", "green", "blue")],
                         ["0", "0", "0"])
        image = next(storyboard.iter("imageView"))
        self.assertEqual(image.get("image"), "BreezzeLaunchMark")
        constraints = image.findall("constraints/constraint")
        self.assertEqual(len(constraints), 2)
        assets = self.mobile / "ios/Runner/Assets.xcassets/BreezzeLaunchMark.imageset"
        self.assertEqual(
            (assets / "BreezzeLaunchMark.png").read_bytes(),
            (self.mobile / "assets/icons/breezze_native_launch_mark.png").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()
