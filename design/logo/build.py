"""Hyperpoint logo: the mark geometry. kitlib.py turns it into the full kit (run: python3 design/logo/build.py).

The mark is the Caps Lock glyph ⇪ (an outlined arrow over a bar) tipped over 22 degrees until it reads as a
pointer. The arrow outline is expanded from a round-joined stroke into one evenodd path: an outer contour rounded
at the convex corners and an inner contour mitred there, so the files have no strokes. The bar carries the accent
colour, like the key's lit LED.
"""
import math, os
from kitlib import Kit, Palette, Wordmark, f

INK, GREEN, GREEN_DEEP, PAPER = "#18181D", "#52E07A", "#138A48", "#FFFFFF"

def _unit(dx, dy):
    l = math.hypot(dx, dy); return dx / l, dy / l

def outline(pts, d):
    """Closed polygon stroked with width 2d and round joins, as two contours (outer, inner hole)."""
    area = sum(pts[i][0]*pts[(i+1) % len(pts)][1] - pts[(i+1) % len(pts)][0]*pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts = pts[::-1]  # make it clockwise on screen, so (dy, -dx) is the outward normal
    n = len(pts)
    normals = []
    for i in range(n):
        ux, uy = _unit(pts[(i+1) % n][0] - pts[i][0], pts[(i+1) % n][1] - pts[i][1])
        normals.append((uy, -ux))
    def contour(sign):
        cmds = []
        for i in range(n):
            v, n1, n2 = pts[i], normals[i-1], normals[i]
            ux1, uy1 = -n1[1], n1[0]; ux2, uy2 = -n2[1], n2[0]
            convex = ux1*uy2 - uy1*ux2 > 0
            a = (v[0] + sign*d*n1[0], v[1] + sign*d*n1[1])
            b = (v[0] + sign*d*n2[0], v[1] + sign*d*n2[1])
            if convex == (sign > 0):  # the round side of the join
                cmds.append(("L", a)); cmds.append(("A", b, 1 if sign > 0 else 0))
            else:                     # the sharp side: where the two offset edges meet
                k = sign*d / (1 + n1[0]*n2[0] + n1[1]*n2[1])
                cmds.append(("L", (v[0] + k*(n1[0] + n2[0]), v[1] + k*(n1[1] + n2[1]))))
        return cmds
    return contour(+1), contour(-1)

def rounded_rect(x, y, w, h, r):
    return [("L", (x + r, y)), ("L", (x + w - r, y)), ("A", (x + w, y + r), 1), ("L", (x + w, y + h - r)),
            ("A", (x + w - r, y + h), 1), ("L", (x + r, y + h)), ("A", (x, y + h - r), 1), ("L", (x, y + r)),
            ("A", (x + r, y), 1)]

def to_d(contours, r_of, mapper):
    d = ""
    for cmds, r in zip(contours, r_of):
        for j, c in enumerate(cmds):
            x, y = mapper(*c[1])
            if j == 0:
                d += f"M{f(x)} {f(y)}"
            elif c[0] == "L":
                d += f"L{f(x)} {f(y)}"
            else:
                d += f"A{f(r)} {f(r)} 0 0 {c[2]} {f(x)} {f(y)}"
        d += "Z"
    return d

def make_mark(arrow, d_full, d_small, bar, bar_small, angle=0.0, pivot=(128, 128), offset=(0, 0)):
    def mapper_for():
        a = math.radians(angle); c, s = math.cos(a), math.sin(a)
        def m(x, y):
            dx, dy = x - pivot[0], y - pivot[1]
            return pivot[0] + dx*c - dy*s + offset[0], pivot[1] + dx*s + dy*c + offset[1]
        return m
    def group(primary, accent, small=False):
        d = d_small if small else d_full
        bx, by, bw, bh, br = bar_small if small else bar
        outer, inner = outline(arrow, d)
        m = mapper_for()
        glyph = to_d([outer, inner], [d, d], m)
        bar_d = to_d([rounded_rect(bx, by, bw, bh, br)], [br], m)
        return (f'<path fill="{primary}" fill-rule="evenodd" d="{glyph}"/>'
                f'<path fill="{accent}" d="{bar_d}"/>')
    return group

# Caps pointer: symmetric ⇪ tipped 22 degrees. Small cut: heavier stroke, taller bar.
CAPS = make_mark([(128, 30), (214, 118), (164, 118), (164, 156), (92, 156), (92, 118), (42, 118)],
                 11, 15, (80, 182, 96, 26, 8), (78, 184, 100, 32, 10), angle=-22, pivot=(128, 136), offset=(4, 6))

PALETTE = Palette(INK, GREEN, GREEN_DEEP, PAPER, names={
    "ink": ("Ink", "glyph, type"), "accent": ("Caps Green", "the bar, the key's lit LED"),
    "accent_deep": ("Deep Green", "one-colour on white"), "paper": ("Paper", "")})
WORDMARK = Wordmark(kern={"Hy": -14, "yp": -6, "rp": -8})

# Menu-bar cut: the 18 pt template sits beside SF Symbols, whose strokes are ~1.5 pt. The small cut's 30-unit stroke is
# ~2.7 pt there and reads bold, so the menu bar gets an 18-unit stroke (~1.6 pt) and a thinner bar.
CAPS_MENUBAR = make_mark([(128, 30), (214, 118), (164, 118), (164, 156), (92, 156), (92, 118), (42, 118)],
                         9, 9, (82, 184, 92, 20, 7), (82, 184, 92, 20, 7), angle=-22, pivot=(128, 136), offset=(4, 6))

KIT = Kit(brand="Hyperpoint", slug="hyperpoint", group=CAPS, palette=PALETTE, wordmark=WORDMARK, mono_name="green",
          tagline="Caps Lock, tipped over into a pointer: the key that becomes hyper, and the cursor it drives.",
          icon_scale=2.5, icon_dy=12, menubar_box=(28, 28, 200, 200), menubar_group=CAPS_MENUBAR)

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    KIT.write(here)
    KIT.overview(here, "hyperpoint-logo-overview.png")
