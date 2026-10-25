# Ratchet = rat + ratchet. Rat marks on a 256 grid; white shapes are knockouts (gaps around ears, eyes).
GAP = lambda cx, cy, r: f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="#fff"/><circle cx="{cx}" cy="{cy}" r="{r}"/>'
MARKS = {
  # A: rat in profile. The head is one ratchet tooth: a sloped back running down to the snout, flat underside.
  "a-tooth-rat": '<g transform="translate(-4 14)">'
      '<path d="M236 176L92 72A64 64 0 0 0 92 200H220A16 16 0 0 0 236 176Z" stroke="#000" stroke-width="8" stroke-linejoin="round"/>'
      + GAP(112, 76, 30) + '<circle cx="152" cy="134" r="11" fill="#fff"/></g>',
  # B: rat face-on. A downward wedge for the snout, two round ears, two eyes.
  "b-face": '<path d="M48 96H208L136 216Q128 228 120 216Z" stroke="#000" stroke-width="28" stroke-linejoin="round"/>'
      + GAP(70, 78, 36) + GAP(186, 78, 36)
      + '<circle cx="104" cy="128" r="11" fill="#fff"/><circle cx="152" cy="128" r="11" fill="#fff"/>',
  # C: computer mouse from above, given rat ears and a tail. The scroll wheel sits where the nose would be.
  "c-mouse-rat": '<rect x="64" y="52" width="128" height="152" rx="64"/>'
      + GAP(78, 58, 26) + GAP(178, 58, 26)
      + '<rect x="120" y="84" width="16" height="44" rx="8" fill="#fff"/>'
      '<path d="M128 200C128 244 196 244 214 206" fill="none" stroke="#000" stroke-width="14" stroke-linecap="round"/>',
}
NOTES = {
  "a-tooth-rat": "A rat in profile whose head is a single ratchet tooth: the name's pun in one shape.",
  "b-face": "A rat face-on: wedge snout, round ears. Friendly mascot energy.",
  "c-mouse-rat": "A computer mouse that grew ears and a tail: mouse becomes rat.",
}
for n, body in MARKS.items():
    open(f"{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ratchet</title>{body}</svg>\n')
    open(f"{n}-lockup.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 256"><title>Ratchet</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">Ratchet</text></svg>\n')
    open(f"{n}.txt", "w").write(NOTES[n])
