# Rat face-on variations: wedge snout, ears, eyes. White shapes are knockouts (ear gaps, eyes).
def face(ink="#000", bg="#fff", snout="M48 96H208L136 216Q128 228 120 216Z", ears="round", er=36, ex=70, ey=78,
         eyes=((104, 128), (152, 128)), nose=False):
    if ears == "round":
        e = "".join(f'<circle cx="{x}" cy="{ey}" r="{er + 10}" fill="{bg}"/><circle cx="{x}" cy="{ey}" r="{er}" fill="{ink}"/>'
                    for x in (ex, 256 - ex))
    else:  # tall ovals tipped outward, more rat than mouse
        e = "".join(f'<ellipse cx="{x}" cy="{ey}" rx="{er + 10}" ry="{er * 1.3 + 10:.0f}" transform="rotate({r} {x} {ey})" fill="{bg}"/>'
                    f'<ellipse cx="{x}" cy="{ey}" rx="{er}" ry="{er * 1.3:.0f}" transform="rotate({r} {x} {ey})" fill="{ink}"/>'
                    for x, r in ((ex, -25), (256 - ex, 25)))
    body = f'<path d="{snout}" fill="{ink}" stroke="{ink}" stroke-width="28" stroke-linejoin="round"/>'
    if nose:  # the snout tip split off as a nose: the "point"
        body += f'<circle cx="128" cy="214" r="30" fill="{bg}"/><circle cx="128" cy="218" r="18" fill="{ink}"/>'
    return body + e + "".join(f'<circle cx="{x}" cy="{y}" r="11" fill="{bg}"/>' for x, y in eyes)

LONG = "M60 100H196L138 222Q128 236 118 222Z"
MARKS = {
  "f1-refined": ("The face from last round, tidied: balanced ears, eyes set into the brow.", face()),
  "f2-long-snout": ("A longer, narrower snout and smaller ears: reads rat, not mouse.",
                    face(snout=LONG, er=30, ex=74, ey=82, eyes=((108, 132), (148, 132)))),
  "f3-oval-ears": ("Tall ears tipped outward: alert, a bit mischievous, further from Mickey.",
                   face(snout=LONG, ears="oval", er=26, ex=72, ey=76, eyes=((108, 132), (148, 132)))),
  "f4-nose": ("The snout tip split off as a nose: the cursor's point, on the rat.",
              face(snout=LONG, er=30, ex=74, ey=82, eyes=((108, 132), (148, 132)), nose=True)),
  "f5-app-icon": ("App icon: the long-snout rat in white on a dark tile.",
                  '<rect x="8" y="8" width="240" height="240" rx="56"/><g transform="translate(32 34) scale(0.75)">'
                  + face(ink="#fff", bg="#000", snout=LONG, er=30, ex=74, ey=82, eyes=((108, 132), (148, 132))) + '</g>'),
}
for n, (note, body) in MARKS.items():
    open(f"face/{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ratchet</title>{body}</svg>\n')
    open(f"face/{n}-lockup.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 256"><title>Ratchet</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">Ratchet</text></svg>\n')
    open(f"face/{n}.txt", "w").write(note)
