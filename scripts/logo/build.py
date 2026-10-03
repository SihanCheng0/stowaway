"""Builds the final Stowaway "Orb" logo set.

out/  : mark.svg, mark-flat.svg, mark-mono.svg, logo-light.svg, logo-dark.svg
work/ : mark-16.svg, mark-32.svg (pixel-hinted sources) and orb-only / glyph-only variants used to
        measure contrast. All geometry is computed here; the wordmark is Geist Mono Medium (OFL)
        outlined to paths."""
import math, os, sys, json
from pathutil import load, wordmark, fmt
from hinted import ring_path, stem_path, clearance

HERE = os.path.dirname(os.path.abspath(__file__))
P = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
OUT = P.get('out') or os.path.join(os.path.dirname(HERE), 'out')
WORK = P.get('work') or os.path.join(os.path.dirname(HERE), 'work')
os.makedirs(OUT, exist_ok=True); os.makedirs(WORK, exist_ok=True)

# ---------------- palette ----------------
HI, MID, LO = '#F0A07E', '#D97757', '#B85A3E'
GLYPH = '#FFFFFF'
MONO = '#141110'
INK_LIGHT = '#2B2421'   # wordmark on light backgrounds
INK_DARK = '#F2EBE6'    # wordmark on dark backgrounds

# ---------------- master mark geometry (256 x 256) ----------------
C = 128.0
ORB_R = 128.0
RING_R = P.get('ring_r', 57.0)     # centreline radius of the power ring
STROKE = P.get('stroke', 21.0)     # ring and stem
GAP_DEG = P.get('gap', 31.0)       # 12 o'clock to ring end-cap centre; the app icon's 62 deg opening
STEM_TOP = 1.24                    # stem top cap centre, in RING_R above ring centre
STEM_BOT = 0.10                    # stem bottom cap centre, in RING_R above ring centre
OPT = 0.5                          # 0 = ring centred, 1 = bbox centred

# ---------------- light ----------------
# Radial gradient whose centre sits outside the orb, up and to the left, so the highlight is a soft
# lit edge. The #D97757 stop is placed on the glyph's nearest point (plus MARGIN), so everything
# under the glyph is #D97757 or darker: white on #D97757 is 3.12:1.
LIGHT_DIR = (-0.55, -0.65)
LIGHT_D = P.get('light_d', 1.6)    # gradient centre distance from orb centre, in orb radii
MARGIN = P.get('margin', 5.0)      # 256-units around the glyph that stay at #D97757 or darker
EASE = P.get('ease', (1.5, 0.55, 1.4))   # Hermite tangents (rim, glyph, far rim) / segment slopes


def hex2rgb(h):
    h = h.lstrip('#'); return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def rgb2hex(c):
    return '#' + ''.join(f'{max(0, min(255, round(v))):02X}' for v in c)


def ramp(k):
    """k in [0, 2]: 0 = HI, 1 = MID, 2 = LO (straight lines in sRGB, as SVG interpolates)."""
    a, b, u = (HI, MID, k) if k <= 1 else (MID, LO, k - 1)
    a, b = hex2rgb(a), hex2rgb(b)
    return rgb2hex([a[i] + (b[i] - a[i]) * u for i in range(3)])


def hermite(t, t0, t1, k0, k1, m0, m1):
    h = t1 - t0; s = (t - t0) / h
    return ((2 * s**3 - 3 * s**2 + 1) * k0 + (s**3 - 2 * s**2 + s) * h * m0
            + (-2 * s**3 + 3 * s**2) * k1 + (s**3 - s**2) * h * m1)


def glyph_centre_y(cy, R, w):
    top = STEM_TOP * R + w / 2
    bot = R + w / 2
    return cy + OPT * (top - bot) / 2


