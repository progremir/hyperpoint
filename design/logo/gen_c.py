# Variants of concept C: the Caps Lock glyph (outlined arrow + bar) becoming a pointer.
SW='fill="none" stroke="{c}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'
def outline(d, c="#000", w=20): return f'<path d="{d}" {SW.format(c=c, w=w)}/>'
# Half-headed caps arrow: left wing dropped, so the head is a cursor (vertical left edge, 45-degree right edge).
HALF = "M76 32 180 136H136V180H76Z"
V = {
  "c1-half-head": ("Upright ⇪ with the left wing dropped: it stays the key legend but its head is now a cursor.",
                   outline(HALF) + '<rect x="66" y="204" width="80" height="24" rx="8"/>'),
  "c2-caps-light": ("Same half-head pointer, but the Caps Lock bar becomes the point: the key's light.",
                    outline(HALF) + '<circle cx="106" cy="218" r="17"/>'),
  "c3-tipped-45": ("Symmetric ⇪ tipped exactly 45° so one wing turns vertical and it lands as a pointer.",
                   '<g transform="rotate(-45 128 128)">' + outline("M128 34 214 120H164V166H92V120H42Z")
                   + '<rect x="88" y="190" width="80" height="24" rx="8"/></g>'),
  "c4-solid": ("Solid cursor sitting on the Caps Lock bar: bolder, reads at menu-bar size.",
               f'<path d="{HALF}" stroke="#000" stroke-width="20" stroke-linejoin="round"/>'
               '<rect x="66" y="204" width="80" height="24" rx="8"/>'),
  "c5-keycap": ("The Caps Lock key itself, its legend already turned into a pointer.",
                '<rect x="8" y="8" width="240" height="240" rx="56"/>'
                '<g transform="translate(37 45) scale(0.66)">' + outline(HALF, "#fff", 24)
                + '<rect x="66" y="204" width="80" height="26" rx="9" fill="#fff"/></g>'),
}
for name, (note, body) in V.items():
    open(f"c-variants/{name}.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Hyperpoint</title>'
        f'<g transform="translate({0 if name=="c5-keycap" else 6} 0)">{body}</g></svg>\n')
    open(f"c-variants/{name}-lockup.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 256"><title>Hyperpoint</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-3">Hyperpoint</text></svg>\n')
    open(f"c-variants/{name}.txt", "w").write(note)
