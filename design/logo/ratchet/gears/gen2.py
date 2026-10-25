# Ratchet round 2. Teeth are asymmetric (one radial face, one slope) so the mark reads one-way, not as a saw or a gear.
import math
f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")
def pt(r, deg, c=128): a = math.radians(deg - 90); return f"{f(c + r*math.cos(a))} {f(c + r*math.sin(a))}"
def circle(r, sweep=0): return f"M{128 - r} 128A{r} {r} 0 1 {sweep} {128 + r} 128A{r} {r} 0 1 {sweep} {128 - r} 128Z"
def saw(n, a, b, start=0):
    step = 360 / n; d = f"M{pt(a, start)}"
    for i in range(n): d += f"L{pt(b, start + i*step)}L{pt(a, start + (i + 1)*step)}"
    return d + "Z"

MARKS = {
  # Freehub: smooth ring outside, sawteeth on the inner edge. Quiet on the surface, clicking inside.
  "a-freehub": f'<path fill-rule="evenodd" d="{circle(116)}{saw(10, 60, 84)}"/>',
  # Ratchet wheel: twelve shallow one-way teeth and a wide hub, so it reads as a mechanism, not a blade.
  "b-wheel": f'<path fill-rule="evenodd" d="{saw(12, 100, 120)}{circle(52)}"/>',
  # Rack: three one-way teeth on a bar, each a notch of scroll.
  "c-rack": '<path d="M40 208A16 16 0 0 1 24 192V168L88 104V168L152 104V168L216 104V168H232V192A16 16 0 0 1 216 208Z"/>',
}
NOTES = {
  "a-freehub": "A freehub ring: smooth outside, one-way teeth inside. Calm surface, precise clicks underneath.",
  "b-wheel": "A ratchet wheel with twelve shallow one-way teeth around a wide hub.",
  "c-rack": "A ratchet rack: three one-way teeth, each one notch of scroll forward.",
}
for n, body in MARKS.items():
    open(f"{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ratchet</title>{body}</svg>\n')
    open(f"{n}-lockup.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 256"><title>Ratchet</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">Ratchet</text></svg>\n')
    open(f"{n}.txt", "w").write(NOTES[n])
