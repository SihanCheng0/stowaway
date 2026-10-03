# Stowaway logo

The Orb is a terracotta orb with a white power glyph, paired with a lowercase **stowaway** wordmark. The wordmark is set in [Geist Mono](https://github.com/vercel/geist-font) Medium (SIL OFL 1.1) and converted to outlines. The SVGs contain only paths and gradients: no `<text>`, no font files and no raster images.

| File | What it is |
|-|-|
| `logo-light.svg`, `logo-light.png` | Horizontal lockup for light backgrounds |
| `logo-dark.svg`, `logo-dark.png` | Horizontal lockup for dark backgrounds |
| `mark.svg` | The mark on its own (256 × 256 viewBox) |
| `mark-64.png` to `mark-1024.png` | `mark.svg` rendered at 64, 128, 512 and 1024 px |
| `mark-16.png`, `mark-32.png` | Small versions drawn on the pixel grid, with a flatter, darker orb. The 32 px orb is 31 px wide so its 3 px stem can sit exactly in the centre. |
| `mark-flat.svg` | One-colour fallback: flat #D97757 orb, white glyph |
| `mark-mono.svg` | Single colour #141110 with the glyph cut out, for print and embossing |
| `social-preview.png` | GitHub social preview, 1280 × 640 |

The lockup SVGs use a 640 × 160 canvas with clear space built in. The lockup PNGs are 1280 px wide with a transparent background.

## Usage

- **README header:** use a `<picture>` that serves `logo-dark.svg` for `prefers-color-scheme: dark` and `logo-light.svg` otherwise.
- **16 and 32 px** (favicons, small slots): use `mark-16.png` and `mark-32.png` rather than scaling `mark.svg` down. From 64 px up, use `mark.svg` or its renders.
- **Gradients not available:** use `mark-flat.svg`. For one-ink print, use `mark-mono.svg`.
- **Social preview:** upload `social-preview.png` in the repository's Settings → General → Social preview.

## Colours

| Part | Colour |
|-|-|
| Orb | #F0A07E → #D97757 → #B85A3E, radial |
| Glyph | #FFFFFF |
| Wordmark | #2B2421 on light, #F2EBE6 on dark |
| Mono | #141110 |

White on the orb behind the glyph is at least 3.1:1 at every size.

## Rebuild

`scripts/logo/render.sh` regenerates every file here from the geometry in `scripts/logo/build.py`. Its verification sheets go to `build/logo-work/`.
