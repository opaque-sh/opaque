#!/usr/bin/env python3
"""Generate the Opaque logo concepts as SVG into brand/logo/.

    python3 tools/gen_logos.py

Concept 1, dissolving disc: a solid circle that breaks into halftone dots.
Concept 2, sliced o: a ring cut into horizontal slats, plus a lockup with an outlined mono wordmark.
Wordmark glyphs are outlined from Geist Mono Medium (SIL Open Font License, see brand/fonts) so no font is needed to
display the SVGs. Swap FONT for another mono face to change the wordmark.
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "brand", "logo")
os.makedirs(OUT, exist_ok=True)

BG = "#07090a"
FG = "#ececec"
TEAL = "#2ee6c5"
FONT = os.path.join(os.path.dirname(__file__), "..", "brand", "fonts", "GeistMono-Medium.ttf")


def write(name, svg):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(svg)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ concept 1: dissolving disc

def disc(cell, fg, bg, tile, glow, name):
    size = 512
    cx = cy = 256
    R = 176
    dots, teal_dots = [], []
    row_h = cell * math.sqrt(3) / 2
    rows = int(size / row_h) + 2
    for j in range(rows):
        y = j * row_h
        x0 = (cell / 2) if j % 2 else 0
        i = 0
        while x0 + i * cell < size:
            x = x0 + i * cell
            i += 1
            if (x - cx) ** 2 + (y - cy) ** 2 > (R + cell * 0.4) ** 2:
                continue
            # dissolve front runs left to right, tilted a little so it does not look like a scanline
            u = (x - (cx - R)) + 0.28 * (y - cy)
            t = (u - R * 0.55) / (R * 1.95)
            if t <= -0.10:
                continue  # solid region is drawn as one shape below
            r = cell * 0.62 if t <= 0 else cell * 0.62 * (1 - smooth(t)) ** 1.2
            if r < 0.7:
                continue
            is_teal = 0.42 < t < 0.80 and ((j * 7 + i * 13) % 6 == 0)
            (teal_dots if is_teal else dots).append((x, y, r))
    # solid left part: the disc clipped to u < R*0.55 + a little overlap with the first dots
    solid_edge = lambda y: (cx - R) + R * 0.55 - 0.28 * (y - cy) + cell * 0.2

    def circ(items, color):
        return "".join('<circle cx="%.1f" cy="%.1f" r="%.2f" fill="%s"/>' % (x, y, r, color) for x, y, r in items)

    # solid region as a polygon clipped by the circle: slanted edge from top to bottom
    top, bot = cy - R - 4, cy + R + 4
    solid = '<path d="M0 %d H%.1f L%.1f %d H0 Z" fill="%s" clip-path="url(#d)"/>' % (
        top, solid_edge(top), solid_edge(bot), bot, fg
    )
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="Opaque">']
    parts.append('<defs><clipPath id="d"><circle cx="%d" cy="%d" r="%d"/></clipPath>' % (cx, cy, R))
    if glow:
        parts.append('<filter id="g" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="7"/></filter>')
    parts.append("</defs>")
    if tile:
        parts.append('<rect width="512" height="512" rx="112" fill="%s"/>' % bg)
    if glow and teal_dots:
        parts.append('<g filter="url(#g)" opacity="0.9">%s</g>' % circ(teal_dots, TEAL))
    parts.append(solid)
    parts.append('<g clip-path="url(#d)">' + circ(dots, fg) + (circ(teal_dots, TEAL if glow else fg) if teal_dots else "") + "</g>")
    parts.append("</svg>")
    write(name, "\n".join(parts))


disc(11, FG, BG, True, True, "disc-full.svg")
disc(11, "#ffffff", BG, False, False, "disc-mono-white.svg")
disc(11, "#000000", BG, False, False, "disc-mono-black.svg")
disc(24, FG, BG, True, False, "disc-icon.svg")


# ------------------------------------------------------------------ concept 2: sliced o

def ring_path(cx, cy, R, r):
    return (
        "M%.2f %.2f A%.2f %.2f 0 1 0 %.2f %.2f A%.2f %.2f 0 1 0 %.2f %.2f Z "
        "M%.2f %.2f A%.2f %.2f 0 1 1 %.2f %.2f A%.2f %.2f 0 1 1 %.2f %.2f Z"
    ) % (
        cx - R, cy, R, R, cx + R, cy, R, R, cx - R, cy,
        cx - r, cy, r, r, cx + r, cy, r, r, cx - r, cy,
    )


def slats(cx, cy, R, n, gap, uid):
    """Clip rects: n bands across the diameter separated by gaps. Gap centered on the middle if n is even."""
    total = 2 * R
    band = (total - gap * (n - 1)) / n
    rects = []
    y = cy - R
    for k in range(n):
        rects.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f"/>' % (cx - R - 1, y, 2 * R + 2, band))
        y += band + gap
    return '<clipPath id="%s">%s</clipPath>' % (uid, "".join(rects)), band


def sliced_o(fg, bg, tile, teal, name):
    cx = cy = 256
    R, r = 190, 108
    n, gap = 9, 9
    clip, band = slats(cx, cy, R, n, gap, "s")
    mid_gap_y = cy - R + 4 * (band + gap) + band + gap / 2  # gap between band 5 and 6 centre
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="Opaque">']
    parts.append("<defs>%s</defs>" % clip)
    if tile:
        parts.append('<rect width="512" height="512" rx="112" fill="%s"/>' % bg)
    parts.append('<path d="%s" fill="%s" fill-rule="evenodd" clip-path="url(#s)"/>' % (ring_path(cx, cy, R, r), fg))
    if teal:
        parts.append(
            '<rect x="%.2f" y="%.2f" width="%.2f" height="3" fill="%s"/>' % (cx - R, mid_gap_y - 1.5, 2 * R, TEAL)
        )
    parts.append("</svg>")
    write(name, "\n".join(parts))


sliced_o(FG, BG, True, True, "o-full.svg")
sliced_o("#ffffff", BG, False, False, "o-mono-white.svg")
sliced_o("#000000", BG, False, False, "o-mono-black.svg")


# ------------------------------------------------------------------ concept 2: lockup "opaque"

def lockup(fg, bg, tile, teal, name):
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(FONT)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    from fontTools.pens.boundsPen import BoundsPen

    bp = BoundsPen(gs)
    gs[cmap[ord("x")]].draw(bp)
    xh = bp.bounds[3]  # top of the lowercase x is the x-height
    S = 200.0
    k = S / upm
    adv = font["hmtx"][cmap[ord("a")]][0] * k
    xheight = xh * k
    overshoot = 0.012 * S

    pad = 56
    base_y = pad + 150  # baseline; ascender room above for p, q descender below
    # the sliced o takes the first character cell
    R = xheight / 2 + overshoot * 1.6
    r = R - 0.118 * S  # a touch heavier than the stems, slats make it read lighter
    ocx = pad + adv / 2
    ocy = base_y - xheight / 2
    n, gap = 7, 3.4
    clip, band = slats(ocx, ocy, R, n, gap, "s")

    paths = []
    for i, ch in enumerate("paque", start=1):
        pen = SVGPathPen(gs)
        tp = TransformPen(pen, (k, 0, 0, -k, pad + i * adv, base_y))
        gs[cmap[ord(ch)]].draw(tp)
        paths.append(pen.getCommands())

    w = pad * 2 + adv * 6
    h = base_y + 0.25 * S + pad
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f" role="img" aria-label="opaque">' % (w, h, w, h)]
    parts.append("<defs>%s</defs>" % clip)
    if tile:
        parts.append('<rect width="%.0f" height="%.0f" fill="%s"/>' % (w, h, bg))
    parts.append('<path d="%s" fill="%s" fill-rule="evenodd" clip-path="url(#s)"/>' % (ring_path(ocx, ocy, R, r), fg))
    parts.append('<path d="%s" fill="%s"/>' % (" ".join(paths), fg))
    if teal:
        mid = ocy - R + 3 * (band + gap) + band + gap / 2
        parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="1.6" fill="%s"/>' % (ocx - R, mid - 0.8, 2 * R, TEAL))
    parts.append("</svg>")
    write(name, "\n".join(parts))


lockup(FG, BG, True, True, "lockup-full.svg")
lockup("#ffffff", BG, False, False, "lockup-mono-white.svg")
lockup("#000000", BG, False, False, "lockup-mono-black.svg")
print("wrote", sorted(os.listdir(OUT)))


# ------------------------------------------------------------------ single-shape silhouettes for shader extrusion
# One filled path each, no slats, dots or glow. Meant as the input mark for extrusion shaders.

def silhouettes():
    d = os.path.join(OUT, "shader")
    os.makedirs(d, exist_ok=True)
    cx = cy = 256
    R, r, h = 190, 108, 8

    def save(name, path):
        svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            '<path d="%s" fill="#ffffff" fill-rule="evenodd"/></svg>' % path
        )
        with open(os.path.join(d, name), "w") as f:
            f.write(svg)

    # solid disc
    save("shape-disc.svg", "M%d %d A%d %d 0 1 0 %d %d A%d %d 0 1 0 %d %d Z" % (cx - R, cy, R, R, cx + R, cy, R, R, cx - R, cy))
    # ring (outer and inner circle, even-odd hole)
    save("shape-ring.svg", ring_path(cx, cy, R, r))
    # ring with one slit on the right side, so it is a single simple shape with no hole
    xo = math.sqrt(R * R - h * h)
    xi = math.sqrt(r * r - h * h)
    path = "M%.2f %.2f A%d %d 0 1 0 %.2f %.2f L%.2f %.2f A%d %d 0 1 1 %.2f %.2f Z" % (
        cx + xo, cy - h, R, R, cx + xo, cy + h, cx + xi, cy + h, r, r, cx + xi, cy - h
    )
    save("shape-ring-slit.svg", path)


silhouettes()
