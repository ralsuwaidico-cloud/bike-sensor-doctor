#!/usr/bin/env bash
# Regenerates the Cyclift Watch v3 LVGL fonts (src/ui/v3/fonts/*.c) from the subset sources in fonts-src/.
# Needs node (npx lv_font_conv@1.5.2). The generated .c files are committed, so a normal firmware build does not need this.
# Sources: Inter 4.x (SIL OFL 1.1) with tabular figures frozen on (pyftfeatfreeze -f tnum), Noto Sans Arabic (SIL OFL 1.1).
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../src/ui/v3/fonts
CONV="${LV_FONT_CONV:-npx --yes lv_font_conv@1.5.2}"
LATIN="0x20-0x7E,0xA0,0xB0,0xB7,0xD7,0x2013,0x2014,0x2019,0x2026,0x2212"
DIGITS="0x20,0x2D,0x2E,0x30-0x3A,0x2014"
ARABIC="0x60C,0x61B,0x61F,0x621-0x652,0x660-0x66D,0x670,0xFE70-0xFE74,0xFE76-0xFEFC"   # Arabic letters, harakat, digits + Presentation Forms-B (LVGL shapes into these)
gen() { # name font size range [extra]
  $CONV --font "fonts-src/$2" -r "$4" --size "$3" --bpp 4 --format lvgl --lv-include lvgl.h ${5:-} -o "$OUT/$1.c" --force-fast-kern-format >/dev/null
  # descriptor stays writable: fonts.cpp links each Latin font to its Arabic fallback at start-up (glyph data stays in flash)
  sed -i "s/^const lv_font_t $1 = {/lv_font_t $1 = {/" "$OUT/$1.c"
  # compiled only into the v3 proof-of-concept build (the existing application build ignores these files)
  { echo "#if defined(CYW_V3POC)"; cat "$OUT/$1.c"; echo "#endif /* CYW_V3POC */"; } > "$OUT/$1.tmp" && mv "$OUT/$1.tmp" "$OUT/$1.c"
}
for s in 11 12 13 14 15 17; do gen cyv3_inter600_$s InterSB-tnum.otf $s "$LATIN"; done
for s in 11 12 13 15 20; do gen cyv3_inter500_$s InterM-tnum.otf $s "$LATIN"; done
for s in 24 32 44 54 58; do gen cyv3_digits_$s InterSB-tnum.otf $s "$DIGITS" --no-compress; done
for s in 11 12 13 14 15 17; do gen cyv3_noto600_$s NotoAr600.ttf $s "$ARABIC"; done
for s in 11 12 13; do gen cyv3_noto400_$s NotoAr400.ttf $s "$ARABIC"; done
echo "fonts written to $OUT"
