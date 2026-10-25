import math, re
def rot(pts, deg, c=(128,128)):
    a=math.radians(deg); out=[]
    for x,y in pts:
        dx,dy=x-c[0],y-c[1]
        out.append((c[0]+dx*math.cos(a)-dy*math.sin(a), c[1]+dx*math.sin(a)+dy*math.cos(a)))
    return out
f=lambda v: f"{v:.2f}".rstrip('0').rstrip('.')
# A: keycap with a bitten inner corner, rotated four ways (rotation about centre maps the shape onto its neighbours)
def key(deg):
    P=dict(a=(28,0),b=(92,0),c=(120,28),d=(120,76.62),e=(76.62,120),g=(28,120),h=(0,92),i=(0,28))
    R={k:rot([v],deg)[0] for k,v in P.items()}
    p=lambda k: f"{f(R[k][0])} {f(R[k][1])}"
    return (f"M{p('a')}L{p('b')}A28 28 0 0 1 {p('c')}L{p('d')}A52 52 0 0 0 {p('e')}"
            f"L{p('g')}A28 28 0 0 1 {p('h')}L{p('i')}A28 28 0 0 1 {p('a')}Z")
A="".join(f'<path d="{key(d)}"/>' for d in (0,90,180,270))+'<circle cx="128" cy="128" r="30"/>'
B='<rect x="30" y="20" width="56" height="216" rx="28"/><rect x="170" y="20" width="56" height="216" rx="28"/><circle cx="128" cy="128" r="26"/>'
# C: Caps Lock glyph (outlined arrow + bar) tipped 30 degrees into a pointer; stroke kept for exploration
C=('<g transform="rotate(-22 128 136)"><path d="M128 30 214 118H164V156H92V118H42Z" fill="none" stroke="#000" '
   'stroke-width="22" stroke-linejoin="round"/><rect x="80" y="182" width="96" height="26" rx="8"/></g>')
for n,body,t in (("a",A,"Hyperpoint, four keys one point"),("b",B,"Hyperpoint, H point"),("c",C,"Hyperpoint, caps pointer")):
    open(f"{n}-symbol.svg","w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>{t}</title>{body}</svg>\n')
    open(f"{n}-lockup.svg","w").write(
      f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 256"><title>{t}</title>'
      f'<g transform="translate(24 40) scale(0.6875)">{body}</g>'
      '<text x="236" y="166" font-family="SF Pro Display, Helvetica Neue" font-weight="600" font-size="116" letter-spacing="-3">Hyperpoint</text></svg>\n')
