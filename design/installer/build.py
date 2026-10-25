"""Draws the DMG window background: background.svg, rendered at 1x and 2x into one HiDPI background.tiff.

The layout here must match the icon positions in scripts/dmg-settings.py. Everything sits in the top 344 pt so it
stays visible when Finder's path and status bars are on. Needs rsvg-convert and Inter.
Run with `python3 design/installer/build.py`.
"""
import os, re, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "logo", "svg", "hyperpoint-horizontal-color.svg")

W, H = 640, 400
APP_X, APPS_X, ICON_Y = 170, 470, 160
INK, ACCENT, ACCENT_DEEP = "#18181D", "#52E07A", "#138A48"

def lockup(height, cx, top):
    svg = open(LOGO).read()
    vw, vh = map(float, re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups())
    body = re.sub(r"^.*?<svg[^>]*>|<title>.*?</title>|</svg>\s*$", "", svg, flags=re.S)
    s = height / vh
    return f'<g transform="translate({cx - vw * s / 2:.2f} {top}) scale({s:.4f})">{body}</g>'

def arrow():
    x0, x1, y = APP_X + 104, APPS_X - 100, ICON_Y
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="2.6" fill="{INK}" opacity="{0.16 + 0.5 * (x - x0) / (x1 - x0):.2f}"/>'
                   for x in range(x0, x1 - 30, 14))
    head = f'<path d="M{x1 - 22} {y - 13}L{x1 - 4} {y}L{x1 - 22} {y + 13}" fill="none" stroke="{INK}" ' \
           f'stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
    return dots + head

def well(cx):
    x, y, w, h = cx - 84, ICON_Y - 84, 168, 186
    return (f'<rect x="{x}" y="{y + 3}" width="{w}" height="{h}" rx="28" fill="{INK}" opacity="0.05"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="28" fill="#FFFFFF" opacity="0.78" '
            f'stroke="{INK}" stroke-opacity="0.06"/>')

def text(x, y, s, size, weight, fill, opacity=1):
    return (f'<text x="{x}" y="{y}" text-anchor="middle" font-family="Inter" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" opacity="{opacity}" letter-spacing="-0.1">{s}</text>')

svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FCFCFA"/><stop offset="1" stop-color="#EFEFEA"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.47" r="0.55">
    <stop offset="0" stop-color="{ACCENT}" stop-opacity="0.10"/><stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="{W}" height="{H}" fill="url(#paper)"/>
<rect width="{W}" height="{H}" fill="url(#glow)"/>
{lockup(36, W / 2, 22)}
{well(APP_X)}{well(APPS_X)}
{arrow()}
{text(W / 2, 290, "Drag Hyperpoint into Applications", 16, 600, INK)}
{text(W / 2, 310, "Then open it from Applications and allow Accessibility and Input Monitoring.", 12, 400, INK, 0.62)}
{text(W / 2, 334, "Hyperpoint lives in the menu bar, next to the clock.", 11, 400, ACCENT_DEEP)}
</svg>
"""

out_svg = os.path.join(HERE, "background.svg")
open(out_svg, "w").write(svg)
with tempfile.TemporaryDirectory() as tmp:
    pngs = []
    for scale in (1, 2):
        png = os.path.join(tmp, f"bg@{scale}x.png")
        subprocess.run(["rsvg-convert", "-w", str(W * scale), "-h", str(H * scale), "-o", png, out_svg], check=True)
        subprocess.run(["sips", "-s", "dpiWidth", str(72 * scale), "-s", "dpiHeight", str(72 * scale), png],
                       check=True, capture_output=True)
        pngs.append(png)
    subprocess.run(["tiffutil", "-cathidpicheck", *pngs, "-out", os.path.join(HERE, "background.tiff")],
                   check=True, capture_output=True)
print("wrote background.svg and background.tiff")
