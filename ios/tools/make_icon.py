#!/usr/bin/env python3
"""Generates the Cyclift app icon and launch mark. Original artwork, pure PIL, no external images or fonts, no text.

The mark: a white "C" drawn as a chainring (a thick ring open on the right, with teeth on its outer edge), a hub in
the middle, and a crank arm that runs out through the opening of the C and ends in two weight plates — a crank that is
also a small barbell (ride + lift). Background: the app's turquoise accent (Theme.swift BC.accent) as a soft vertical
gradient on a rounded square.

Writes: the 1024 masters for the iPhone and Apple Watch asset catalogs, the launch-screen mark (1x/2x/3x, white on
transparent), the Android launcher mipmaps and the Play / App Store 512 and 1024 listing icons.
Usage (from the repo root): python3 ios/tools/make_icon.py   [--preview out.png]
"""
import math
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ACCENT = (14, 158, 155)       # Theme.swift BC.accent (light): 0.055, 0.62, 0.608
ACCENT_HI = (52, 231, 228)    # BC.accent (dark): 0.204, 0.906, 0.894
WHITE = (255, 255, 255, 255)

# geometry in units of the canvas (0..1)
CX, CY = 0.45, 0.5            # centre of the ring (left of centre: the crank and plates fill the right side)
R_OUT, R_IN = 0.275, 0.18    # ring radii
GAP = 84                      # opening of the C, degrees, centred on 0° (pointing right)
TEETH = 11                    # teeth over the arc
TOOTH_H, TOOTH_W = 0.032, 0.05


def _ring(d, S, colour):
    """The C: an annular sector from GAP/2 to 360-GAP/2 degrees, with rounded ends and teeth."""
    cx, cy = CX * S, CY * S
    ro, ri = R_OUT * S, R_IN * S
    a0, a1 = GAP / 2, 360 - GAP / 2
    # PIL angles: 0° = 3 o'clock, clockwise. Draw the thick arc as a polygon for clean edges.
    pts = []
    steps = 240
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + ro * math.cos(a), cy + ro * math.sin(a)))
    for i in range(steps, -1, -1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + ri * math.cos(a), cy + ri * math.sin(a)))
    d.polygon(pts, fill=colour)
    # rounded ends
    rm, w = (ro + ri) / 2, (ro - ri) / 2
    for a in (a0, a1):
        t = math.radians(a)
        x, y = cx + rm * math.cos(t), cy + rm * math.sin(t)
        d.ellipse([x - w, y - w, x + w, y + w], fill=colour)
    # teeth: small rounded blocks standing on the outer edge, evenly spaced, kept clear of the rounded ends
    th, tw = TOOTH_H * S, TOOTH_W * S
    margin = 14
    for k in range(TEETH):
        a = a0 + margin + (a1 - a0 - 2 * margin) * k / (TEETH - 1)
        t = math.radians(a)
        ux, uy = math.cos(t), math.sin(t)          # radial
        vx, vy = -uy, ux                           # tangential
        base = ro - th * 0.3
        tip = ro + th
        half_b, half_t = tw / 2, tw * 0.34
        quad = [(cx + ux * base + vx * half_b, cy + uy * base + vy * half_b),
                (cx + ux * tip + vx * half_t, cy + uy * tip + vy * half_t),
                (cx + ux * tip - vx * half_t, cy + uy * tip - vy * half_t),
                (cx + ux * base - vx * half_b, cy + uy * base - vy * half_b)]
        d.polygon(quad, fill=colour)


def _crank_barbell(d, S, colour):
    """Hub + crank arm out through the C's opening, ending in two plates (a barbell end)."""
    cx, cy = CX * S, CY * S
    hub = 0.06 * S
    d.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=colour)
    bar_h = 0.046 * S
    x_end = 0.855 * S
    d.rounded_rectangle([cx, cy - bar_h / 2, x_end, cy + bar_h / 2], radius=int(bar_h / 2), fill=colour)
    # plates: a big one and a smaller outer one, inside the opening of the C
    p1x, p1w, p1h = 0.735 * S, 0.056 * S, 0.25 * S
    p2x, p2w, p2h = 0.805 * S, 0.044 * S, 0.17 * S
    d.rounded_rectangle([p1x - p1w / 2, cy - p1h / 2, p1x + p1w / 2, cy + p1h / 2], radius=int(p1w * 0.42), fill=colour)
    d.rounded_rectangle([p2x - p2w / 2, cy - p2h / 2, p2x + p2w / 2, cy + p2h / 2], radius=int(p2w * 0.42), fill=colour)


def _draw_mark(img, S, colour=WHITE):
    d = ImageDraw.Draw(img)
    _ring(d, S, colour)
    _crank_barbell(d, S, colour)


def master(size=1024, rounded=True, scale=4):
    S = size * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = Image.new("RGB", (1, S))
    for y in range(S):
        t = y / (S - 1)
        k = (1 - t) * 0.55
        bg.putpixel((0, y), tuple(int(ACCENT_HI[i] * k + ACCENT[i] * (1 - k)) for i in range(3)))
    bg = bg.resize((S, S))
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
    else:
        md.rectangle([0, 0, S - 1, S - 1], fill=255)
    img.paste(bg, (0, 0), mask)
    _draw_mark(img, S)
    return img.resize((size, size), Image.LANCZOS)


def mark_only(size=600, scale=4):
    """White mark on transparent, for the launch screen and the in-app CycliftMark view."""
    S = size * scale
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    _draw_mark(img, S)
    return img.resize((size, size), Image.LANCZOS)


def opaque(img):
    out = Image.new("RGB", img.size, ACCENT)
    out.paste(img, (0, 0), img)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--preview":
        sheet = Image.new("RGB", (1024 + 40 + 300 + 40 + 120, 1024), (240, 240, 240))
        sheet.paste(master(1024, rounded=True), (0, 0), master(1024, rounded=True))
        dark = Image.new("RGBA", (300, 300), (14, 158, 155, 255)); m = mark_only(300); dark.paste(m, (0, 0), m)
        sheet.paste(dark, (1064, 0))
        small = master(120, rounded=True); sheet.paste(small, (1404, 0), small)
        small2 = master(48, rounded=True); sheet.paste(small2, (1404, 140), small2)
        sheet.save(sys.argv[2]); print("preview", sys.argv[2]); sys.exit(0)
    # Apple asset catalogs take one 1024 master; it must be square and opaque (iOS applies its own mask)
    ios = opaque(master(1024, rounded=False))
    save(ios, os.path.join(ROOT, "ios/BikeComputer/Assets.xcassets/AppIcon.appiconset/icon.png"))
    save(ios, os.path.join(ROOT, "ios/BikeComputerWatch/Assets.xcassets/AppIcon.appiconset/icon.png"))
    save(ios, os.path.join(ROOT, "ios/store/app-icon-1024.png"))
    # launch screen mark (white on transparent) at 1x/2x/3x
    for n, px in (("LaunchMark.png", 200), ("LaunchMark@2x.png", 400), ("LaunchMark@3x.png", 600)):
        save(mark_only(px), os.path.join(ROOT, "ios/BikeComputer/Assets.xcassets/LaunchMark.imageset", n))
    # Android launcher icons (legacy mipmaps, rounded)
    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(master(px, rounded=True), os.path.join(ROOT, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher.png"))
    # Play Store listing icon (512, opaque)
    save(opaque(master(512, rounded=False)), os.path.join(ROOT, "android/store/ic_launcher-playstore.png"))
