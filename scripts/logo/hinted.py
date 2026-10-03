"""Pixel-hinted small marks. Geometry is authored directly on the target pixel grid (1 unit = 1 px),
so ring extremes and the stem's edges land on whole pixels when rendered at 1:1."""
import math
from pathutil import fmt


def ring_path(cx, cy, r_out, r_in, gap_deg, nd=3):
    """Arc of an annulus from +gap to -gap (through 6 o'clock), with round caps."""
    f = lambda v: fmt(v, nd)
    h = (r_out - r_in) / 2
    t = math.radians(gap_deg)
    s, c = math.sin(t), math.cos(t)
    p1 = (cx + r_out * s, cy - r_out * c); p2 = (cx - r_out * s, cy - r_out * c)
    p3 = (cx - r_in * s, cy - r_in * c); p4 = (cx + r_in * s, cy - r_in * c)
    return (f"M{f(p1[0])} {f(p1[1])}A{f(r_out)} {f(r_out)} 0 1 1 {f(p2[0])} {f(p2[1])}"
            f"A{f(h)} {f(h)} 0 0 1 {f(p3[0])} {f(p3[1])}A{f(r_in)} {f(r_in)} 0 1 0 {f(p4[0])} {f(p4[1])}"
            f"A{f(h)} {f(h)} 0 0 1 {f(p1[0])} {f(p1[1])}Z")


def stem_path(x1, x2, y1, y2, cap=0.0, nd=3):
    """Vertical bar from (x1,y1) to (x2,y2). cap = corner radius (0 = square ends, (x2-x1)/2 = round)."""
    f = lambda v: fmt(v, nd)
    if cap <= 0:
        return f"M{f(x1)} {f(y1)}H{f(x2)}V{f(y2)}H{f(x1)}Z"
    k = cap
    return (f"M{f(x1)} {f(y1 + k)}A{f(k)} {f(k)} 0 0 1 {f(x1 + k)} {f(y1)}H{f(x2 - k)}"
            f"A{f(k)} {f(k)} 0 0 1 {f(x2)} {f(y1 + k)}V{f(y2 - k)}A{f(k)} {f(k)} 0 0 1 {f(x2 - k)} {f(y2)}"
            f"H{f(x1 + k)}A{f(k)} {f(k)} 0 0 1 {f(x1)} {f(y2 - k)}Z")


def glyph_d(spec):
    cx, cy = spec['ring_c']
    d = ring_path(cx, cy, spec['r_out'], spec['r_in'], spec['gap'])
    x1, x2, y1, y2 = spec['stem']
    return d + stem_path(x1, x2, y1, y2, spec.get('cap', 0))


def clearance(spec):
    """Smallest distance between the stem's edge and a ring cap (px)."""
    cx, cy = spec['ring_c']
    rc = (spec['r_out'] + spec['r_in']) / 2
    h = (spec['r_out'] - spec['r_in']) / 2
    t = math.radians(spec['gap'])
    capx = cx + rc * math.sin(t)
    return capx - h - spec['stem'][1]
