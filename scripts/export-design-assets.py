#!/usr/bin/env python3
"""Export icons and app-icon concepts from the Figcraft design board to standalone SVGs.

The board (design/figcraft/MacSweeper.figcraft.html) is the source of truth:
- <symbol id="i-*"> elements become design/figcraft/icons/<name>.svg
  and MacSweeper/Assets.xcassets/Icons/ms-<name>.imageset (vector template images)
- ICONS entries in the board script become design/figcraft/app-icons/<n>-<name>.svg

Icons are written with a black stroke so Xcode treats them as template images.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOARD = ROOT / "design/figcraft/MacSweeper.figcraft.html"
ICON_DIR = ROOT / "design/figcraft/icons"
APP_ICON_DIR = ROOT / "design/figcraft/app-icons"
ASSET_ICON_DIR = ROOT / "MacSweeper/Assets.xcassets/Icons"

# Stroke attributes live on a <g> so Xcode's SVG importer applies them to every shape.
ICON_TEMPLATE = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<g fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">'
    "{body}</g></svg>\n"
)

IMAGESET_CONTENTS = """{{
  "images" : [ {{ "filename" : "{name}.svg", "idiom" : "universal" }} ],
  "info" : {{ "author" : "xcode", "version" : 1 }},
  "properties" : {{
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }}
}}
"""

FOLDER_CONTENTS = """{
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


def export_icons(html: str) -> int:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    symbols = re.findall(r'<symbol id="i-([\w-]+)" viewBox="0 0 24 24">(.*?)</symbol>', html, re.S)
    ASSET_ICON_DIR.mkdir(parents=True, exist_ok=True)
    (ASSET_ICON_DIR / "Contents.json").write_text(FOLDER_CONTENTS)
    for name, body in symbols:
        body = body.replace('fill="currentColor"', 'fill="#000"')
        svg = ICON_TEMPLATE.format(body=body)
        (ICON_DIR / f"{name}.svg").write_text(svg)
        # Asset name "ms-<name>" is what `MSIcon` loads in SwiftUI.
        imageset = ASSET_ICON_DIR / f"ms-{name}.imageset"
        imageset.mkdir(exist_ok=True)
        (imageset / f"{name}.svg").write_text(svg)
        (imageset / "Contents.json").write_text(IMAGESET_CONTENTS.format(name=name))
    return len(symbols)


def export_app_icons(html: str) -> int:
    APP_ICON_DIR.mkdir(parents=True, exist_ok=True)
    squircle = re.search(r"const SQ = `([^`]+)`", html).group(1)
    entries = re.findall(r'\["(\w+)", "[^"]*",\s*`(.*?)`\]', html, re.S)
    for i, (name, body) in enumerate(entries, start=1):
        body = body.replace("${SQ}", squircle)
        svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f"{body.strip()}</svg>\n"
        )
        (APP_ICON_DIR / f"{i}-{name.lower()}.svg").write_text(svg)
    return len(entries)


def main() -> int:
    html = BOARD.read_text()
    icons = export_icons(html)
    app_icons = export_app_icons(html)
    print(f"exported {icons} icons to {ICON_DIR.relative_to(ROOT)}")
    print(f"exported {app_icons} app icons to {APP_ICON_DIR.relative_to(ROOT)}")
    return 0 if icons and app_icons else 1


if __name__ == "__main__":
    sys.exit(main())
