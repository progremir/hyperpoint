# Mouse rat variations: a computer mouse from above with rat ears and a tail; the scroll wheel is the nose.
def rat(ink="#000", bg="#fff", seam=False, tail="curve"):
    gap = lambda cx, cy, r: f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="{bg}"/><circle cx="{cx}" cy="{cy}" r="{r}" fill="{ink}"/>'
    t = {
        "curve": '<path d="M128 204C128 246 194 246 212 210" fill="none" stroke="{i}" stroke-width="14" stroke-linecap="round"/>',
        # Ratchet tail: the curve broken into one-way steps, each with a steep face and a slope.
        "ratchet": '<path d="M128 204L136 236L156 222L170 240L188 222L210 226" fill="none" stroke="{i}" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>',
    }[tail].format(i=ink)
    return (t + f'<rect x="68" y="60" width="120" height="148" rx="60" fill="{ink}"/>'
            + gap(82, 64, 26) + gap(174, 64, 26)
            + (f'<rect x="125" y="60" width="6" height="30" fill="{bg}"/>' if seam else "")
            + f'<rect x="120" y="90" width="16" height="40" rx="8" fill="{bg}"/>')
MARKS = {
  "m1-refined": ("Cleaner proportions: tighter ears, wheel as the nose, one smooth tail.", rat()),
  "m2-buttons": ("A seam between the mouse buttons runs up to the wheel: unmistakably a computer mouse.", rat(seam=True)),
  "m3-ratchet-tail": ("The tail clicks along in one-way steps: the ratchet half of the name.", rat(tail="ratchet")),
  "m4-app-icon": ("App icon: the rat knocked out of a dark key-shaped tile.",
                  '<rect x="8" y="8" width="240" height="240" rx="56"/><g transform="translate(30 22) scale(0.76)">'
                  + rat(ink="#fff", bg="#000") + '</g>'),
}
for n, (note, body) in MARKS.items():
    open(f"mouse-rat/{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ratchet</title>{body}</svg>\n')
    open(f"mouse-rat/{n}-lockup.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 256"><title>Ratchet</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">Ratchet</text></svg>\n')
    open(f"mouse-rat/{n}.txt", "w").write(note)
