#!/usr/bin/env python3
"""Writes docs/design/CYCLIFT_APPROVED_SCREENS.md and .pdf from screens.py. No CI, no simulator: existing assets only."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from screens import SCREENS, UPDATED, CAPABILITY, INTEGRATION
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak, Table, TableStyle,
                                Image, KeepTogether)
from PIL import Image as PILImage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "design"); ASSETS = os.path.join(OUT, "assets")
STAGES = ["Approved design", "Implemented in code", "Compiled", "Simulator-verified", "Physically verified on iPhone"]

# ---------------------------------------------------------------- Markdown
FIVE = ["Approved design", "Implemented in code", "Compiled", "Simulator-verified", "Physically verified on iPhone"]
def summary_states(s):
    """One state per canonical stage for the summary table (a screen may list several simulator rounds in detail)."""
    d = {}
    for a, b, _ in s["stages"]:
        d.setdefault(a, b)
    out = []
    for k in FIVE:
        v = d.get(k, "—")
        if k == "Simulator-verified" and len([a for a, _, _ in s["stages"] if a.startswith("Simulator-verified")]) > 1:
            v += " (later rounds: see the screen's status table)"
        out.append(v)
    return out

def markdown():
    L = ["# Cyclift — Approved Screens Register", "",
         f"Last updated: {UPDATED} · Screens recorded: {len(SCREENS)}", "",
         "This is the cumulative record of every UI/UX decision the owner has approved. The latest explicitly approved "
         "decision for a screen is the source of truth. Older designs, provisional sketches, newer unapproved "
         "implementations and screenshots that merely passed a check never replace it. An earlier decision is never "
         "altered: a revision is added to the screen's history and the earlier one is kept as superseded.", "",
         "The five statuses below are separate facts and are never treated as interchangeable: "
         "**Approved design · Implemented in code · Compiled · Simulator-verified · Physically verified on iPhone.**", "",
         "The visual book is `CYCLIFT_APPROVED_SCREENS.pdf` in this folder; images are in `assets/`.", "",
         "## Approved product direction", "",
         "**Cyclift is a universal multisport athlete platform** (owner, 21 Nov 2026 — `decisions/2026-11-21_universal-multisport-product-direction.md`). "
         "Every catalogue activity is selectable and any can be the primary sport; goals follow the selected sports; every athlete completes onboarding, "
         "with a plan where planning exists and profile-only otherwise; nothing is fabricated and no cycling or strength programme is assigned silently.", "",
         "Five things are always distinguished, and a sport being selectable never means the rest exists:", "",
         "| Sport / discipline | Selectable in the UI | Profile and goal storage | Workout planning | Recording | AI Coach |", "|---|---|---|---|---|---|"]
    L += ["| " + " | ".join(r) + " |" for r in CAPABILITY]
    L += ["", "The goal categories for sports without a planner are PROVISIONAL until the owner reviews them.", "",
         "## Cross-screen integration requirements", "",
         "Decided by the owner; requirements, not implemented features. Each is taken up when its screen is reached in the sequential review.", "",
         "| ID | Screen | Decided | Requirement | State |", "|---|---|---|---|---|"]
    L += ["| " + " | ".join(r) + " |" for r in INTEGRATION]
    L += ["", "## Summary", "",
         "| # | ID | Screen | " + " | ".join(STAGES) + " |", "|---|---|---|" + "---|" * len(STAGES)]
    for s in SCREENS:
        L.append(f"| {s['number']} | {s['id']} | {s['name']} | " + " | ".join(summary_states(s)) + " |")
    for s in SCREENS:
        L += ["", "---", "", f"## Screen {s['number']} — {s['name']} ({s['id']})", "",
              f"- **Navigation location:** {s['location']}",
              f"- **Approval date:** {s['approved_on']}",
              f"- **Approval status:** {s['status']}",
              f"- **Original design reference and source:** {s['reference']}",
              f"- **Implementation commit:** {s['commits']}", "",
              "### Exact approved wording", ""]
        L += [f"- **{k}:** {v}" for k, v in s["wording"]]
        L += ["", "### Approved layout, visual elements and interactions", ""] + [f"- {x}" for x in s["design"]]
        L += ["", "### Mandatory functionality and dependencies", ""] + [f"- {x}" for x in s["mandatory"]]
        L += ["", "### Explicitly rejected alternatives", ""] + [f"- {x}" for x in s["rejected"]]
        L += ["", "### Status", "", "| Stage | State | Evidence |", "|---|---|---|"]
        L += [f"| {a} | {b} | {c} |" for a, b, c in s["stages"]]
        L += ["", f"- **Visual verification:** {s['visual_verification']}",
              f"- **Functional verification:** {s['functional_verification']}", "",
              "### Remaining work or limitations", ""] + [f"- {x}" for x in s["remaining"]]
        L += ["", "### Images", ""] + [f"- `assets/{f}` — {c}" for f, c in s["images"]]
        L += ["", "### Decision history", "", "| When | Decision | State |", "|---|---|---|"]
        L += [f"| {a} | {b} | {c} |" for a, b, c in s["history"]]
    open(os.path.join(OUT, "CYCLIFT_APPROVED_SCREENS.md"), "w").write("\n".join(L) + "\n")

# ---------------------------------------------------------------- PDF
F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Body", F + "DejaVuSans.ttf")); pdfmetrics.registerFont(TTFont("Bold", F + "DejaVuSans-Bold.ttf"))
INK = colors.HexColor("#14171C"); MUTE = colors.HexColor("#5A6270"); LINE = colors.HexColor("#D5DAE1")
GOOD = colors.HexColor("#1E6E3C"); WARN = colors.HexColor("#A1490F"); BAD = colors.HexColor("#A32424"); SOFT = colors.HexColor("#F3F5F8")
P = lambda name, **k: ParagraphStyle(name, fontName=k.pop("font", "Body"), textColor=k.pop("color", INK), alignment=TA_LEFT, **k)
H1 = P("h1", font="Bold", fontSize=20, leading=25, spaceAfter=4)
H2 = P("h2", font="Bold", fontSize=11, leading=14, spaceBefore=9, spaceAfter=3)
BODY = P("body", fontSize=8.6, leading=12)
SMALL = P("small", fontSize=7.6, leading=10.4, color=MUTE)
CELL = P("cell", fontSize=7.9, leading=10.6)
CELLB = P("cellb", font="Bold", fontSize=7.9, leading=10.6)
CAP = P("cap", fontSize=7.4, leading=9.8, color=MUTE)
CAPB = P("capb", font="Bold", fontSize=7.4, leading=9.8)
esc = lambda t: t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def state_color(v):
    u = v.upper()
    if u.startswith("NO") or "NOT YET" in u: return BAD if u.startswith("NO") else WARN
    if "WITH" in u: return WARN if "LIMITS" in u else GOOD
    return GOOD

def bullets(items): return [Paragraph("• " + esc(x), BODY) for x in items]

def stage_table(s, width):
    rows = [[Paragraph("Stage", CELLB), Paragraph("State", CELLB), Paragraph("Evidence", CELLB)]]
    for a, b, c in s["stages"]:
        rows.append([Paragraph(esc(a), CELLB), Paragraph(esc(b), ParagraphStyle("st", parent=CELLB, textColor=state_color(b))), Paragraph(esc(c), CELL)])
    t = Table(rows, colWidths=[32 * mm, 30 * mm, width - 62 * mm], repeatRows=1)
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
                           ("BACKGROUND", (0, 0), (-1, 0), SOFT), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                           ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return t

def picture(fname, max_w, max_h):
    p = os.path.join(ASSETS, fname); w, h = PILImage.open(p).size
    k = min(max_w / w, max_h / h); return Image(p, width=w * k, height=h * k)

def image_row(images, width, max_h):
    """Images side by side at one scale, captions underneath. The original pixels are embedded; nothing is redrawn."""
    n = len(images); gap = 6 * mm
    col = (width - gap * (n - 1)) / n if n > 1 else width * 0.55
    pics = [picture(f, col, max_h) for f, _ in images]
    caps = []
    for f, c in images:
        approved = c.startswith("APPROVED")
        cut = c.find(". ")                      # the label is the first sentence
        head, rest = (c[:cut + 1], c[cut + 2:]) if cut > 0 else (c, "")
        caps.append([Paragraph(esc(head), ParagraphStyle("ch", parent=CAPB, textColor=GOOD if approved else WARN)), Paragraph(esc(rest), CAP)])
    t = Table([pics, caps], colWidths=[col + (gap if i < n - 1 else 0) for i in range(n)], hAlign="LEFT")
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("ALIGN", (0, 0), (-1, 0), "LEFT"),
                           ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), gap), ("TOPPADDING", (0, 1), (-1, 1), 5)]))
    return t

def pdf():
    path = os.path.join(OUT, "CYCLIFT_APPROVED_SCREENS.pdf")
    W, H = A4; M = 16 * mm; width = W - 2 * M
    def chrome(c, d):
        c.saveState(); c.setFont("Body", 7.5); c.setFillColor(MUTE)
        c.drawString(M, 9 * mm, f"Cyclift — Approved Screens · design record, not a test report · updated {UPDATED}")
        c.drawRightString(W - M, 9 * mm, f"Page {d.page}"); c.setStrokeColor(LINE); c.line(M, 12.5 * mm, W - M, 12.5 * mm); c.restoreState()
    doc = BaseDocTemplate(path, pagesize=A4, leftMargin=M, rightMargin=M, topMargin=15 * mm, bottomMargin=17 * mm,
                          title="Cyclift — Approved Screens", author="Cyclift")
    doc.addPageTemplates([PageTemplate(id="p", frames=[Frame(M, 17 * mm, width, H - 32 * mm, id="f", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)], onPage=chrome)])
    S = [Paragraph("Cyclift — Approved Screens", H1),
         Paragraph(f"Cumulative visual approval book · {len(SCREENS)} screen(s) recorded · updated {UPDATED}", SMALL), Spacer(1, 5 * mm),
         Paragraph("How to read this book", H2),
         Paragraph("Each screen has the image of the design the owner approved, the approved wording and interactions, what must "
                   "keep working, and what is still outstanding. The latest explicitly approved decision is the source of truth.", BODY),
         Spacer(1, 2 * mm),
         Paragraph("Five separate statuses are shown for every screen. They are never interchangeable: a screen can be approved but "
                   "not built, or built and checked on the simulator but never seen on a real iPhone.", BODY),
         Spacer(1, 2 * mm),
         Paragraph("An image labelled APPROVED DESIGN is what the owner approved. An image labelled IMPLEMENTATION — NOT YET VISUALLY "
                   "VERIFIED is the current build, shown for information only; it does not replace the approved design.", BODY),
         Paragraph("Summary", H2)]
    head = [Paragraph(x, CELLB) for x in ["#", "Screen"] + STAGES]
    rows = [head]
    for s in SCREENS:
        rows.append([Paragraph(str(s["number"]), CELL), Paragraph(f"<b>{esc(s['name'])}</b><br/>{s['id']}", CELL)] +
                    [Paragraph(esc(v), ParagraphStyle("sv", parent=CELLB, textColor=state_color(v))) for v in summary_states(s)])
    cw = [8 * mm, 30 * mm] + [(width - 38 * mm) / 5] * 5
    t = Table(rows, colWidths=cw, repeatRows=1)
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BACKGROUND", (0, 0), (-1, 0), SOFT),
                           ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    S += [t, Spacer(1, 4 * mm),
          Paragraph("All checks so far ran in the iOS Simulator (iPhone 15 Pro, Obsidian). Nothing in this book has been verified on a physical iPhone.", SMALL),
          PageBreak(), Paragraph("Approved product direction", H1),
          Paragraph("<b>Cyclift is a universal multisport athlete platform</b> (owner, 21 Nov 2026). Every catalogue activity is selectable and any can be the primary "
                    "sport; goals follow the selected sports; every athlete completes onboarding — with a plan where planning exists, profile-only otherwise. Nothing "
                    "is fabricated, and no cycling or strength programme is assigned silently.", BODY), Spacer(1, 3 * mm),
          Paragraph("Five separate facts per sport. A sport being selectable never means the rest exists.", BODY), Spacer(1, 2 * mm)]
    crow = [[Paragraph(x, CELLB) for x in ["Sport / discipline", "Selectable in the UI", "Profile and goal storage", "Workout planning", "Recording", "AI Coach"]]]
    for r in CAPABILITY:
        crow.append([Paragraph(esc(r[0]), CELLB)] + [Paragraph(esc(v), ParagraphStyle("cv", parent=CELL, textColor=GOOD if v.startswith("Yes") else (WARN if v.startswith("As") else BAD))) for v in r[1:]])
    ct = Table(crow, colWidths=[42 * mm] + [(width - 42 * mm) / 5] * 5, repeatRows=1)
    ct.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BACKGROUND", (0, 0), (-1, 0), SOFT),
                            ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    S += [ct, Spacer(1, 3 * mm),
          Paragraph("\"Yes\" in the first two columns means implemented in code on the development branch; verification is recorded under Screens 3 and 4. "
                    "Goal categories for sports without a planner are provisional until the owner reviews them. Nothing here is in a TestFlight build.", SMALL),
          Spacer(1, 5 * mm), Paragraph("Cross-screen integration requirements", H2),
          Paragraph("Decided by the owner; requirements, not implemented features. Each is taken up when its screen is reached in the sequential review.", SMALL), Spacer(1, 2 * mm)]
    irow = [[Paragraph(x, CELLB) for x in ["ID", "Screen", "Decided", "Requirement", "State"]]]
    for r in INTEGRATION: irow.append([Paragraph(esc(v), CELL) for v in r])
    it = Table(irow, colWidths=[14 * mm, 24 * mm, 24 * mm, width - 102 * mm, 40 * mm], repeatRows=1)
    it.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BACKGROUND", (0, 0), (-1, 0), SOFT),
                            ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    S += [it]
    for s in SCREENS:
        S += [PageBreak(), Paragraph(f"Screen {s['number']} — {esc(s['name'])}", H1),
              Paragraph(f"{s['id']} · {esc(s['location'])}", SMALL), Spacer(1, 2 * mm),
              Paragraph(f"<b>Status:</b> {esc(s['status'])}", ParagraphStyle("stt", parent=BODY, textColor=GOOD if s['status'].startswith('APPROVED AND LOCKED') else WARN)),
              Paragraph(f"<b>Approved:</b> {esc(s['approved_on'])}", BODY), Spacer(1, 4 * mm),
              image_row(s["images"][:1], width, 190 * mm)]
        rest = s["images"][1:]
        approved_more = [x for x in rest if x[1].startswith("APPROVED")]
        other = [x for x in rest if not x[1].startswith("APPROVED")]
        for k in range(0, len(approved_more), 4):
            S += [PageBreak(), Paragraph(f"Screen {s['number']} — {esc(s['name'])} · approved states", H1), Spacer(1, 3 * mm),
                  image_row(approved_more[k:k + 4], width, 150 * mm)]
        if other:
            impl = any(x[1].startswith("IMPLEMENTATION") for x in other)
            S += [PageBreak(), Paragraph(f"Screen {s['number']} — {esc(s['name'])} · " + ("current implementation" if impl else "origin"), H1),
                  Paragraph("Shown for information. These screenshots are NOT the approved design and have not been visually verified by the owner." if impl
                            else "Shown for the record only. This is where the approved design came from; it is not the canonical design.",
                            ParagraphStyle("w", parent=BODY, textColor=WARN)), Spacer(1, 4 * mm),
                  image_row(other[:4], width, 150 * mm)]
        S += [PageBreak(), Paragraph(f"Screen {s['number']} — {esc(s['name'])} · record", H1),
              Paragraph(f"<b>Design reference:</b> {esc(s['reference'])}", BODY),
              Paragraph("Exact approved wording", H2)]
        wt = Table([[Paragraph(esc(k), CELLB), Paragraph(esc(v), CELL)] for k, v in s["wording"]], colWidths=[34 * mm, width - 34 * mm])
        wt.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("LEFTPADDING", (0, 0), (-1, -1), 4),
                                ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
        S += [wt, Paragraph("Approved layout, visual elements and interactions", H2)] + bullets(s["design"])
        S += [Paragraph("Mandatory functionality", H2)] + bullets(s["mandatory"])
        S += [Paragraph("Explicitly rejected", H2)] + bullets(s["rejected"])
        S += [Paragraph("Status — five separate facts", H2), stage_table(s, width), Spacer(1, 2 * mm),
              Paragraph(f"<b>Visual verification:</b> {esc(s['visual_verification'])}", BODY),
              Paragraph(f"<b>Functional verification:</b> {esc(s['functional_verification'])}", BODY),
              Paragraph(f"<b>Implementation:</b> {esc(s['commits'])}", BODY),
              Paragraph("Outstanding implementation and testing", H2)] + bullets(s["remaining"])
        hist = [[Paragraph(x, CELLB) for x in ["When", "Decision", "State"]]] + \
               [[Paragraph(esc(a), CELL), Paragraph(esc(b), CELL), Paragraph(esc(c), ParagraphStyle("hs", parent=CELLB, textColor=MUTE if c.startswith("SUPERSEDED") else GOOD))] for a, b, c in s["history"]]
        ht = Table(hist, colWidths=[30 * mm, width - 62 * mm, 32 * mm], repeatRows=1)
        ht.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE), ("BACKGROUND", (0, 0), (-1, 0), SOFT),
                                ("LEFTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
        S += [Paragraph("Decision history", H2), ht]
    doc.build(S)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True); markdown(); pdf(); print("written:", OUT)
