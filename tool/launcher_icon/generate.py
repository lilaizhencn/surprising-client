#!/usr/bin/env python3
"""Rasterize the unchanged AETERN Web mark into native launcher resources."""
import argparse
import copy
import io
import json
from decimal import Decimal
from pathlib import Path
import xml.etree.ElementTree as ET

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name("aetern-mark.svg")
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID = ROOT / "android/app/src/main/res"
SVG = "http://www.w3.org/2000/svg"
DENSITIES = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216),
             "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}
BACKGROUND = "#05060F"
ET.register_namespace("", SVG)


def raster(size, variant):
    mark = ET.fromstring(SOURCE.read_bytes())
    assert mark.attrib["viewBox"] == "0 0 32 32"
    assert mark.find(f"{{{SVG}}}rect").attrib["fill"] == BACKGROUND
    canvas = 108 if variant == "foreground" else 36 if variant == "round" else 32
    root = ET.Element(f"{{{SVG}}}svg", {"viewBox": f"0 0 {canvas} {canvas}",
                                       "fill": "none"})
    if variant != "foreground":
        ET.SubElement(root, f"{{{SVG}}}rect", {"width": str(canvas),
                      "height": str(canvas), "fill": BACKGROUND})
    # Adaptive foreground: the complete Web badge fits inside the guaranteed
    # 66dp circular safe zone, including its rounded gradient rim.
    transform = "translate(27 27) scale(1.6875)" if variant == "foreground" else (
        "translate(2 2)" if variant == "round" else "")
    group = ET.SubElement(root, f"{{{SVG}}}g", {"transform": transform})
    group.extend(copy.deepcopy(list(mark)))
    png = cairosvg.svg2png(bytestring=ET.tostring(root), output_width=size * 4,
                          output_height=size * 4)
    image = Image.open(io.BytesIO(png)).convert("RGBA").resize(
        (size, size), Image.Resampling.LANCZOS)
    # iOS must have no alpha channel; use the same full-bleed Web background.
    if variant != "foreground":
        image = image.convert("RGB")
    output = io.BytesIO()
    image.save(output, format="PNG", compress_level=9)
    return output.getvalue()


def outputs():
    records = json.loads((IOS / "Contents.json").read_text())["images"]
    sizes = {}
    for record in records:
        size = Decimal(record["size"].split("x")[0]) * Decimal(record["scale"][:-1])
        assert size == int(size)
        name = record["filename"]
        assert name not in sizes or sizes[name] == int(size)
        sizes[name] = int(size)
    for name, size in sizes.items():
        yield IOS / name, raster(size, "square")
    for density, (legacy, foreground) in DENSITIES.items():
        folder = ANDROID / f"mipmap-{density}"
        yield folder / "ic_launcher.png", raster(legacy, "square")
        yield folder / "ic_launcher_round.png", raster(legacy, "round")
        yield folder / "ic_launcher_foreground.png", raster(foreground, "foreground")
    adaptive = b'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/aetern_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''
    for name in ["ic_launcher.xml", "ic_launcher_round.xml"]:
        yield ANDROID / "mipmap-anydpi-v26" / name, adaptive
    yield ANDROID / "values/aetern_launcher_background.xml", (
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="aetern_launcher_background">{BACKGROUND}</color>\n'
        '</resources>\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated assets differ")
    args = parser.parse_args()
    count = 0
    for path, data in outputs():
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f"Regenerate launcher resource: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        count += 1
    print(f"{'Verified' if args.check else 'Generated'} {count} native launcher resources")


if __name__ == "__main__":
    main()
