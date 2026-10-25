"""Shared logo-kit builder: given a mark drawn on a 256 grid, writes the SVG masters, lockups, app icon,
menu-bar template, PNGs, AppIcon.icns, web icons and a one-page overview.

A mark is a function `group(primary, accent, small=False) -> str` returning SVG elements on the 256 grid.
`primary` paints the main shape, `accent` the one detail that carries the brand colour; `small=True` asks for
the cut drawn for 16-40 px.
"""
import base64, math, os, re, subprocess
from dataclasses import dataclass, field
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

EXPORT = os.path.expanduser(
    "~/.claude/plugins/cache/logo-design-skill/logo-design/1.4.5/skills/logo-design/scripts/export_variants.py")

f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")

def circle(cx, cy, r, ccw=False):
    s = 0 if ccw else 1
    return f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx + r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx - r)} {f(cy)}Z"

class Wordmark:
    """Inter Display SemiBold (SIL OFL) outlined, tracked tight, with hand kerning."""
    def __init__(self, kern=None, track=-12, font="~/Library/Fonts/InterDisplay-SemiBold.otf"):
        self.font = TTFont(os.path.expanduser(font))
        self.gs, self.cmap, self.hmtx = self.font.getGlyphSet(), self.font.getBestCmap(), self.font["hmtx"]
        self.cap = self.font["OS/2"].sCapHeight
        self.kern, self.track = kern or {}, track

    def path(self, text, cap_px, x0=0, baseline=0):
        s = cap_px / self.cap; x = 0; parts = []
        for i, ch in enumerate(text):
            g = self.cmap[ord(ch)]
            pen = SVGPathPen(self.gs)
            self.gs[g].draw(TransformPen(pen, (s, 0, 0, -s, x0 + x*s, baseline)))
            parts.append(pen.getCommands())
            x += self.hmtx[g][0] + self.track + (self.kern.get(text[i:i+2], 0) if i + 1 < len(text) else 0)
        return "".join(parts), x * s

@dataclass
class Palette:
    ink: str
    accent: str
    accent_deep: str
    paper: str = "#FFFFFF"
    names: dict = field(default_factory=dict)  # display names for the overview

