"""Measures the rendered marks and the wordmark spacing.

Contrast: for every size, white vs the orb colour at each pixel the glyph touches (any coverage),
read from an orb-only render; also with the glyph footprint grown by 1 px.
Spacing: per letter pair, the gap between ink bounding boxes (lockup units, 1 em = 100), the
closest ink-to-ink distance, and the mean horizontal gap across the x-height band."""
import json, os, re, sys
import numpy as np
from PIL import Image
from geom import contrast_white

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORK = os.environ.get('LOGO_WORK') or os.path.join(ROOT, 'work')


def contrast_report():
    rows = {}
    for s in (16, 32, 64, 128, 512, 1024):
        orb = np.asarray(Image.open(f'{WORK}/orb-{s}.png').convert('RGBA'), dtype=float)
        gly = np.asarray(Image.open(f'{WORK}/glyph-{s}.png').convert('RGBA'), dtype=float)[..., 3] / 255
        assert orb[gly > 0][:, 3].min() == 255, 'glyph reaches the orb edge'
        cr = contrast_white(orb[..., :3])
        under = gly > 0
        grown = under.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                grown |= np.roll(np.roll(under, dy, 0), dx, 1)
        i = np.unravel_index(np.argmin(np.where(under, cr, 99)), cr.shape)
        rows[s] = dict(min=round(float(cr[under].min()), 2), min_grown=round(float(cr[grown].min()), 2),
                       median=round(float(np.median(cr[under])), 2),
                       lightest='#%02X%02X%02X' % tuple(int(v) for v in orb[i][:3]))
    return rows


TOK = re.compile(r'[MLQCZ]|-?\d+(?:\.\d+)?')


def outline_points(d, step=4.0):
    """Sample a font-unit outline (M L Q C Z, absolute) every ~step units."""
    toks = TOK.findall(d); i = 0; pts = []; cur = start = None; cmd = None
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if toks[i] in 'MLQCZ':
            cmd = toks[i]; i += 1
            if cmd == 'Z':
                if cur is not None and start is not None:
                    pts += list(zip(np.linspace(cur[0], start[0], 20), np.linspace(cur[1], start[1], 20)))
                cur = start
                continue
        if cmd == 'M':
            cur = start = (num(), num()); pts.append(cur)
        elif cmd == 'L':
            p = (num(), num()); n = max(2, int(np.hypot(p[0] - cur[0], p[1] - cur[1]) / step))
            pts += list(zip(np.linspace(cur[0], p[0], n), np.linspace(cur[1], p[1], n))); cur = p
        elif cmd == 'Q':
            c1 = (num(), num()); p = (num(), num()); t = np.linspace(0, 1, 40)[:, None]
            a, b, e = np.array(cur), np.array(c1), np.array(p)
            pts += [tuple(v) for v in (1 - t)**2 * a + 2 * (1 - t) * t * b + t**2 * e]; cur = p
        elif cmd == 'C':
            c1 = (num(), num()); c2 = (num(), num()); p = (num(), num()); t = np.linspace(0, 1, 60)[:, None]
            a, b, c, e = np.array(cur), np.array(c1), np.array(c2), np.array(p)
            pts += [tuple(v) for v in (1 - t)**3 * a + 3 * (1 - t)**2 * t * b + 3 * (1 - t) * t**2 * c + t**3 * e]
            cur = p
    return np.array(pts)


def spacing_report(kern, tracking=-0.03):
    data = json.load(open(f'{WORK}/glyphs.json'))
    upm, xh = data['upm'], data['xHeight']
    g = data['glyphs']
    x = 0.0; xs = []
    for i, gl in enumerate(g):
        x += kern.get(i, 0) * upm
        xs.append(x)
        x += gl['advance'] + (tracking * upm if i < len(g) - 1 else 0)
    pts = [outline_points(gl['d']) + [xs[i], 0] for i, gl in enumerate(g)]
    out = []
    for i in range(len(g) - 1):
        a, b = g[i], g[i + 1]
        bbox_gap = (xs[i + 1] + b['bbox'][0]) - (xs[i] + a['bbox'][2])
        pa, pb = pts[i], pts[i + 1]
        dmin = np.sqrt(((pa[:, None, :] - pb[None, :, :])**2).sum(-1)).min()
        # mean horizontal gap across the x-height band, rows of 10 units
        gaps = []
        for y0 in np.arange(0, xh, 10):
            ra = pa[(pa[:, 1] >= y0) & (pa[:, 1] < y0 + 10)]
            rb = pb[(pb[:, 1] >= y0) & (pb[:, 1] < y0 + 10)]
            if len(ra) and len(rb):
                gaps.append(rb[:, 0].min() - ra[:, 0].max())
        out.append(dict(pair=a['char'] + b['char'], bbox=round(bbox_gap / 10, 2), closest=round(dmin / 10, 2),
                        band_mean=round(float(np.mean(gaps)) / 10, 2)))
    return out


if __name__ == '__main__':
    report = {}
    if '--spacing-only' not in sys.argv:
        report['contrast'] = contrast_report()
    report['spacing_before'] = spacing_report({1: -0.03, 2: -0.035, 7: -0.02})
    report['spacing_after'] = spacing_report({1: -0.053, 2: -0.060, 7: -0.02})
    print(json.dumps(report, indent=1))
