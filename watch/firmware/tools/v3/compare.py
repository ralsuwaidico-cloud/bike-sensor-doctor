#!/usr/bin/env python3
"""Side-by-side comparison of the LVGL renders (test/v3/out) with the approved prototype v3.1 screenshots.
Usage: compare.py <lvgl-out-dir> <prototype-shots-dir> <dest-dir>
Writes one sheet per group (prototype left, LVGL right) and comparison.json with a pixel difference per pair
(mean absolute difference of the 0–255 channels inside the round screen; 0 = identical). Needs Pillow."""
import json, pathlib, sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

PAIRS = [  # (LVGL state, prototype screenshot)
    ('face--std-en', 'face--obsidian-en-normal'), ('face__phone-lost-battery-9--std-en', 'face__phone-lost-battery-9--obsidian-en-normal'),
    ('face__not-synced--std-en', 'face--obsidian-en-empty'), ('face__charging--std-en', 'face__charging--obsidian-en-normal'),
    ('menu--std-en', 'menu--obsidian-en-normal'), ('menu__during-workout--std-en', 'menu__during-workout--obsidian-en-normal'),
    ('cockpit--std-en', 'ride-cockpit--obsidian-en-normal'), ('cockpit--foc-en', 'ride-cockpit__focused--obsidian-en-normal'),
    ('cockpit__power-1999--std-en', 'ride-cockpit--obsidian-en-max'), ('cockpit__no-sensors--std-en', 'ride-cockpit--obsidian-en-unavail'),
    ('cockpit__phone-lost--std-en', 'ride-cockpit__phone-lost--obsidian-en-normal'), ('cockpit__pause-pending--std-en', 'ride-cockpit__pause-pending--obsidian-en-normal'),
    ('cockpit__no-answer--std-en', 'ride-cockpit__refused--obsidian-en-normal'), ('cockpit__key2-first-press--std-en', 'ride-cockpit__Key-2-first-press--obsidian-en-normal'),
    ('face--lt-en', 'LT__face--en'), ('menu--lt-en', 'LT__menu--en'), ('cockpit--lt-en', 'LT__ride-cockpit--en'),
    ('face--std-ar', 'face--obsidian-ar-normal'), ('menu--std-ar', 'menu--obsidian-ar-normal'), ('cockpit--std-ar', 'ride-cockpit--obsidian-ar-normal'),
    ('cockpit--foc-ar', 'ride-cockpit__focused--obsidian-ar-normal'), ('face--lt-ar', 'LT__face--ar'), ('menu--lt-ar', 'LT__menu--ar'), ('cockpit--lt-ar', 'LT__ride-cockpit--ar'),
]
GROUPS = [('compare_en_standard_focused', PAIRS[:14]), ('compare_large_text', PAIRS[14:17]), ('compare_arabic', PAIRS[17:])]

def masked(img):
    img = img.convert('RGB').resize((240, 240), Image.LANCZOS)
    m = Image.new('L', (240, 240), 0); ImageDraw.Draw(m).ellipse((0, 0, 239, 239), fill=255)
    bg = Image.new('RGB', (240, 240), (32, 34, 38)); bg.paste(img, (0, 0), m); return bg, m

def main(out, shots, dest):
    out, shots, dest = map(pathlib.Path, (out, shots, dest)); dest.mkdir(parents=True, exist_ok=True)
    try: font = ImageFont.truetype('DejaVuSans.ttf', 12)
    except OSError: font = ImageFont.load_default()
    result = {}
    for name, pairs in GROUPS:
        cols = 4; rows = (len(pairs) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * 500, rows * 270), (245, 245, 242)); d = ImageDraw.Draw(sheet)
        for i, (mine, proto) in enumerate(pairs):
            a, m = masked(Image.open(shots / f'{proto}.png')); b, _ = masked(Image.open(out / f'{mine}.png'))
            diff = ImageChops.difference(a, b); px = [p for p, k in zip(diff.getdata(), m.getdata()) if k]
            score = sum(sum(p) for p in px) / (3 * len(px)); result[mine] = {'prototype': proto, 'mean_abs_diff': round(score, 2)}
            x, y = (i % cols) * 500, (i // cols) * 270
            sheet.paste(a, (x + 6, y + 6)); sheet.paste(b, (x + 252, y + 6))
            d.text((x + 8, y + 250), f'prototype v3.1  |  LVGL  ·  {mine}  ·  diff {score:.1f}', fill=(40, 40, 40), font=font)
        sheet.save(dest / f'{name}.png', optimize=True)
    (dest / 'comparison.json').write_text(json.dumps(result, indent=1))
    print('compared', len(result), 'pairs; mean difference', round(sum(v['mean_abs_diff'] for v in result.values()) / len(result), 2))

if __name__ == '__main__':
    main(*sys.argv[1:4])