@dataclass
class Kit:
    brand: str            # wordmark text, e.g. "Hyperpoint"
    slug: str             # file prefix, e.g. "hyperpoint"
    group: object         # the mark function
    palette: Palette
    wordmark: Wordmark
    tagline: str = ""
    mono_name: str = "mono"
    icon_scale: float = 2.65      # mark scale inside the 824 px app-icon body
    icon_dy: float = 20           # optical drop of the mark inside the tile
    menubar_box: tuple = (36, 36, 184, 184)  # tight square viewBox around the menu-bar cut
    menubar_group: object = None  # lighter cut for the 18 pt menu bar; defaults to the small cut

    def svg(self, body, w=256, h=256):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}"><title>{self.brand}</title>'
                f'{body}</svg>\n')

    def symbols(self):
        p, g = self.palette, self.group
        return {
            "symbol-color": self.svg(g(p.ink, p.accent)),
            "symbol-black": self.svg(g("#000", "#000")),
            "symbol-white": self.svg(g(p.paper, p.paper)),
            f"symbol-{self.mono_name}": self.svg(g(p.accent_deep, p.accent_deep)),
            "symbol-color-on-dark": self.svg(g(p.paper, p.accent)),
            "symbol-small": self.svg(g("#000", "#000", small=True)),
        }

    def lockups(self):
        p, out = self.palette, {}
        for name, prim, acc, text in (("color", p.ink, p.accent, p.ink), ("black", "#000", "#000", "#000"),
                                      ("white", p.paper, p.paper, p.paper), ("color-on-dark", p.paper, p.accent, p.paper)):
            # Horizontal: mark 256 tall, cap height ~0.44 of it, caps centred on the mark's optical middle.
            wd, ww = self.wordmark.path(self.brand, 96, x0=252, baseline=176)
            out[f"horizontal-{name}"] = self.svg(
                f'{self.group(prim, acc)}<path fill="{text}" d="{wd}"/>', math.ceil(252 + ww + 16), 256)
            # Stacked: mark on top, wordmark centred below.
            _, ww2 = self.wordmark.path(self.brand, 50)
            W2 = max(256, math.ceil(ww2 + 32))
            wd2, _ = self.wordmark.path(self.brand, 50, x0=(W2 - ww2) / 2, baseline=286)
            out[f"stacked-{name}"] = self.svg(
                f'<g transform="translate({f((W2 - 256) / 2)} 0)">{self.group(prim, acc)}</g><path fill="{text}" d="{wd2}"/>',
                W2, 304)
            wd3, ww3 = self.wordmark.path(self.brand, 96, x0=8, baseline=112)
            out[f"wordmark-{name}"] = self.svg(f'<path fill="{text}" d="{wd3}"/>', math.ceil(ww3 + 16), 128)
        return out

    def app_icon(self):
        # macOS icon grid: 1024 canvas, 824 body with ~185 corner radius.
        p = self.palette
        return self.svg(f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{p.ink}"/>'
                        f'<g transform="translate(512 {512 + self.icon_dy}) scale({self.icon_scale}) translate(-128 -128)">'
                        f'{self.group(p.paper, p.accent)}</g>', 1024, 1024)

    def menubar(self):
        x, y, w, h = self.menubar_box
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x} {y} {w} {h}"><title>{self.brand}</title>'
                f'{(self.menubar_group or (lambda a, b: self.group(a, b, small=True)))("#000", "#000")}</svg>\n')

    def write(self, out):
        """SVG masters, PNGs, macOS icons and web icons into `out`."""
        sv = lambda n: os.path.join(out, "svg", f"{self.slug}-{n}.svg")
        for d in ("svg", "png", "macos/AppIcon.iconset", "web"):
            os.makedirs(os.path.join(out, d), exist_ok=True)
        p = self.palette
        swatches = {f"swatch-{k.replace('_', '-')}": self.svg(f'<rect width="16" height="16" rx="4" fill="{getattr(p, k)}"/>', 16, 16)
                    for k in ("ink", "accent", "accent_deep")}
        files = {**self.symbols(), **self.lockups(), "app-icon": self.app_icon(), "menubar-template": self.menubar(), **swatches}
        for n, s in files.items():
            open(sv(n), "w").write(s)
        run = lambda *a: subprocess.run(a, check=True, capture_output=True)
        for n in files:
            if n == "menubar-template" or n.startswith("swatch-"):
                continue
            w = "1200" if n.startswith(("horizontal", "wordmark")) else "1024"
            run("rsvg-convert", "-w", w, sv(n), "-o", os.path.join(out, "png", f"{self.slug}-{n}-{w}.png"))
        iconset = os.path.join(out, "macos/AppIcon.iconset")
        for s in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                px = str(s * scale)
                run("rsvg-convert", "-w", px, "-h", px, sv("app-icon"), "-o", f"{iconset}/icon_{s}x{s}{suffix}.png")
        run("iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "macos/AppIcon.icns"))
        for px, suffix in (("18", ""), ("36", "@2x")):
            run("rsvg-convert", "-w", px, "-h", px, sv("menubar-template"), "-o", os.path.join(out, f"macos/MenuBarTemplate{suffix}.png"))
        open(os.path.join(out, f"macos/{self.slug}-menubar-template.svg"), "w").write(files["menubar-template"])
        run("python3", EXPORT, sv("symbol-color"), "--name", self.slug, "--title", self.brand, "--only", "square", "favicon",
            "--web-icons", "--icon-bg", self.palette.ink, "--favicon-source", sv("symbol-small"), "--out-dir", os.path.join(out, "web"))
        return files

    def overview(self, out, png_name):
        """One-page overview of every main asset, the palette and the small sizes."""
        sv = lambda n: os.path.join(out, "svg", f"{self.slug}-{n}.svg")
        def png(svg, w, h=None):
            a = ["rsvg-convert", "-w", str(w)] + (["-h", str(h)] if h else []) + [svg]
            return "data:image/png;base64," + base64.b64encode(subprocess.run(a, capture_output=True).stdout).decode()
        T = lambda x, y, s, txt, c="#55555c", w=500: f'<text x="{x}" y="{y}" font-family="Inter" font-size="{s}" font-weight="{w}" fill="{c}">{txt}</text>'
        img = lambda href, x, y, w, h: f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{href}"/>'
        card = lambda x, y, w, h, bg="#fff": f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="20" fill="{bg}"/>'
        def lock(n, x, y, w):
            vw, vh = map(float, re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', open(sv(n)).read()).groups())
            return img(png(sv(n), int(w*2)), x, y, w, w*vh/vw)
        p, ink = self.palette, self.palette.ink
        W, H = 1600, 1180
        o = [f'<rect width="{W}" height="{H}" fill="#F4F3EF"/>', T(60, 82, 40, f"{self.brand} — logo kit", ink, 700), T(60, 118, 18, self.tagline)]
        row = [("symbol-color", "#fff", "Symbol · colour"), ("symbol-color-on-dark", ink, "Symbol · on ink"),
               ("app-icon", "#fff", "macOS app icon"), ("symbol-black", "#fff", "One colour · black"),
               (f"symbol-{self.mono_name}", "#fff", f"One colour · {p.names.get('accent_deep', ('accent',))[0].lower()}")]
        for i, (n, bg, label) in enumerate(row):
            x = 60 + i*300
            o += [card(x, 150, 280, 300, bg), img(png(sv(n), 400), x + 40, 170, 200, 200),
                  T(x + 20, 430, 15, label, "#c9c9cf" if bg != "#fff" else "#55555c")]
        o += [card(60, 470, 880, 200), lock("horizontal-color", 100, 492, 400), T(80, 652, 15, "Horizontal lockup · primary"),
              card(960, 470, 580, 200, ink), lock("horizontal-color-on-dark", 1000, 492, 400), T(980, 652, 15, "Horizontal · reversed", "#c9c9cf"),
              card(60, 690, 380, 460), lock("stacked-color", 110, 720, 280), T(80, 1130, 15, "Stacked lockup")]
        o += [card(460, 690, 520, 460), T(490, 730, 18, "Colour", ink, 700)]
        for i, key in enumerate(("ink", "accent", "accent_deep", "paper")):
            c, y = getattr(p, key), 760 + i*92
            name, use = p.names.get(key, (key, ""))
            o += [f'<rect x="490" y="{y}" width="72" height="72" rx="14" fill="{c}" stroke="#ddd"/>',
                  T(580, y + 32, 18, name, ink, 600), T(580, y + 56, 14, f"{c} · {use}" if use else c)]
        o += [card(1000, 690, 540, 460), T(1030, 730, 18, "Small sizes", ink, 700),
              T(1030, 760, 14, "Below 40 px use the small cut (heavier strokes, wider gaps).")]
        for i, s in enumerate((16, 18, 24, 32, 48)):
            x = 1030 + i*90
            o += [img(png(sv("symbol-small"), s, s), x, 800, s, s), T(x, 870, 13, f"{s} px")]
        o += [f'<rect x="1030" y="900" width="480" height="30" fill="#ECECEC"/>', img(png(sv("menubar-template"), 36, 36), 1044, 906, 18, 18),
              T(1072, 920, 13, "menu bar, light"), f'<rect x="1030" y="940" width="480" height="30" fill="#2A2A2E"/>',
              img(png(sv("symbol-white"), 36, 36), 1044, 946, 18, 18), T(1072, 960, 13, "menu bar, dark (template tinted white)", "#c9c9cf"),
              img(png(sv("symbol-small"), 128, 128), 1030, 990, 128, 128), img(png(sv("app-icon"), 128, 128), 1180, 990, 128, 128),
              T(1330, 1060, 13, "small cut · app icon, 128 px")]
        tmp = os.path.join(out, ".overview.svg")
        open(tmp, "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">{"".join(o)}</svg>')
        subprocess.run(["rsvg-convert", tmp, "-o", os.path.join(out, png_name)], check=True)
        os.remove(tmp)
