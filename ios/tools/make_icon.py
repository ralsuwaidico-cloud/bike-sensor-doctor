#!/usr/bin/env python3
"""Generates the Athletics app icon (original mark: turquoise rounded square, white geometric "A" built from a chevron
and a bar with a pulse). Writes the 1024 masters for the iPhone and Watch asset catalogs and the Android launcher
mipmaps. Pure PIL, no external artwork.   Usage: python3 ios/tools/make_icon.py  (from the repo root)"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ACCENT = (14, 158, 155)       # Theme.swift BC.accent (light): 0.055, 0.62, 0.608
ACCENT_HI = (52, 231, 228)    # BC.accent (dark): 0.204, 0.906, 0.894
WHITE = (255, 255, 255)


def master(size=1024, rounded=True, scale=4):
    S = size * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # vertical gradient background
    bg = Image.new("RGB", (S, S), ACCENT)
    px = bg.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(ACCENT_HI[i] * (1 - t) * 0.55 + ACCENT[i] * (1 - (1 - t) * 0.55)) for i in range(3))
        for x in range(S):
            px[x, y] = c
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
    else:
        md.rectangle([0, 0, S - 1, S - 1], fill=255)
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    w = int(S * 0.095)                       # stroke width
    # chevron (the "A")
    apex = (S * 0.5, S * 0.235)
    left = (S * 0.21, S * 0.70)
    right = (S * 0.79, S * 0.70)
    d.line([left, apex, right], fill=WHITE, width=w, joint="curve")
    for p in (apex, left, right):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=WHITE)
    # the bar of the A, drawn as a road / pulse line: flat, one beat, flat
    y = S * 0.56
    pts = [(S * 0.345, y), (S * 0.445, y), (S * 0.475, y - S * 0.055), (S * 0.505, y + S * 0.055), (S * 0.535, y), (S * 0.655, y)]
    d.line(pts, fill=WHITE, width=int(w * 0.72), joint="curve")
    for p in (pts[0], pts[-1]):
        r = w * 0.36
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE)
    # ground line under the A, hinting the road
    gy = S * 0.80
    d.rounded_rectangle([S * 0.26, gy - w * 0.22, S * 0.74, gy + w * 0.22], radius=int(w * 0.22), fill=(255, 255, 255, 200))
    return img.resize((size, size), Image.LANCZOS)


def mark_only(size=600, scale=4):
    """White mark on transparent, for the launch screen and in-app wordmark."""
    S = size * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = int(S * 0.095)
    apex = (S * 0.5, S * 0.235); left = (S * 0.21, S * 0.70); right = (S * 0.79, S * 0.70)
    d.line([left, apex, right], fill=WHITE, width=w, joint="curve")
    for p in (apex, left, right):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=WHITE)
    y = S * 0.56
    pts = [(S * 0.345, y), (S * 0.445, y), (S * 0.475, y - S * 0.055), (S * 0.505, y + S * 0.055), (S * 0.535, y), (S * 0.655, y)]
    d.line(pts, fill=WHITE, width=int(w * 0.72), joint="curve")
    for p in (pts[0], pts[-1]):
        r = w * 0.36
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE)
    gy = S * 0.80
    d.rounded_rectangle([S * 0.26, gy - w * 0.22, S * 0.74, gy + w * 0.22], radius=int(w * 0.22), fill=(255, 255, 255, 200))
    return img.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    # Apple asset catalogs take one 1024 master (no alpha for the App Store: flatten on white-free background)
    ios = master(1024, rounded=False)         # iOS applies its own mask; the file must be square and opaque
    ios_rgb = Image.new("RGB", ios.size, ACCENT); ios_rgb.paste(ios, (0, 0), ios)
    save(ios_rgb, os.path.join(ROOT, "ios/BikeComputer/Assets.xcassets/AppIcon.appiconset/icon.png"))
    save(ios_rgb, os.path.join(ROOT, "ios/BikeComputerWatch/Assets.xcassets/AppIcon.appiconset/icon.png"))
    # launch screen mark (white on transparent) at 1x/2x/3x
    for n, px in (("LaunchMark.png", 200), ("LaunchMark@2x.png", 400), ("LaunchMark@3x.png", 600)):
        save(mark_only(px), os.path.join(ROOT, "ios/BikeComputer/Assets.xcassets/LaunchMark.imageset", n))
    # Android launcher icons (legacy mipmaps, rounded)
    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(master(px, rounded=True), os.path.join(ROOT, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher.png"))
    # Play Store listing icon (512, opaque)
    play = master(512, rounded=False); play_rgb = Image.new("RGB", play.size, ACCENT); play_rgb.paste(play, (0, 0), play)
    save(play_rgb, os.path.join(ROOT, "android/store/ic_launcher-playstore.png"))
