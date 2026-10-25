# Cursor-shaped takes on the half-cut Caps Lock glyph. The head is the half ⇪ arrow (vertical left edge, notched base);
# the Caps Lock bar either stays underneath or swings round to become the cursor's tail.
SW='fill="{f}" stroke="{c}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'
HEAD = "M78 30V186L114 150H176Z"
FULL = "M78 30V186L112 152 136 202 158 192 134 146H176Z"
def head(d=HEAD, c="#000", f="none", w=20): return f'<path d="{d}" {SW.format(f=f, c=c, w=w)}/>'
def tail(c="#000", w=26): return f'<line x1="134" y1="186" x2="160" y2="231" stroke="{c}" stroke-width="{w}" stroke-linecap="round"/>'
V = {
  "t1-bar-tail": ("The Caps Lock bar swings round to become the cursor's tail: ⇪ cut in half is a pointer.",
                  head() + tail()),
  "t2-solid-tail": ("Solid half-arrow with the detached bar as tail: the boldest, for the menu bar.",
                    head(f="#000") + tail()),
  "t3-bar-under": ("Notched half-arrow with the Caps Lock bar kept flat underneath, as on the key.",
                   head() + '<rect x="68" y="214" width="76" height="24" rx="8"/>'),
  "t4-full-cursor": ("A whole cursor outline drawn with the ⇪ stroke, the bar flat beneath it.",
                     head(FULL) + '<rect x="68" y="226" width="64" height="22" rx="8"/>'),
  "t5-keycap": ("The Caps Lock key, its legend turned into the bar-tailed pointer (app icon).",
                '<rect x="8" y="8" width="240" height="240" rx="56"/>'
                '<g transform="translate(46 44) scale(0.66)">' + head(c="#fff", w=24) + tail("#fff", 30) + '</g>'),
}
# Optical centring per variant (dx, dy) — the head's mass sits left, so nudge right of the bbox centre.
OFF = {"t1-bar-tail": (8, -6), "t2-solid-tail": (8, -6), "t3-bar-under": (14, -6), "t4-full-cursor": (18, -10), "t5-keycap": (0, 0)}
for name, (note, body) in V.items():
    dx, dy = OFF[name]
    open(f"cursor-variants/{name}.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Hyperpoint</title>'
        f'<g transform="translate({dx} {dy})">{body}</g></svg>\n')
    open(f"cursor-variants/{name}-lockup.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 256"><title>Hyperpoint</title>'
        f'<g transform="translate({24+dx*0.6875:.1f} {40+dy*0.6875:.1f}) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-3">Hyperpoint</text></svg>\n')
    open(f"cursor-variants/{name}.txt", "w").write(note)
