"""Analytic helpers: glyph signed-distance field, SVG radial-gradient colour, WCAG contrast.
Used to check that white-on-orb contrast stays >= 3:1 under the glyph before anything is rendered."""
import math
import numpy as np


def hex2rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


def srgb_to_lin(c):
    c = np.asarray(c, dtype=float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luminance(rgb):
    lin = srgb_to_lin(rgb)
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722


def contrast_white(rgb):
    return 1.05 / (luminance(rgb) + 0.05)


def glyph_sdf(x, y, gx, gy, R, w, gap_deg, stem_top, stem_bot, stem_w=None):
    """Signed distance (negative inside) to the power glyph: round-capped arc + round-capped stem."""
    h = w / 2
    sh = (stem_w if stem_w is not None else w) / 2
    dx, dy = x - gx, y - gy
    r = np.hypot(dx, dy)
    ang = np.degrees(np.arctan2(dx, -dy))          # 0 at 12 o'clock, +clockwise
    t = math.radians(gap_deg)
    c1 = (gx + R * math.sin(t), gy - R * math.cos(t))
    c2 = (gx - R * math.sin(t), gy - R * math.cos(t))
    d_arc = np.abs(r - R) - h
    d_cap = np.minimum(np.hypot(x - c1[0], y - c1[1]), np.hypot(x - c2[0], y - c2[1])) - h
    ring = np.where(np.abs(ang) >= gap_deg, d_arc, d_cap)
    y1, y2 = gy - stem_top * R, gy - stem_bot * R
    yc = np.clip(y, y1, y2)
    stem = np.hypot(x - gx, y - yc) - sh
    return np.minimum(ring, stem)


def radial(x, y, cx, cy, r, stops, fx=None, fy=None):
    """SVG radialGradient (pad spread, sRGB interpolation). stops: [(offset, '#hex'), ...]."""
    fx = cx if fx is None else fx
    fy = cy if fy is None else fy
    if fx == cx and fy == cy:
        t = np.hypot(x - cx, y - cy) / r
    else:
        # solve |F + s*(P-F) - C| = r for the ray from F through P; t = 1/s
        px, py = x - fx, y - fy
        ox, oy = fx - cx, fy - cy
        a = px * px + py * py
        b = 2 * (px * ox + py * oy)
        c = ox * ox + oy * oy - r * r
        s = (-b + np.sqrt(np.maximum(b * b - 4 * a * c, 0))) / (2 * np.maximum(a, 1e-12))
        t = 1 / np.maximum(s, 1e-12)
    t = np.clip(t, 0, 1)
    offs = np.array([s[0] for s in stops])
    cols = np.array([hex2rgb(s[1]) for s in stops])
    out = np.empty(t.shape + (3,))
    for k in range(3):
        out[..., k] = np.interp(t, offs, cols[:, k])
    return out
