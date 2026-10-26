#!/usr/bin/env python3
"""Draws site/og.png, the 1200 x 630 social preview, from the logo kit and Geist.

The text is converted to outlines so rsvg-convert needs no installed fonts. Needs fonttools
(pip3 install --user fonttools), rsvg-convert (brew install librsvg) and the Geist variable font:

    python3 site/og.py ~/Downloads/Geist[wght].ttf
"""

import pathlib
import re
import subprocess
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = pathlib.Path(__file__).resolve().parent
LOGO = HERE.parent / "design/logo/svg"
W, H = 1200, 630


class Text:
    def __init__(self, path, weight):
        self.font = TTFont(path)
        self.glyphs = self.font.getGlyphSet(location={"wght": weight})
        self.cmap = self.font.getBestCmap()
        self.em = self.font["head"].unitsPerEm

    def path(self, text, x, y, size, tracking=0.0):
        """SVG path data for `text` with its baseline starting at (x, y)."""
        scale = size / self.em
        pen = SVGPathPen(self.glyphs)
        cursor = 0.0
        for char in text:
            name = self.cmap[ord(char)]
            glyph = self.glyphs[name]
            glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, x + cursor, y)))
            cursor += glyph.width * scale + tracking * size
        return pen.getCommands(), cursor


def inner(svg):
    """The drawing inside an SVG file, without its <svg> and <title>."""
    body = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S).group(1)
    return re.sub(r"<title>.*?</title>", "", body)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    bold = Text(sys.argv[1], 600)
    regular = Text(sys.argv[1], 400)

    heading = ""
    widest = 0.0
    for i, line in enumerate(["Your mouse setup,", "still there after", "every reconnect"]):
        d, width = bold.path(line, 80, 268 + i * 80, 72, tracking=-0.03)
        heading += d
        widest = max(widest, width)
    sub, _ = regular.path("Mouse buttons, smooth scrolling and a hyper key for macOS", 80, 548, 28)

    lockup = inner((LOGO / "hyperpoint-horizontal-color-on-dark.svg").read_text())
    icon = inner((LOGO / "hyperpoint-app-icon.svg").read_text())

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs><linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="80" x2="{80 + widest:.0f}" y1="0" y2="0">
<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#9B9B9B"/></linearGradient></defs>
<rect width="{W}" height="{H}" fill="#181818"/>
<g transform="translate(80 64) scale(0.25)">{lockup}</g>
<path d="{heading}" fill="url(#fade)"/>
<path d="{sub}" fill="#9B9B9B"/>
<g transform="translate(828 176) scale(0.3125)">{icon}</g>
</svg>"""
    out = HERE / "og.png"
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(out)], input=svg.encode(), check=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
