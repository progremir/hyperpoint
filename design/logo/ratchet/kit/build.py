"""Ratchet logo kit: final mark geometry, outlined wordmark, lockups, app icon and menu-bar icon.

The mark is one evenodd path on a 256 grid: a wedge snout with a round tip, bitten at the top corners by the
ear gaps, two eye holes, and two ear discs. No strokes, masks or white shapes painted on top.
"""
import math, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

INK, PINK, PINK_DEEP, PAPER = "#18181D", "#FF6F96", "#D93A6A", "#FFFFFF"
f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")

def tangent(p, c, r, side):
    """Outer tangent point from external point p to circle (c, r): leftmost for side=-1, rightmost for +1."""
    dx, dy = c[0] - p[0], c[1] - p[1]
    d = math.hypot(dx, dy); a = math.atan2(dy, dx); b = math.asin(r / d); L = math.sqrt(d*d - r*r)
    pts = [(p[0] + L*math.cos(a + s*b), p[1] + L*math.sin(a + s*b)) for s in (-1, 1)]
    return min(pts) if side < 0 else max(pts)

def exit_point(p, q, c, r):
    """Where segment p→q leaves circle (c, r): the larger-t intersection."""
    dx, dy = q[0] - p[0], q[1] - p[1]; fx, fy = p[0] - c[0], p[1] - c[1]
    A = dx*dx + dy*dy; B = 2*(fx*dx + fy*dy); C = fx*fx + fy*fy - r*r
    t = (-B + math.sqrt(B*B - 4*A*C)) / (2*A)
    return (p[0] + t*dx, p[1] + t*dy)

def circle(cx, cy, r, ccw=False):
    s = 0 if ccw else 1
    return f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx + r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx - r)} {f(cy)}Z"

def mark_paths(small=False):
    """Returns (face_d, ears_d). small=True is the cut for 16-36 px: bigger eyes, wider ear gap."""
    top, tip_c, tip_r = 86, (128, 206), 26
    ear_l, ear_r, ear = (74, 82), (182, 82), 30
    gap = ear + (14 if small else 10)
    eye_r, eye_y, eye_dx = (15, 140, 22) if small else (11, 138, 20)
    pl, pr = (56, top), (200, top)
    tl, tr = tangent(pl, tip_c, tip_r, -1), tangent(pr, tip_c, tip_r, +1)
    el, er = exit_point(pl, tl, ear_l, gap), exit_point(pr, tr, ear_r, gap)
    hx = math.sqrt(gap*gap - (top - ear_l[1])**2)
    face = (f"M{f(ear_l[0] + hx)} {top}H{f(ear_r[0] - hx)}"
            f"A{gap} {gap} 0 0 0 {f(er[0])} {f(er[1])}L{f(tr[0])} {f(tr[1])}"
            f"A{tip_r} {tip_r} 0 0 1 {f(tl[0])} {f(tl[1])}L{f(el[0])} {f(el[1])}"
            f"A{gap} {gap} 0 0 0 {f(ear_l[0] + hx)} {top}Z"
            + circle(128 - eye_dx, eye_y, eye_r, ccw=True) + circle(128 + eye_dx, eye_y, eye_r, ccw=True))
    ears = circle(*ear_l, ear) + circle(*ear_r, ear)
    return face, ears

# Optical placement: bbox runs 52..232 vertically; centre it slightly above the canvas centre.
SHIFT = "translate(0 -16)"

def mark(face_fill, ear_fill, small=False, title="Ratchet"):
    face, ears = mark_paths(small)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>{title}</title>'
            f'<g transform="{SHIFT}"><path fill="{face_fill}" fill-rule="evenodd" d="{face}"/>'
            f'<path fill="{ear_fill}" d="{ears}"/></g></svg>\n')

def mark_group(face_fill, ear_fill, small=False):
    face, ears = mark_paths(small)
    return (f'<g transform="{SHIFT}"><path fill="{face_fill}" fill-rule="evenodd" d="{face}"/>'
            f'<path fill="{ear_fill}" d="{ears}"/></g>')

