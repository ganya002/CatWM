import os, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

HERE = os.path.dirname(os.path.abspath(__file__))
font = TTFont(os.path.join(HERE, "../../Resources/Fonts/DelaGothicOne-Regular.ttf"))
gs, cmap = font.getGlyphSet(), font.getBestCmap()
hmtx = font["hmtx"]


def text(s, cx, cy, cap, sx=1.0, track=0):
    """Outline `s`, centred on (cx, cy) by ink bounds, cap height `cap` px. sx squashes horizontally."""
    k = cap / 726.0
    names = [cmap[ord(c)] for c in s]
    bp = BoundsPen(gs)
    x = 0
    for n in names:
        gs[n].draw(TransformPen(bp, (1, 0, 0, 1, x, 0)))
        x += hmtx[n][0] + track
    x0, y0, x1, y1 = bp.bounds
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.1f}")
    ox = cx - (x0 + x1) / 2 * k * sx
    oy = cy + (y0 + y1) / 2 * k
    x = 0
    for n in names:
        gs[n].draw(TransformPen(pen, (k * sx, 0, 0, -k, ox + x * k * sx, oy)))
        x += hmtx[n][0] + track
    return pen.getCommands()


DEFS = """
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a4a4f"/><stop offset="1" stop-color="#1b1b1e"/></linearGradient>
<linearGradient id="bgblue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5aa8ff"/><stop offset="1" stop-color="#0a63e8"/></linearGradient>
<linearGradient id="bglight" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#dcdce2"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".25"/><stop offset="1" stop-color="#fff" stop-opacity=".05"/></linearGradient>
<linearGradient id="blue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8dc3ff"/><stop offset=".45" stop-color="#3f95ff"/><stop offset="1" stop-color="#0a74ff"/></linearGradient>
<linearGradient id="white" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fdfdfd"/><stop offset="1" stop-color="#e6e6eb"/></linearGradient>
<linearGradient id="graphite" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a4a50"/><stop offset="1" stop-color="#26262a"/></linearGradient>
<filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
<filter id="drop" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
"""


def squircle(fill):
    return f"""<rect x="100" y="112" width="824" height="824" rx="185" fill="#000" opacity=".35" filter="url(#drop)"/>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#{fill})"/>
<rect x="101" y="101" width="822" height="822" rx="184" fill="none" stroke="url(#rim)" stroke-width="2"/>"""


def win(x, y, w, h, fill="white", edge="#a8a8b0", dots="#c7c7cc", r=30, shadow=False, depth=8):
    d = dots if isinstance(dots, (list, tuple)) else [dots] * 3
    out = ""
    if shadow:
        out += f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#000" opacity=".4" filter="url(#soft)" transform="translate(6 20)"/>'
    out += f'<rect x="{x+5}" y="{y+depth}" width="{w}" height="{h}" rx="{r}" fill="{edge}"/>'
    out += f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#{fill})"/>'
    out += f'<rect x="{x+1.5}" y="{y+1.5}" width="{w-3}" height="{h-3}" rx="{r-1.5}" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="2"/>'
    for i, c in enumerate(d):
        out += f'<circle cx="{x+26+22*i}" cy="{y+24}" r="7" fill="{c}"/>'
    return out


TRAFFIC = ["#ff5f57", "#febc2e", "#28c840"]
INK = "#18181b"


def svg(body, note):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<!-- Ouch app icon: {note}. Lettering is Dela Gothic One (SIL OFL 1.1), outlined to paths. -->
<defs>{DEFS}</defs>
{body}
</svg>"""


def burst(cx, cy, rays, color="#ffcc00", w=12):
    import math
    out = ""
    for ang, r0, r1 in rays:
        a = math.radians(ang)
        out += f'<line x1="{cx+r0*math.cos(a):.1f}" y1="{cy+r0*math.sin(a):.1f}" x2="{cx+r1*math.cos(a):.1f}" y2="{cy+r1*math.sin(a):.1f}" stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>'
    return out


concepts = {}

# A — Snap: a true tiled layout (equal gaps) with the Ouch window slamming in at an angle.
concepts["a-snap"] = svg(
    squircle("bg")
    + win(220, 220, 280, 584, "blue", "#0b52bd", ["#fff"] * 3)
    .replace('fill="#fff"/>', 'fill="#fff" fill-opacity=".45"/>')
    + win(524, 220, 280, 280)
    + win(524, 524, 280, 280)
    + burst(322, 412, [(190, 26, 70), (225, 26, 76), (260, 26, 66)])
    + '<g transform="rotate(-9 512 512)">'
    + win(340, 398, 344, 236, shadow=True, dots=TRAFFIC)
    + f'<path d="{text("Ouch", 512, 528, 78)}" fill="{INK}"/></g>',
    "concept A, Snap",
)

# B — Master tile: light squircle, the wordmark lives in the blue master window of a real tiled layout.
concepts["b-master"] = svg(
    squircle("bglight")
    + win(196, 196, 404, 632, "blue", "#0b52bd", TRAFFIC, r=34)
    + win(624, 196, 204, 304, "graphite", "#111114", ["#6b6b72"] * 3, r=34)
    + win(624, 524, 204, 304, "graphite", "#111114", ["#6b6b72"] * 3, r=34)
    + f'<path d="{text("Ouch", 398, 520, 86, sx=0.92)}" fill="#fff"/>',
    "concept B, Master tile",
)

# C — Monogram: one heavy Dela "O"; its counter is a tiny tiled desktop.
o = text("O", 512, 512, 480)
concepts["c-monogram"] = svg(
    squircle("bgblue")
    + f'<path d="{o}" fill="#000" opacity=".25" filter="url(#soft)" transform="translate(0 18)"/>'
    + f'<path d="{o}" fill="url(#white)"/>'
    + '<rect x="452" y="452" width="56" height="120" rx="12" fill="url(#blue)"/>'
    + '<rect x="516" y="452" width="56" height="56" rx="12" fill="#2a2a2e"/>'
    + '<rect x="516" y="516" width="56" height="56" rx="12" fill="#2a2a2e"/>',
    "concept C, Monogram",
)

# D — Squish: the Ouch window gets pinched between two tiles closing in; lettering squashed to match.
concepts["d-squish"] = svg(
    squircle("bg")
    + win(150, 250, 300, 524, "blue", "#0b52bd", ["#fff"] * 3).replace('fill="#fff"/>', 'fill="#fff" fill-opacity=".45"/>')
    + win(574, 250, 300, 524)
    + win(440, 330, 144, 364, shadow=True, dots=TRAFFIC, r=24)
    + f'<path d="{text("Ouch", 512, 530, 120, sx=0.26)}" fill="{INK}"/>'
    + burst(512, 312, [(-90, 18, 60), (-130, 22, 58), (-50, 22, 58)], "#ffcc00", 11)
    + burst(512, 716, [(90, 18, 60), (130, 22, 58), (50, 22, 58)], "#ffcc00", 11),
    "concept D, Squish",
)

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for k, v in concepts.items():
    open(os.path.join(out, f"ouch-{k}.svg"), "w").write(v)
print("ok")