def nearest_glyph(fx, fy, cx, gcy, R, w, margin):
    """Distance from (fx, fy) to the power glyph grown by `margin` (round caps, capsule stem)."""
    h = w / 2 + margin
    dx, dy = fx - cx, fy - gcy
    ang = math.degrees(math.atan2(dx, -dy))
    t = math.radians(GAP_DEG)
    caps = [(cx + R * math.sin(t), gcy - R * math.cos(t)), (cx - R * math.sin(t), gcy - R * math.cos(t))]
    if abs(ang) >= GAP_DEG:
        d_ring = abs(math.hypot(dx, dy) - R) - h
    else:
        d_ring = min(math.hypot(fx - x, fy - y) for x, y in caps) - h
    y1, y2 = gcy - STEM_TOP * R, gcy - STEM_BOT * R
    d_stem = math.hypot(fx - cx, fy - min(max(fy, y1), y2)) - h
    return min(d_ring, d_stem)


def light_focus(cx, cy, r):
    ux, uy = LIGHT_DIR; n = math.hypot(ux, uy)
    return cx + LIGHT_D * r * ux / n, cy + LIGHT_D * r * uy / n


def master_gradient(gid, cx, cy, scale):
    r = ORB_R * scale
    fx, fy = light_focus(cx, cy, r)
    gr = (LIGHT_D + 1) * r                               # t = 1 on the far rim
    t_rim = (LIGHT_D - 1) * r / gr
    gcy = glyph_centre_y(cy, RING_R * scale, STROKE * scale)
    t_g = nearest_glyph(fx, fy, cx, gcy, RING_R * scale, STROKE * scale, MARGIN * scale) / gr
    s1, s2 = 1 / (t_g - t_rim), 1 / (1 - t_g)
    m0, m1, m2 = EASE[0] * s1, EASE[1] * s2, EASE[2] * s2
    stops = []
    for i in range(6):                                   # rim -> glyph: HI -> MID, easing out
        t = t_rim + (t_g - t_rim) * i / 5
        stops.append((t, hermite(t, t_rim, t_g, 0, 1, m0, m1)))
    for i in range(1, 7):                                # glyph -> far rim: MID -> LO, easing in
        t = t_g + (1 - t_g) * i / 6
        stops.append((t, hermite(t, t_g, 1, 1, 2, m1, m2)))
    stops[5] = (t_g, 1.0)                                # exact: nothing lighter than MID past here
    sx = ''.join(f'<stop offset="{fmt(t, 4)}" stop-color="{ramp(min(2, max(0, k)))}"/>' for t, k in stops)
    return (f'<radialGradient id="{gid}" cx="{fmt(fx)}" cy="{fmt(fy)}" r="{fmt(gr)}" '
            f'gradientUnits="userSpaceOnUse">{sx}</radialGradient>'), dict(t_rim=t_rim, t_g=t_g, stops=stops)


def small_gradient(gid, cx, cy, r, k0=1.0, k1=1.75):
    """<= 32 px: flatter and darker. Lightest point is MID on the rim, so >= 3.12:1 everywhere."""
    fx, fy = light_focus(cx, cy, r)
    gr = (LIGHT_D + 1) * r
    t_rim = (LIGHT_D - 1) * r / gr
    return (f'<radialGradient id="{gid}" cx="{fmt(fx, 3)}" cy="{fmt(fy, 3)}" r="{fmt(gr, 3)}" '
            f'gradientUnits="userSpaceOnUse"><stop offset="{fmt(t_rim, 4)}" stop-color="{ramp(k0)}"/>'
            f'<stop offset="1" stop-color="{ramp(k1)}"/></radialGradient>')


