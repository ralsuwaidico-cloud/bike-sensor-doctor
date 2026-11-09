#!/usr/bin/env python3
"""Contact sheets of the LVGL renders (test/v3/out): one row per state, columns Standard / Focused / Large Text in
English and Arabic. Usage: contact_sheet.py <out-dir> <dest-dir>. Needs Pillow."""
import pathlib, sys
from PIL import Image, ImageDraw, ImageFont

STATES = {
    'face': ['face', 'face__phone-lost-battery-9', 'face__not-synced', 'face__charging'],
    'menu': ['menu', 'menu__scrolled-end', 'menu__during-workout'],
    'cockpit': ['cockpit', 'cockpit__push', 'cockpit__power-1999', 'cockpit__power-2500', 'cockpit__no-power', 'cockpit__hr-only', 'cockpit__no-sensors'],
    'cockpit_states': ['cockpit__phone-lost', 'cockpit__pause-pending', 'cockpit__paused', 'cockpit__paused-toast', 'cockpit__refused', 'cockpit__no-answer', 'cockpit__phone-lost-refused', 'cockpit__key2-first-press'],
}
COLS = [('std', 'en', 'Standard'), ('foc', 'en', 'Focused'), ('lt', 'en', 'Large Text'), ('std', 'ar', 'Standard AR'), ('foc', 'ar', 'Focused AR'), ('lt', 'ar', 'Large Text AR')]

def main(out, dest):
    out, dest = pathlib.Path(out), pathlib.Path(dest); dest.mkdir(parents=True, exist_ok=True)
    try: font = ImageFont.truetype('DejaVuSans.ttf', 13)
    except OSError: font = ImageFont.load_default()
    for name, rows in STATES.items():
        S = 200; W = 170 + len(COLS) * (S + 8); H = 28 + len(rows) * (S + 8)
        sheet = Image.new('RGB', (W, H), (245, 245, 242)); d = ImageDraw.Draw(sheet)
        for j, (_, _, title) in enumerate(COLS): d.text((170 + j * (S + 8) + 4, 6), title, fill=(30, 30, 30), font=font)
        for i, st in enumerate(rows):
            y = 28 + i * (S + 8); d.text((6, y + S // 2 - 8), st.replace('__', ' · ').replace('cockpit', 'cockpit'), fill=(30, 30, 30), font=font)
            for j, (den, lang, _) in enumerate(COLS):
                img = Image.open(out / f'{st}--{den}-{lang}.png').convert('RGB').resize((S, S), Image.LANCZOS)
                m = Image.new('L', (S, S), 0); ImageDraw.Draw(m).ellipse((0, 0, S - 1, S - 1), fill=255)
                bg = Image.new('RGB', (S, S), (32, 34, 38)); bg.paste(img, (0, 0), m); sheet.paste(bg, (170 + j * (S + 8), y))
        sheet.save(dest / f'renders_{name}.png', optimize=True)
    print('sheets written to', dest)

if __name__ == '__main__':
    main(*sys.argv[1:3])
