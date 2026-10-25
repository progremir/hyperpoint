# Ratchet marks on a 256 grid. Ratchet teeth are asymmetric: one steep face, one slope; that one-way shape is the idea.
import math
f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")
def pt(r, deg, c=128): a = math.radians(deg - 90); return f"{f(c + r*math.cos(a))} {f(c + r*math.sin(a))}"

# A: ratchet wheel, 8 sawtooth teeth (radial steep face, sloped back), round hub knocked out.
def wheel(n=8, root=86, tip=116, hub=34, start=0):
    step = 360 / n
    d = f"M{pt(root, start)}"
    for i in range(n):
        a = start + i*step
        d += f"L{pt(tip, a)}L{pt(root, a + step)}"
    d += f"ZM{128 - hub} 128A{hub} {hub} 0 1 0 {128 + hub} 128A{hub} {hub} 0 1 0 {128 - hub} 128Z"
    return f'<path fill-rule="evenodd" d="{d}"/>'

# B: one tooth, one pawl: a wheel with a single sawtooth notch and the pawl dropped into it, the click itself.
def click():
    r = 92; c = (120, 140)
    # notch: steep radial face at -20deg, slope back to -60deg
    a1, a2 = math.radians(-20 - 90 + 90), math.radians(-70)
    p = lambda rr, deg: (c[0] + rr*math.cos(math.radians(deg)), c[1] + rr*math.sin(math.radians(deg)))
    s, e, inner = p(r, -70), p(r, -25), p(r - 36, -25)
    d = (f"M{f(e[0])} {f(e[1])}A{r} {r} 0 1 1 {f(s[0])} {f(s[1])}L{f(inner[0])} {f(inner[1])}Z")
    pawl = '<line x1="{}" y1="{}" x2="228" y2="22" stroke="#000" stroke-width="28" stroke-linecap="round"/>'
    tipx, tipy = p(r - 20, -32)
    return f'<path d="{d}"/>' + pawl.format(f(tipx + 6), f(tipy - 4))

# C: linear ratchet: a scroll-wheel capsule seen side-on, its right edge stepped into four one-way teeth.
def strip():
    d = "M108 24A40 40 0 0 0 68 64V192A40 40 0 0 0 108 232H124"
    y = 232
    for _ in range(4):
        d += f"L188 {y - 52}H{124 if y - 52 > 24 else 108}" if False else f"L180 {y - 52}H124"
        y -= 52
    d = d.rsplit("H124", 1)[0] + "H108Z"
    return f'<path d="{d}"/>'

MARKS = {"a-wheel": wheel(), "b-click": click(), "c-strip": strip()}
NOTES = {
  "a-wheel": "The ratchet wheel: eight one-way teeth around a hub. A gear that only turns forward.",
  "b-click": "One tooth, one pawl: the exact moment of the click.",
  "c-strip": "A scroll wheel side-on, its edge stepped into one-way teeth: each step a notch of scroll.",
}
for n, body in MARKS.items():
    open(f"{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ratchet</title>{body}</svg>\n')
    open(f"{n}-lockup.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 256"><title>Ratchet</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">Ratchet</text></svg>\n')
    open(f"{n}.txt", "w").write(NOTES[n])