# Wordmark: Inter Display SemiBold (SIL OFL), outlined, tracked tight with hand kerning.
FONT = TTFont(os.path.expanduser("~/Library/Fonts/InterDisplay-SemiBold.otf"))
GS, CMAP, HMTX = FONT.getGlyphSet(), FONT.getBestCmap(), FONT["hmtx"]
UPM, CAP = FONT["head"].unitsPerEm, FONT["OS/2"].sCapHeight
KERN = {"Ra": -30, "at": -20, "tc": -10, "ch": 0, "he": 0, "et": -10}
TRACK = -12

def wordmark(text="Ratchet", cap_px=100, x0=0, baseline=0):
    s = cap_px / CAP; x = 0; parts = []
    for i, ch in enumerate(text):
        g = CMAP[ord(ch)]
        pen = SVGPathPen(GS)
        GS[g].draw(TransformPen(pen, (s, 0, 0, -s, x0 + x*s, baseline)))
        parts.append(pen.getCommands())
        x += HMTX[g][0] + TRACK + (KERN.get(text[i:i+2], 0) if i + 1 < len(text) else 0)
    return "".join(parts), x * s

def lockups():
    out = {}
    # Horizontal: mark 256 tall, cap height ~ 0.44 of mark, caps centred on the face's optical middle.
    wd, ww = wordmark(cap_px=96, x0=0, baseline=0)
    for name, face, ear, text in (("color", INK, PINK, INK), ("black", "#000", "#000", "#000"),
                                  ("white", PAPER, PAPER, PAPER), ("color-on-dark", PAPER, PINK, PAPER)):
        wd, ww = wordmark(cap_px=96, x0=252, baseline=176)
        W = math.ceil(252 + ww + 16)
        out[f"ratchet-horizontal-{name}.svg"] = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} 256"><title>Ratchet</title>'
            f'{mark_group(face, ear)}<path fill="{text}" d="{wd}"/></svg>\n')
        # Stacked: mark on top, wordmark centred below.
        wd2, ww2 = wordmark(cap_px=50)
        W2 = max(256, math.ceil(ww2 + 32)); mx = (W2 - 256) / 2
        wd2, _ = wordmark(cap_px=50, x0=(W2 - ww2) / 2, baseline=286)
        out[f"ratchet-stacked-{name}.svg"] = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W2} 304"><title>Ratchet</title>'
            f'<g transform="translate({f(mx)} 0)">{mark_group(face, ear)}</g><path fill="{text}" d="{wd2}"/></svg>\n')
        wd3, ww3 = wordmark(cap_px=96, x0=8, baseline=112)
        out[f"ratchet-wordmark-{name}.svg"] = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {math.ceil(ww3 + 16)} 128"><title>Ratchet</title>'
            f'<path fill="{text}" d="{wd3}"/></svg>\n')
    return out

def app_icon():
    # macOS icon grid: 1024 canvas, 824 body with ~185 corner radius, mark at ~60% of the body.
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>Ratchet</title>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{INK}"/>'
            f'<g transform="translate(512 532) scale(2.65) translate(-128 -128)">{mark_group(PAPER, PINK)}</g></svg>\n')

def menubar():
    # Template image: pure black small cut, tight square, for NSImage.isTemplate.
    face, ears = mark_paths(small=True)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="36 36 184 184"><title>Ratchet</title>'
            f'<g transform="{SHIFT}"><path fill-rule="evenodd" d="{face}"/><path d="{ears}"/></g></svg>\n')

if __name__ == "__main__":
    os.makedirs("svg", exist_ok=True)
    files = {
        "ratchet-symbol-color.svg": mark(INK, PINK),
        "ratchet-symbol-black.svg": mark("#000", "#000"),
        "ratchet-symbol-white.svg": mark(PAPER, PAPER),
        "ratchet-symbol-pink.svg": mark(PINK_DEEP, PINK_DEEP),
        "ratchet-symbol-color-on-dark.svg": mark(PAPER, PINK),
        "ratchet-symbol-small.svg": mark("#000", "#000", small=True),
        "ratchet-app-icon.svg": app_icon(),
        "ratchet-menubar-template.svg": menubar(),
        **lockups(),
    }
    for n, s in files.items():
        open(f"svg/{n}", "w").write(s)
    print("\n".join(sorted(files)))
