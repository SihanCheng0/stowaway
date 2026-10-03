#!/bin/zsh
# Rebuilds the logo set into assets/logo and the verification sheets into build/logo-work.
# Needs: xcrun swiftc, rsvg-convert (Homebrew librsvg), Geist Mono in ~/Library/Fonts,
#        and a python with numpy + pillow in $PY (only measure.py needs them; skipped without).
set -e
S="${0:A:h}"; ROOT="${S:h:h}"; O="$ROOT/assets/logo"; K="$ROOT/build/logo-work"
PY="${PY:-python3}"
mkdir -p "$O" "$K"
xcrun swiftc -O "$S/glyphs.swift" -o "$S/glyphs"
xcrun swiftc -O "$S/sheet.swift" -o "$K/sheet"
xcrun swiftc -O "$S/social.swift" -o "$K/social"
"$S/glyphs" ~/Library/Fonts/GeistMono-Medium.otf stowaway > "$K/glyphs.json"
$PY "$S/build.py" "{\"out\": \"$O\", \"work\": \"$K\"}" > "$K/build.json"

# marks: 16 and 32 come from their own pixel-hinted sources, the rest from mark.svg
rsvg-convert -w 16 -h 16 "$K/mark-16.svg" -o "$O/mark-16.png"
rsvg-convert -w 32 -h 32 "$K/mark-32.svg" -o "$O/mark-32.png"
for s in 64 128 512 1024; do rsvg-convert -w $s -h $s "$O/mark.svg" -o "$O/mark-$s.png"; done

# lockups, transparent
for v in light dark; do
  rsvg-convert -w 1280 "$O/logo-$v.svg" -o "$O/logo-$v.png"
  rsvg-convert -w 420 "$O/logo-$v.svg" -o "$K/logo-$v-420.png"
done

# social preview
rsvg-convert -w 800 "$O/logo-dark.svg" -o "$K/social-lockup.png"
"$K/social" "$K/social-lockup.png" "$O/social-preview.png" > "$K/social.json"

# measurement layers: orb only / glyph only at every size
for s in 64 128 512 1024; do
  rsvg-convert -w $s -h $s "$K/mark-orb.svg" -o "$K/orb-$s.png"
  rsvg-convert -w $s -h $s "$K/mark-glyph.svg" -o "$K/glyph-$s.png"
done
for s in 16 32; do
  rsvg-convert -w $s -h $s "$K/mark-$s-orb.svg" -o "$K/orb-$s.png"
  rsvg-convert -w $s -h $s "$K/mark-$s-glyph.svg" -o "$K/glyph-$s.png"
done
if $PY -c 'import numpy, PIL' 2>/dev/null; then
  LOGO_WORK="$K" $PY "$S/measure.py" > "$K/measure.json"
else
  echo "skipping contrast measurements: $PY has no numpy/pillow"
fi

# verification sheets
"$K/sheet" marks "$O" "$K/marks-sheet.png"
"$K/sheet" logos "$O" "$K" "$K/logos-sheet.png"
rm -f "$S/glyphs"
echo "done: $O"
