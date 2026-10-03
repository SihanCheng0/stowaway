import re, json, subprocess, os

HERE = os.path.dirname(os.path.abspath(__file__))
TOK = re.compile(r'[MLQCZ]|-?\d+(?:\.\d+)?')


def fmt(v, nd=2):
    v = round(v, nd)
    if v == int(v):
        return str(int(v))
    s = f"{v:.{nd}f}".rstrip('0').rstrip('.')
    return s.replace('-0.', '-.') if s.startswith('-0.') else (s[1:] if s.startswith('0.') else s)


def transform(d, sx, sy, tx, ty, nd=2):
    """Apply x' = x*sx+tx, y' = y*sy+ty to a simple absolute path (M L Q C Z)."""
    toks = TOK.findall(d)
    out = []
    i = 0
    cmd = None
    while i < len(toks):
        t = toks[i]
        if t in 'MLQCZ':
            cmd = t
            out.append(t)
            i += 1
            continue
        x = float(toks[i]) * sx + tx
        y = float(toks[i + 1]) * sy + ty
        out.append(fmt(x, nd) + ' ' + fmt(y, nd))
        i += 2
    # compact join
    s = ''
    for o in out:
        if o in 'MLQCZ':
            s += o
        else:
            if s and s[-1] not in 'MLQCZ':
                s += ' '
            s += o
    s = re.sub(r' -', '-', s)
    return s


def load(font, text, wght=None):
    args = [os.path.join(HERE, 'glyphs'), font, text]
    if wght is not None:
        args.append(str(wght))
    return json.loads(subprocess.check_output(args))


def wordmark(data, size, x0, baseline, tracking=0.0, kern=None, nd=2):
    """Return (path_d, width, bbox) for glyph run scaled so 1 em = size px.
    tracking: in em units added after each glyph (except last).
    kern: dict index->extra em offset applied before glyph index."""
    s = size / data['upm']
    x = 0.0
    parts = []
    minx = miny = 1e9
    maxx = maxy = -1e9
    g = data['glyphs']
    for i, gl in enumerate(g):
        if kern and i in kern:
            x += kern[i] * data['upm']
        ox = x0 + x * s
        parts.append(transform(gl['d'], s, -s, ox, baseline, nd))
        b = gl['bbox']
        minx = min(minx, ox + b[0] * s); maxx = max(maxx, ox + b[2] * s)
        miny = min(miny, baseline - b[3] * s); maxy = max(maxy, baseline - b[1] * s)
        x += gl['advance']
        if i < len(g) - 1:
            x += tracking * data['upm']
    return ''.join(parts), (minx, miny, maxx, maxy)
