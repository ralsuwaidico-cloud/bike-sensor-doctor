#!/usr/bin/env python3
"""Turn out/*.ppm into PNG previews (round mask like the real glass) and contact sheets.
usage: sheet.py OUTDIR [pattern ...]   -> OUTDIR/png/<name>.png and OUTDIR/sheet_*.png"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
pats = sys.argv[2:] or ["*"]
os.makedirs(os.path.join(out, "png"), exist_ok=True)
files = []
for p in pats:
    files += sorted(glob.glob(os.path.join(out, p + ".ppm")))
files = sorted(set(files))
S = 2
mask = Image.new("L", (240 * S, 240 * S), 0)
ImageDraw.Draw(mask).ellipse((0, 0, 240 * S - 1, 240 * S - 1), fill=255)
tiles = []
for f in files:
    name = os.path.splitext(os.path.basename(f))[0]
    im = Image.open(f).convert("RGB").resize((240 * S, 240 * S), Image.NEAREST)
    bez = Image.new("RGB", im.size, (40, 40, 44))
    bez.paste(im, (0, 0), mask)
    d = ImageDraw.Draw(bez)
    d.ellipse((0, 0, 240 * S - 1, 240 * S - 1), outline=(90, 90, 96), width=2)
    bez.save(os.path.join(out, "png", name + ".png"))
    tiles.append((name, bez))
if tiles:
    cols = 4
    per = 12
    for si in range(0, len(tiles), per):
        chunk = tiles[si:si + per]
        rows = (len(chunk) + cols - 1) // cols
        W, H = 240 * S + 20, 240 * S + 44
        sheet = Image.new("RGB", (cols * W, rows * H), (24, 24, 28))
        d = ImageDraw.Draw(sheet)
        for i, (n, im) in enumerate(chunk):
            x, y = (i % cols) * W + 10, (i // cols) * H + 34
            sheet.paste(im, (x, y))
            d.text((x, y - 26), n, fill=(230, 230, 230))
        sheet.save(os.path.join(out, "sheet_%02d.png" % (si // per)))
print(len(tiles), "previews")
