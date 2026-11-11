#!/usr/bin/env python3
"""WCAG 2.1 contrast check for the Cyclift UI Lab theme tokens.

Parses CycliftUILab/DesignSystem/Theme.swift (between TOKENS-BEGIN / TOKENS-END) and checks:
  text tokens on background, surface and surface2            >= 4.5 (tertiary: >= 4.5 too)
  accent, category, status and ring colours on the surfaces  >= 3.0 (graphics / large text, WCAG 1.4.11)
  accent used as text on surface                             >= 4.5
  textOnAccent on accent (primary button label)              >= 4.5
  border against background (control boundary)               reported (>= 3.0 required only for High Contrast)
Exit code 1 when any required pair fails.
"""
import re, sys, pathlib

src = pathlib.Path(__file__).resolve().parents[1] / "CycliftUILab/DesignSystem/Theme.swift"
text = src.read_text().split("TOKENS-BEGIN")[1].split("TOKENS-END")[0]

def lum(h):
    def c(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * c((h >> 16) & 255) + 0.7152 * c((h >> 8) & 255) + 0.0722 * c(h & 255)

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

themes = {}
for m in re.finditer(r"static let (\w+) = CyTheme\((.*?)\)\n", text, re.S):
    themes[m.group(1)] = {k: int(v, 16) for k, v in re.findall(r"(\w+): Color\(hex: 0x([0-9A-Fa-f]{6})\)", m.group(2))}

fails, rows = 0, []
for name, t in themes.items():
    surfaces = ["background", "surface", "surface2"]
    def need(fg, bg, minimum, label=None):
        global fails
        r = ratio(t[fg], t[bg])
        ok = r >= minimum
        if not ok: fails += 1
        rows.append((name, label or fg, bg, r, minimum, ok))
    for s in surfaces:
        for fg in ["textPrimary", "textSecondary", "textTertiary"]: need(fg, s, 4.5)
        for fg in ["endurance", "strength", "recovery", "success", "warning", "danger",
                   "ringConsistency", "ringLoad", "ringRecovery", "accent"]: need(fg, s, 3.0)
    need("accent", "surface", 4.5, "accent as text")
    need("accent", "background", 4.5, "accent as text")
    need("textOnAccent", "accent", 4.5)
    for fg in ["success", "warning", "danger", "endurance", "strength", "recovery"]:
        need(fg, "surface", 4.5, fg + " as text")
    r = ratio(t["border"], t["background"])
    req = 3.0 if name == "highContrast" else 0
    ok = r >= req
    if not ok: fails += 1
    rows.append((name, "border", "background", r, req, ok))

print(f"{'theme':13} {'token':22} {'on':11} ratio  min  result")
for n, fg, bg, r, mn, ok in rows:
    if not ok or "--all" in sys.argv:
        print(f"{n:13} {fg:22} {bg:11} {r:5.2f}  {mn:3}  {'ok' if ok else 'FAIL'}")
worst = min((r for *_, r, mn, ok in rows if mn >= 4.5), default=0)
print(f"themes: {len(themes)} · pairs checked: {len(rows)} · failures: {fails} · lowest text-level ratio: {worst:.2f}")
sys.exit(1 if fails else 0)