def power_glyph(cx, cy, R, w, gap_deg, stem_top, stem_bot, nd=2):
    h = w / 2
    t = math.radians(gap_deg)
    s, c = math.sin(t), math.cos(t)
    f = lambda v: fmt(v, nd)
    ro, ri = R + h, R - h
    p1 = (cx + ro * s, cy - ro * c)
    p2 = (cx - ro * s, cy - ro * c)
    p3 = (cx - ri * s, cy - ri * c)
    p4 = (cx + ri * s, cy - ri * c)
    ring = (f"M{f(p1[0])} {f(p1[1])}"
            f"A{f(ro)} {f(ro)} 0 1 1 {f(p2[0])} {f(p2[1])}"
            f"A{f(h)} {f(h)} 0 0 1 {f(p3[0])} {f(p3[1])}"
            f"A{f(ri)} {f(ri)} 0 1 0 {f(p4[0])} {f(p4[1])}"
            f"A{f(h)} {f(h)} 0 0 1 {f(p1[0])} {f(p1[1])}Z")
    y1 = cy - stem_top * R
    y2 = cy - stem_bot * R
    stem = (f"M{f(cx - h)} {f(y1)}A{f(h)} {f(h)} 0 0 1 {f(cx + h)} {f(y1)}"
            f"V{f(y2)}A{f(h)} {f(h)} 0 0 1 {f(cx - h)} {f(y2)}Z")
    return ring + stem


def circle_d(cx, cy, r):
    f = fmt
    return (f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 0 {f(cx + r)} {f(cy)}"
            f"A{f(r)} {f(r)} 0 1 0 {f(cx - r)} {f(cy)}Z")


def mark_parts(ox, oy, scale, gid, style='master'):
    """(defs, orb, glyph) for the 256-box mark placed at (ox, oy) and scaled by `scale`."""
    cx, cy = ox + C * scale, oy + C * scale
    r = ORB_R * scale
    R, w = RING_R * scale, STROKE * scale
    gd = power_glyph(cx, glyph_centre_y(cy, R, w), R, w, GAP_DEG, STEM_TOP, STEM_BOT)
    if style == 'master':
        defs, _ = master_gradient(gid, cx, cy, scale)
        fill = f'url(#{gid})'
    else:
        defs, fill = '', MID
    return defs, f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" fill="{fill}"/>', gd


def svg(w, h, defs, body, title='Stowaway'):
    d = f'<defs>{defs}</defs>' if defs else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(w)} {fmt(h)}" '
            f'width="{fmt(w)}" height="{fmt(h)}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{d}{body}</svg>\n')


def write(path, text):
    with open(path, 'w') as fh:
        fh.write(text)


# ---------------- marks (256) ----------------
d, orb, gd = mark_parts(0, 0, 1.0, 'sw-orb')
write(os.path.join(OUT, 'mark.svg'), svg(256, 256, d, orb + f'<path d="{gd}" fill="{GLYPH}"/>'))
write(os.path.join(WORK, 'mark-orb.svg'), svg(256, 256, d, orb))
write(os.path.join(WORK, 'mark-glyph.svg'), svg(256, 256, '', f'<path d="{gd}" fill="{GLYPH}"/>'))
_, orb, gd = mark_parts(0, 0, 1.0, '', 'flat')
write(os.path.join(OUT, 'mark-flat.svg'), svg(256, 256, '', orb + f'<path d="{gd}" fill="{GLYPH}"/>'))
# one colour: the glyph is knocked out of the orb (single compound path, even-odd)
write(os.path.join(OUT, 'mark-mono.svg'),
      svg(256, 256, '', f'<path d="{circle_d(C, C, ORB_R)}{gd}" fill="{MONO}" fill-rule="evenodd"/>'))

