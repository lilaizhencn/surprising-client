import json
import unittest
import xml.etree.ElementTree as ET
from decimal import Decimal
from pathlib import Path

from PIL import Image

from generate import ANDROID, IOS, DENSITIES, SOURCE


class LauncherIconsTest(unittest.TestCase):
    def test_ios_sizes_are_opaque_rgb_with_full_bleed_brand_background(self):
        for entry in json.loads((IOS / "Contents.json").read_text())["images"]:
            size = int(Decimal(entry["size"].split("x")[0]) * Decimal(entry["scale"][:-1]))
            with self.subTest(file=entry["filename"]), Image.open(IOS / entry["filename"]) as image:
                image.load()
                self.assertEqual(image.size, (size, size))
                self.assertEqual(image.mode, "RGB")
                self.assertEqual(image.getpixel((0, 0)), (5, 6, 15))

    def test_android_sizes_alpha_and_circle_safe_zone(self):
        for density, (legacy, foreground) in DENSITIES.items():
            folder = ANDROID / f"mipmap-{density}"
            for name in ["ic_launcher.png", "ic_launcher_round.png"]:
                with Image.open(folder / name) as image:
                    image.load()
                    self.assertEqual(image.size, (legacy, legacy))
                    self.assertEqual(image.mode, "RGB")
            with Image.open(folder / "ic_launcher_foreground.png") as image:
                image.load()
                self.assertEqual(image.size, (foreground, foreground))
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.getpixel((0, 0))[3], 0)
                scale = foreground / 108
                for index, alpha in enumerate(image.getchannel("A").tobytes()):
                    if alpha:
                        x = (index % foreground + .5) / scale - 54
                        y = (index // foreground + .5) / scale - 54
                        self.assertLessEqual(x*x + y*y, 33*33, density)

    def test_adaptive_layers_reference_existing_resources(self):
        ns = "{http://schemas.android.com/apk/res/android}"
        for name in ["ic_launcher.xml", "ic_launcher_round.xml"]:
            root = ET.parse(ANDROID / "mipmap-anydpi-v26" / name).getroot()
            self.assertEqual(root.tag, "adaptive-icon")
            self.assertEqual(root.find("background").get(ns+"drawable"), "@color/aetern_launcher_background")
            self.assertEqual(root.find("foreground").get(ns+"drawable"), "@mipmap/ic_launcher_foreground")
        color = ET.parse(ANDROID / "values/aetern_launcher_background.xml").getroot().find("color")
        self.assertEqual(color.text, "#05060F")

    def test_web_gradient_is_not_reinvented(self):
        ns = {"s": "http://www.w3.org/2000/svg"}
        root = ET.parse(SOURCE).getroot()
        gradient = root.find("s:defs/s:linearGradient[@id='aetern-aurora']", ns)
        self.assertEqual([(e.get("offset"), e.get("stop-color")) for e in gradient],
                         [("0%", "#00E5FF"), ("52%", "#7C4DFF"), ("100%", "#FF2BD6")])
        self.assertEqual(root.find("s:path", ns).get("fill"), "#F4F6FF")


if __name__ == "__main__":
    unittest.main()
