# Round 2: new names, one mark each. Filled geometry on a 256 grid; white shapes are knockouts for exploration.
MARKS = {
  # Knurl: the ridged grip on a scroll wheel. A wheel seen edge-on with three slanted ridges cut through it.
  "knurl": '<g transform="translate(128 128) scale(0.86) rotate(45) translate(-92.0 -92.0)"><rect x="0" y="0" width="52" height="52" rx="8"/><rect x="0" y="66" width="52" height="52" rx="8"/><rect x="0" y="132" width="52" height="52" rx="8"/><rect x="66" y="0" width="52" height="52" rx="8"/><rect x="66" y="66" width="52" height="52" rx="8"/><rect x="66" y="132" width="52" height="52" rx="8"/><rect x="132" y="0" width="52" height="52" rx="8"/><rect x="132" y="66" width="52" height="52" rx="8"/><rect x="132" y="132" width="52" height="52" rx="8"/></g>',
  # Detent: a ball resting in its notch, the click-step of a wheel (and settings that snap back into place).
  "detent": '<g transform="translate(0 -16)"><path d="M40 136H48A24 24 0 0 0 96 136H98A30 30 0 0 0 158 136H160A24 24 0 0 0 208 136H216A24 24 0 0 1 240 160V184A24 24 0 0 1 216 208H40A24 24 0 0 1 16 184V160A24 24 0 0 1 40 136Z"/><circle cx="128" cy="130" r="22"/></g>',
  # Chord: four keys held as one. Four rounded keys fused into one key-shaped block, the seams stopping short of the edge.
  "chord": '<ellipse cx="112" cy="52" rx="58" ry="40" transform="rotate(-20 112 52)"/><ellipse cx="144" cy="128" rx="58" ry="40" transform="rotate(-20 144 128)"/><ellipse cx="112" cy="204" rx="58" ry="40" transform="rotate(-20 112 204)"/>',
}
NOTES = {
  "knurl": "Knurl: the diamond grip texture on a scroll wheel, nine facets.",
  "detent": "Detent: a ball clicking into its notch; settings snap back into place on every connect.",
  "chord": "Chord: stacked noteheads; four modifiers sounded as one.",
}
for n, body in MARKS.items():
    open(f"{n}.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>{n}</title>{body}</svg>\n')
    word = n.capitalize()
    open(f"{n}-lockup.svg", "w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 256"><title>{word}</title>'
        f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
        f'<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-2">{word}</text></svg>\n')
    open(f"{n}.txt", "w").write(NOTES[n])