# ---------------- pixel-hinted small marks ----------------
# 16 px: 2 px ring (outer r 5, inner r 3) centred on the pixel corner (8, 8) so its left, right and
#        bottom edges fall on whole pixels; 2 px stem on x 7-9, y 2-9, square ends.
# 32 px: 3 px ring and stem. An odd stroke can only be centred on a pixel centre, so the orb is
#        31 px (centre 15.5) and the glyph is exactly centred in it; stem on x 14-17, y 5-16.
# The ring opening is as close to the master's 31 deg as a >= 1 px gap beside the stem allows.
HINTED = {
    16: dict(orb=(8, 8, 8), ring_c=(8, 8), r_out=5, r_in=3, gap=P.get('gap16', 50), stem=(7, 9, 2, 9)),
    32: dict(orb=(15.5, 15.5, 15.5), ring_c=(15.5, 15.5), r_out=8.5, r_in=5.5, gap=P.get('gap32', 38),
             stem=(14, 17, 5, 16)),
}
hint_info = {}
for px, spec in HINTED.items():
    ocx, ocy, orr = spec['orb']
    defs = small_gradient(f'sw-orb-{px}', ocx, ocy, orr)
    orb = f'<circle cx="{fmt(ocx)}" cy="{fmt(ocy)}" r="{fmt(orr)}" fill="url(#sw-orb-{px})"/>'
    x1, x2, y1, y2 = spec['stem']
    gd = ring_path(*spec['ring_c'], spec['r_out'], spec['r_in'], spec['gap']) + stem_path(x1, x2, y1, y2)
    write(os.path.join(WORK, f'mark-{px}.svg'), svg(px, px, defs, orb + f'<path d="{gd}" fill="{GLYPH}"/>'))
    write(os.path.join(WORK, f'mark-{px}-orb.svg'), svg(px, px, defs, orb))
    write(os.path.join(WORK, f'mark-{px}-glyph.svg'), svg(px, px, '', f'<path d="{gd}" fill="{GLYPH}"/>'))
    hint_info[px] = dict(gap=spec['gap'], clearance_px=round(clearance(spec), 2))

# ---------------- lockup ----------------
FONT = os.path.expanduser('~/Library/Fonts/GeistMono-Medium.otf')
TRACK = -0.03
# optical kerning (em) applied before glyph index: 1 = t, 2 = o, 7 = y
KERN = {int(k): v for k, v in P.get('kern', {'1': -0.053, '2': -0.060, '7': -0.02}).items()}
S = 100.0                       # wordmark em size in lockup units
MARK_D = 1.0 * S
GAP = 0.29 * S

data = load(FONT, 'stowaway')
xh = data['xHeight'] / data['upm'] * S
VC = 0.5  # 0 = x-height middle, 1 = ink-extent middle
wm0, bb0 = wordmark(data, S, 0, 0, TRACK, KERN)
ink_mid = (bb0[1] + bb0[3]) / 2
x_mid = -xh / 2
mid = round((x_mid + VC * (ink_mid - x_mid)) * 20) / 20

s_lsb = data['glyphs'][0]['bbox'][0] / data['upm'] * S
text_x = MARK_D + GAP - s_lsb
_, bb = wordmark(data, S, text_x, 0, TRACK, KERN)
content_w = bb[2]
content_top = min(-MARK_D / 2 + mid, bb[1])
content_bot = max(MARK_D / 2 + mid, bb[3])
content_h = content_bot - content_top
W, H = 640, 160                 # unchanged from the concept: README header and the reel end card
snap = lambda v: round(v * 20) / 20
ox = snap((W - content_w) / 2)
oy = snap((H - content_h) / 2 - content_top)   # baseline y
scale = MARK_D / 256.0
for name, ink, gid in (('logo-light.svg', INK_LIGHT, 'sw-orb-l'), ('logo-dark.svg', INK_DARK, 'sw-orb-d')):
    md, orb, gd = mark_parts(ox, oy + mid - MARK_D / 2, scale, gid)
    wd, _ = wordmark(data, S, ox + text_x, oy, TRACK, KERN)
    body = orb + f'<path d="{gd}" fill="{GLYPH}"/><path d="{wd}" fill="{ink}"/>'
    write(os.path.join(OUT, name), svg(W, H, md, body))

_, ginfo = master_gradient('x', C, C, 1.0)
print(json.dumps({
    'lockup': {'W': W, 'H': H, 'content': [round(content_w, 2), round(content_h, 2)],
               'origin': [ox, oy], 'kern': KERN, 'font': data['name']},
    'master': {'ring_r': RING_R, 'stroke': STROKE, 'gap': GAP_DEG,
               'clearance': round(RING_R * math.sin(math.radians(GAP_DEG)) - STROKE, 2),
               't_rim': round(ginfo['t_rim'], 4), 't_glyph': round(ginfo['t_g'], 4),
               'stops': [(round(t, 4), ramp(min(2, max(0, k)))) for t, k in ginfo['stops']]},
    'hinted': hint_info}, indent=1))
