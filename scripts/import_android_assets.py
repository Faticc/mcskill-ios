"""Copies the Android launcher's look into the iOS app: icons, Inter fonts, app icon.

Run from ios/ on the development machine (the Android project is ../app); the output is
committed, CI does not need the Android sources.

    python scripts/import_android_assets.py
"""
import json
import pathlib
import shutil
import xml.etree.ElementTree as ET

from fontTools.ttLib import TTFont
from PIL import Image

IOS = pathlib.Path(__file__).resolve().parent.parent
ANDROID = IOS.parent / "app" / "src" / "main"
ASSETS = IOS / "App" / "Assets.xcassets"
A = "{http://schemas.android.com/apk/res/android}"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def svg_color(value):
    # #AARRGGBB with alpha 0 means "none"; any real colour becomes black, the icons are templates
    if value is None:
        return "none"
    value = value.lstrip("#")
    if len(value) == 8 and value[:2] == "00":
        return "none"
    return "#000000"


def icons():
    folder = ASSETS / "Icons"
    if folder.exists():
        shutil.rmtree(folder)
    write_json(folder / "Contents.json", {"info": {"author": "xcode", "version": 1},
                                          "properties": {"provides-namespace": False}})
    for xml in sorted((ANDROID / "res" / "drawable").glob("ic_*.xml")):
        root = ET.parse(xml).getroot()
        w, h = root.get(A + "viewportWidth"), root.get(A + "viewportHeight")
        paths = []
        for p in root.iter("path"):
            attrs = {
                "d": p.get(A + "pathData"),
                "fill": svg_color(p.get(A + "fillColor")),
                "stroke": svg_color(p.get(A + "strokeColor")),
            }
            if attrs["stroke"] != "none":
                attrs["stroke-width"] = p.get(A + "strokeWidth", "1")
                attrs["stroke-linecap"] = p.get(A + "strokeLineCap", "butt")
                attrs["stroke-linejoin"] = p.get(A + "strokeLineJoin", "miter")
            paths.append("<path " + " ".join(f'{k}="{v}"' for k, v in attrs.items()) + "/>")
        name = xml.stem
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
               + "".join(paths) + "</svg>\n")
        imageset = folder / f"{name}.imageset"
        imageset.mkdir(parents=True)
        (imageset / f"{name}.svg").write_text(svg, encoding="utf-8")
        write_json(imageset / "Contents.json", {
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
        })
        print("icon", name)


def fonts():
    target = IOS / "App" / "Fonts"
    target.mkdir(parents=True, exist_ok=True)
    for ttf in sorted((ANDROID / "assets" / "fonts").glob("*.ttf")):
        shutil.copy2(ttf, target / ttf.name)
        name = TTFont(ttf)["name"].getDebugName(6)
        print("font", ttf.name, "->", name)


def app_icon():
    src = Image.open(ANDROID / "res" / "mipmap-xxxhdpi" / "ic_launcher.png").convert("RGBA")
    # The Android icon has its own rounded corners; iOS masks the square itself, so cut them off
    inset = round(src.width * 0.06)
    src = src.crop((inset, inset, src.width - inset, src.height - inset))
    icon = Image.new("RGB", src.size, src.getpixel((src.width // 2, 2))[:3])
    icon.paste(src, mask=src.split()[3])
    icon = icon.resize((1024, 1024), Image.LANCZOS)
    iconset = ASSETS / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    icon.save(iconset / "AppIcon.png")
    write_json(iconset / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })
    print("app icon", icon.size)


if __name__ == "__main__":
    write_json(ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    icons()
    fonts()
    app_icon()
