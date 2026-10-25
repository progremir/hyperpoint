# One-page kit overview: every main asset, the palette and the small sizes, rendered from the masters.
import base64, subprocess
def png(svg, w, h=None):
    args = ["rsvg-convert", "-w", str(w)] + (["-h", str(h)] if h else []) + [svg]
    return "data:image/png;base64," + base64.b64encode(subprocess.run(args, capture_output=True).stdout).decode()
T = lambda x, y, s, txt, c="#55555c", w=500: f'<text x="{x}" y="{y}" font-family="Inter" font-size="{s}" font-weight="{w}" fill="{c}">{txt}</text>'
def img(href, x, y, w, h): return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{href}"/>'
W, H = 1600, 1180
p = [f'<rect width="{W}" height="{H}" fill="#F4F3EF"/>', T(60, 82, 40, "Ratchet — logo kit", "#18181D", 700),
     T(60, 118, 18, "Ratchet → rat → mouse. A menu-bar app for your mouse, named after one.")]
card = lambda x, y, w, h, bg="#fff": f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="20" fill="{bg}"/>'
# Row 1: primary symbol, on dark, app icon, black, pink
row = [("svg/ratchet-symbol-color.svg", "#fff", "Symbol · colour"), ("svg/ratchet-symbol-color-on-dark.svg", "#18181D", "Symbol · on ink"),
       ("svg/ratchet-app-icon.svg", "#fff", "macOS app icon"), ("svg/ratchet-symbol-black.svg", "#fff", "One colour · black"),
       ("svg/ratchet-symbol-pink.svg", "#fff", "One colour · deep pink")]
for i, (f, bg, label) in enumerate(row):
    x = 60 + i*300
    p += [card(x, 150, 280, 300, bg), img(png(f, 400), x + 40, 170, 200, 200),
          T(x + 20, 430, 15, label, "#c9c9cf" if bg != "#fff" else "#55555c")]
# Row 2: horizontal and stacked lockups, light and dark
p += [card(60, 470, 880, 200), img(png("svg/ratchet-horizontal-color.svg", 1200), 100, 500, 560, 0) ]
import re
def lock(f, x, y, w, bg):
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', open(f).read()); vw, vh = map(float, vb.groups())
    return img(png(f, int(w*2)), x, y, w, w*vh/vw)
p = p[:-1] + [lock("svg/ratchet-horizontal-color.svg", 100, 492, 400, "#fff"), T(80, 652, 15, "Horizontal lockup · primary"),
              card(960, 470, 580, 200, "#18181D"), lock("svg/ratchet-horizontal-color-on-dark.svg", 1000, 492, 400, "#18181D"),
              T(980, 652, 15, "Horizontal · reversed", "#c9c9cf"),
              card(60, 690, 380, 460), lock("svg/ratchet-stacked-color.svg", 110, 720, 280, "#fff"), T(80, 1130, 15, "Stacked lockup")]
# Palette
pal = [("#18181D", "Ink", "#18181D · face, type"), ("#FF6F96", "Rat Pink", "#FF6F96 · ears, accent on ink"),
       ("#D93A6A", "Deep Pink", "#D93A6A · one-colour on white"), ("#FFFFFF", "Paper", "#FFFFFF")]
p += [card(460, 690, 520, 460), T(490, 730, 18, "Colour", "#18181D", 700)]
for i, (c, n, d) in enumerate(pal):
    y = 760 + i*92
    p += [f'<rect x="490" y="{y}" width="72" height="72" rx="14" fill="{c}" stroke="#ddd"/>', T(580, y + 32, 18, n, "#18181D", 600), T(580, y + 56, 14, d)]
# Small sizes at true size and zoomed
p += [card(1000, 690, 540, 460), T(1030, 730, 18, "Small sizes", "#18181D", 700),
      T(1030, 760, 14, "Below 40 px use the small cut (bigger eyes, wider ear gaps).")]
for i, s in enumerate((16, 18, 24, 32, 48)):
    x = 1030 + i*90
    p += [img(png("svg/ratchet-symbol-small.svg", s, s), x, 800, s, s), T(x, 870, 13, f"{s} px")]
p += [f'<rect x="1030" y="900" width="480" height="30" fill="#ECECEC"/>', img(png("macos/ratchet-menubar-template.svg", 36, 36), 1044, 906, 18, 18),
      T(1072, 920, 13, "menu bar, light"), f'<rect x="1030" y="940" width="480" height="30" fill="#2A2A2E"/>',
      img(png("svg/ratchet-symbol-white.svg", 36, 36).replace("", ""), 1044, 946, 18, 18), T(1072, 960, 13, "menu bar, dark (template tinted white)", "#c9c9cf"),
      img(png("web/favicon-32.png" if False else "svg/ratchet-symbol-small.svg", 128, 128), 1030, 990, 128, 128),
      img(png("svg/ratchet-app-icon.svg", 128, 128), 1180, 990, 128, 128), T(1330, 1060, 13, "small cut · app icon, 128 px")]
open("overview.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">{"".join(p)}</svg>')
subprocess.run(["rsvg-convert", "overview.svg", "-o", "ratchet-kit-overview.png"])
