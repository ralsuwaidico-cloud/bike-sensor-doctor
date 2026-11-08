#pragma once
// Cyclift Watch OS — round-screen layout engine (owner requirement 8 Nov 15:14, §1).
//
// The display is a 240 × 240 circle. Nothing may cross the visible circular boundary, labels may not overlap, text may
// not be silently clipped, and touch targets must stay inside the usable area. This engine is pure C++ (host-tested):
// it computes the usable chord at every height, measures text with a pluggable `TextMeasurer` (LVGL on the device, a
// conservative font table on the host), fits text by rules (minimum size, maximum lines, never "make everything tiny"),
// and emits a scene of rectangles / texts / arcs that the LVGL layer and the host renderer draw identically. Every
// element carries its bounds so `layout_checks.hpp` can prove the rules.
#include <cstdint>
#include <string>
#include <vector>
#include <cmath>
#include <algorithm>
#include <optional>

namespace cyw::ui {

constexpr float SCREEN = 240.f, RADIUS = 120.f, CX = 120.f, CY = 120.f;
constexpr float EDGE_INSET = 6.f;              // the bezel hides ~4–6 px of the panel; nothing lives there
constexpr float MIN_TOUCH = 44.f;              // minimum touch target (both dimensions)
// Minimum sizes per component (owner §1: establish minimums, never shrink everything): lead numbers 20, complication
// values 12, body 13, labels/units 11, button labels 12.
constexpr float MIN_FONT_BODY = 13.f, MIN_FONT_LABEL = 11.f, MIN_FONT_NUMBER = 20.f, MIN_FONT_COMP = 12.f, MIN_FONT_BUTTON = 12.f;

struct Rect { float x, y, w, h; float right() const { return x + w; } float bottom() const { return y + h; } float cx() const { return x + w / 2; } float cy() const { return y + h / 2; }
    bool intersects(const Rect& o) const { return x < o.right() && o.x < right() && y < o.bottom() && o.y < bottom(); } };

/// Half-width of the usable chord at height y (distance from the centre line), after the edge inset.
inline float halfChord(float y) {
    float r = RADIUS - EDGE_INSET, dy = y - CY;
    if (std::fabs(dy) >= r) return 0.f;
    return std::sqrt(r * r - dy * dy);
}
/// The widest rectangle of height h whose every corner is inside the usable circle, centred horizontally at y.
inline Rect bandAt(float y, float h, float sidePad = 0.f) {
    float top = y, bottom = y + h;
    float hw = std::min(halfChord(top), halfChord(bottom)) - sidePad;
    if (hw < 0) hw = 0;
    return {CX - hw, top, 2 * hw, h};
}
/// True when all four corners (and the mid-edges) of r are inside the usable circle.
inline bool insideCircle(const Rect& r) {
    float rr = (RADIUS - EDGE_INSET) * (RADIUS - EDGE_INSET);
    auto in = [&](float x, float y) { return (x - CX) * (x - CX) + (y - CY) * (y - CY) <= rr + 0.01f; };
    return in(r.x, r.y) && in(r.right(), r.y) && in(r.x, r.bottom()) && in(r.right(), r.bottom()) && in(r.cx(), r.y) && in(r.cx(), r.bottom());
}

// ---------------------------------------------------------------- text measurement
struct TextMeasurer {
    virtual float width(const std::string& s, float fontPx, bool bold) const = 0;
    virtual float lineHeight(float fontPx) const { return fontPx * 1.2f; }
    virtual ~TextMeasurer() = default;
};
/// Host measurer: conservative per-class advance widths for a Montserrat-like sans (digits are tabular on the watch).
struct HostMeasurer : TextMeasurer {
    float width(const std::string& s, float fontPx, bool bold) const override {
        float w = 0; float k = bold ? 1.06f : 1.f;
        for (unsigned char c : s) {
            if (c >= 0x80) { if ((c & 0xC0) == 0x80) continue; w += 0.70f * fontPx; continue; }   // multi-byte: count once, wide
            if (c >= '0' && c <= '9') w += 0.62f * fontPx;
            else if (c >= 'A' && c <= 'Z') w += 0.68f * fontPx;
            else if (c == ' ') w += 0.28f * fontPx;
            else if (c == 'i' || c == 'l' || c == 'j' || c == 't' || c == 'f' || c == '.' || c == ',' || c == ':' || c == '\'' || c == '|') w += 0.30f * fontPx;
            else if (c == 'm' || c == 'w' || c == 'M' || c == 'W') w += 0.85f * fontPx;
            else w += 0.56f * fontPx;
        }
        return w * k;
    }
};

// ---------------------------------------------------------------- scene elements
enum class Kind : uint8_t { Rect, Text, Arc, Circle, Polyline, Marker };
enum class Role : uint8_t { Decor, Label, Value, Comp, Unit, Body, Button, Icon, Indicator };
struct Element {
    Kind kind; Role role; Rect r;
    std::string text; float font = 0; bool bold = false; std::string color = "text"; std::string fill;   // token names, resolved by the theme
    int lines = 1; bool critical = false; bool truncated = false; std::string id;
    std::vector<std::string> fitLines;   // the exact lines the fitter chose (ellipsis included), drawn verbatim
    float a0 = 0, a1 = 0, stroke = 0;   // arcs
    std::vector<std::optional<std::pair<float, float>>> pts;   // polylines (nullopt = gap → the line breaks)
    float rot = 0;                       // marker heading in degrees
};
struct Scene { std::string name; std::vector<Element> els; bool needsMore = false; std::string moreReason; };

// ---------------------------------------------------------------- text fitting
struct FitSpec { float fontPx; float minFontPx; int maxLines; bool allowEllipsis; };

/// Word-wraps `s` into at most `maxLines` lines of width ≤ `maxW` at `fontPx`; returns false if it does not fit.
inline bool wrap(const TextMeasurer& m, const std::string& s, float fontPx, bool bold, float maxW, int maxLines, std::vector<std::string>& out) {
    out.clear(); std::string line; size_t i = 0;
    auto flush = [&]() { if (!line.empty()) { out.push_back(line); line.clear(); } };
    while (i < s.size()) {
        size_t j = s.find(' ', i); if (j == std::string::npos) j = s.size();
        std::string word = s.substr(i, j - i); i = j + 1;
        if (m.width(word, fontPx, bold) > maxW) return false;            // a single word wider than the box never fits
        std::string cand = line.empty() ? word : line + " " + word;
        if (m.width(cand, fontPx, bold) <= maxW) line = cand; else { flush(); line = word; }
        if ((int)out.size() > maxLines) return false;
    }
    flush();
    return (int)out.size() <= maxLines && !out.empty();
}

/// Fit text into a box: try the preferred size, step down by 1 px to the minimum, add lines up to maxLines. Returns the
/// chosen font and lines; `fits` false means the caller must page / open a detail screen / show "More" — never shrink
/// below the minimum, never clip silently (ellipsis only where the spec allows it, and it is flagged `truncated`).
struct Fitted { bool fits; float font; std::vector<std::string> lines; bool truncated; };
inline Fitted fitText(const TextMeasurer& m, const std::string& s, const FitSpec& spec, bool bold, float maxW, float maxH) {
    for (float f = spec.fontPx; f >= spec.minFontPx - 0.01f; f -= 1.f) {
        for (int n = 1; n <= spec.maxLines; n++) {
            if (n * m.lineHeight(f) > maxH + 0.01f) break;
            std::vector<std::string> lines;
            if (wrap(m, s, f, bold, maxW, n, lines)) return {true, f, lines, false};
        }
    }
    if (spec.allowEllipsis) {                       // last resort for non-critical text only
        float f = spec.minFontPx; std::string t = s;
        while (!t.empty() && m.width(t + "…", f, bold) > maxW) t.pop_back();
        while (!t.empty() && t.back() == ' ') t.pop_back();
        return {!t.empty(), f, {t + "…"}, true};
    }
    return {false, spec.minFontPx, {}, false};
}

// ---------------------------------------------------------------- components (reusable, all circle-aware)
struct Theme { std::string name; bool dark; };

class Builder {
public:
    Builder(Scene& s, const TextMeasurer& m) : s_(s), m_(m) {}

    /// Text centred in a band at y; returns the bounding rect (empty when it did not fit and no fallback was allowed).
    Rect text(const std::string& txt, float y, const FitSpec& spec, Role role, bool bold, const std::string& color = "text", float sidePad = 6.f, bool critical = false, const std::string& id = "") {
        float h = spec.maxLines * m_.lineHeight(spec.fontPx);
        Rect band = bandAt(y, h, sidePad);
        Fitted f = fitText(m_, txt, spec, bold, band.w, h);
        if (!f.fits) { s_.needsMore = true; s_.moreReason += (s_.moreReason.empty() ? "" : "; ") + ("'" + txt + "' does not fit at ≥ " + std::to_string(int(spec.minFontPx)) + " px"); return {0, 0, 0, 0}; }
        float lh = m_.lineHeight(f.font); float maxw = 0; for (auto& l : f.lines) maxw = std::max(maxw, m_.width(l, f.font, bold));
        Rect r{CX - maxw / 2, y, maxw, lh * f.lines.size()};
        Element e{Kind::Text, role, r}; e.text = txt; e.font = f.font; e.bold = bold; e.color = color; e.lines = int(f.lines.size()); e.critical = critical; e.truncated = f.truncated; e.id = id; e.fitLines = f.lines;
        s_.els.push_back(e); return r;
    }
    /// Left-aligned text inside an explicit box (for list rows / tiles).
    Rect textIn(const std::string& txt, const Rect& box, const FitSpec& spec, Role role, bool bold, const std::string& color = "text", bool critical = false, const std::string& id = "") {
        Fitted f = fitText(m_, txt, spec, bold, box.w, box.h);
        if (!f.fits) { s_.needsMore = true; s_.moreReason += (s_.moreReason.empty() ? "" : "; ") + ("'" + txt + "' does not fit its box"); return {0, 0, 0, 0}; }
        float lh = m_.lineHeight(f.font); float maxw = 0; for (auto& l : f.lines) maxw = std::max(maxw, m_.width(l, f.font, bold));
        Rect r{box.x, box.y, std::min(maxw, box.w), lh * f.lines.size()};
        Element e{Kind::Text, role, r}; e.text = txt; e.font = f.font; e.bold = bold; e.color = color; e.lines = int(f.lines.size()); e.critical = critical; e.truncated = f.truncated; e.id = id; e.fitLines = f.lines;
        s_.els.push_back(e); return r;
    }
    /// A metric: big number + unit on one baseline + label above, centred at y. Numbers never shrink below MIN_FONT_NUMBER.
    Rect metric(const std::string& label, const std::string& value, const std::string& unit, float y, float valueFont, const std::string& valueColor = "text", const std::string& id = "") {
        Rect l = text(label, y, {11, MIN_FONT_LABEL, 1, false}, Role::Label, true, "mut", 12);
        float vy = l.bottom() + 2;
        float vf = valueFont; float lh = m_.lineHeight(vf);
        float vw = m_.width(value, vf, true), uw = unit.empty() ? 0 : m_.width(unit, std::max(MIN_FONT_LABEL, vf * 0.35f), false) + 4;
        Rect band = bandAt(vy, lh, 10);
        while (vw + uw > band.w && vf > MIN_FONT_NUMBER) { vf -= 1; lh = m_.lineHeight(vf); vw = m_.width(value, vf, true); uw = unit.empty() ? 0 : m_.width(unit, std::max(MIN_FONT_LABEL, vf * 0.35f), false) + 4; band = bandAt(vy, lh, 10); }
        if (vw + uw > band.w) { s_.needsMore = true; s_.moreReason += "; value '" + value + "' too wide"; return {0, 0, 0, 0}; }
        float x0 = CX - (vw + uw) / 2;
        Element v{Kind::Text, Role::Value, {x0, vy, vw, lh}}; v.text = value; v.font = vf; v.bold = true; v.color = valueColor; v.id = id; s_.els.push_back(v);
        if (!unit.empty()) { float uf = std::max(MIN_FONT_LABEL, vf * 0.35f); Element u{Kind::Text, Role::Unit, {x0 + vw + 4, vy + lh - m_.lineHeight(uf) - 2, uw - 4, m_.lineHeight(uf)}}; u.text = unit; u.font = uf; u.color = "mut"; s_.els.push_back(u); }
        return {x0, l.y, vw + uw, vy + lh - l.y};
    }
    /// A pill button centred at (cx, y) with a minimum 44-pt touch size; label fitted inside; critical = must always be visible.
    Rect button(const std::string& label, float cx, float y, float w, const std::string& fill, const std::string& textColor, bool critical, const std::string& id) {
        float h = MIN_TOUCH; w = std::max(w, MIN_TOUCH);
        Rect r{cx - w / 2, y, w, h};
        Element b{Kind::Rect, Role::Button, r}; b.fill = fill; b.critical = critical; b.id = id; s_.els.push_back(b);
        Fitted f = fitText(m_, label, {14, 12, 1, false}, true, w - 16, h);
        if (!f.fits) { s_.needsMore = true; s_.moreReason += "; button '" + label + "' label too long"; }
        else { float tw = m_.width(f.lines[0], f.font, true), lh = m_.lineHeight(f.font); Element t{Kind::Text, Role::Button, {cx - tw / 2, y + (h - lh) / 2, tw, lh}}; t.text = f.lines[0]; t.font = f.font; t.bold = true; t.color = textColor; t.critical = critical; t.id = id + ".label"; s_.els.push_back(t); }
        return r;
    }
    /// First candidate that fits (owner §1: drop the least important part instead of shrinking everything).
    Rect textFirstFit(const std::vector<std::string>& candidates, float y, const FitSpec& spec, Role role, bool bold, const std::string& color = "text", float sidePad = 6.f) {
        Scene probe{s_.name}; Builder pb(probe, m_);
        for (auto& c : candidates) { Rect r = pb.text(c, y, spec, role, bold, color, sidePad); if (!probe.needsMore) { return text(c, y, spec, role, bold, color, sidePad); } probe.needsMore = false; probe.moreReason.clear(); probe.els.clear(); (void)r; }
        return text(candidates.back(), y, spec, role, bold, color, sidePad);
    }
    /// Text that may be longer than its box: shown fitted when possible; otherwise with an ellipsis AND an invisible
    /// full-band "More" touch target over it (tap opens the detail screen). Never silent, never tiny.
    Rect moreText(const std::string& txt, float y, const FitSpec& spec, Role role, bool bold, const std::string& color, float sidePad, const std::string& id) {
        float h = spec.maxLines * m_.lineHeight(spec.fontPx);
        Rect band = bandAt(y, h, sidePad);
        Fitted f = fitText(m_, txt, {spec.fontPx, spec.minFontPx, spec.maxLines, false}, bold, band.w, h);
        if (f.fits) return text(txt, y, spec, role, bold, color, sidePad, false, id);
        Rect touch = bandAt(y - 4, std::max(h + 8, MIN_TOUCH), sidePad - 4);
        Element btn{Kind::Rect, Role::Button, touch}; btn.fill = "bg"; btn.id = "more"; s_.els.push_back(btn);
        Fitted g = fitText(m_, txt, {spec.fontPx, spec.minFontPx, spec.maxLines, true}, bold, band.w, h);
        float lh = m_.lineHeight(g.font); float maxw = 0; for (auto& l : g.lines) maxw = std::max(maxw, m_.width(l, g.font, bold));
        Rect r{CX - maxw / 2, y, maxw, lh * g.lines.size()};
        Element e{Kind::Text, role, r}; e.text = txt; e.font = g.font; e.bold = bold; e.color = color; e.lines = int(g.lines.size()); e.truncated = true; e.id = id; e.fitLines = g.lines; s_.els.push_back(e);
        return r;
    }
    /// Progress / zone arc along the rim.
    void arc(float a0, float a1, float stroke, const std::string& color, float radius = RADIUS - EDGE_INSET - 4, const std::string& id = "") {
        Element e{Kind::Arc, Role::Decor, {CX - radius, CY - radius, 2 * radius, 2 * radius}}; e.a0 = a0; e.a1 = a1; e.stroke = stroke; e.color = color; e.id = id; s_.els.push_back(e);
    }
    /// Segmented ring: `n` equal segments between a0 and a1 (a 240° ladder for zones); segment `lit` is drawn in `litColor`.
    void segments(float a0, float a1, int n, float stroke, const std::string& trackColor, int lit, const std::string& litColor, float radius, const std::string& id = "") {
        float span = (a1 - a0) / n, gap = 3.f;
        for (int i = 0; i < n; i++) arc(a0 + i * span + gap / 2, a0 + (i + 1) * span - gap / 2, stroke, i == lit ? litColor : trackColor, radius, id.empty() ? "" : id + "." + std::to_string(i));
    }
    /// Needle dot on a ring at angle a (degrees, 0 = top, clockwise).
    void needle(float a, float radius, float r, const std::string& color, const std::string& id = "") {
        float t = (a - 90) * 3.14159265f / 180; dot(CX + radius * std::cos(t), CY + radius * std::sin(t), r, color); if (!id.empty()) s_.els.back().id = id;
    }
    /// Sparkline inside a box: normalised points (x, y in 0…1), gaps break the line. Drawn as decor; the box is a panel.
    void sparkline(const Rect& box, const std::vector<std::optional<std::pair<float, float>>>& pts, const std::string& color, float stroke = 2.f, const std::string& id = "") {
        Element e{Kind::Polyline, Role::Decor, box}; e.color = color; e.stroke = stroke; e.id = id;
        for (auto& p : pts) e.pts.push_back(p ? std::optional<std::pair<float, float>>(std::make_pair(box.x + p->first * box.w, box.bottom() - p->second * box.h)) : std::nullopt);
        s_.els.push_back(e);
    }
    /// Absolute polyline (breadcrumb trail), already projected into the circle. A nullopt point breaks the line: a
    /// breadcrumb that left the visible radius is a GAP, never a point dragged onto the rim (that would draw a false route).
    void polyline(const std::vector<std::optional<std::pair<float, float>>>& pts, const std::string& color, float stroke, const std::string& id = "") {
        bool any = false; float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
        for (auto& p : pts) { if (!p) continue; if (!any) { x0 = x1 = p->first; y0 = y1 = p->second; any = true; } x0 = std::min(x0, p->first); y0 = std::min(y0, p->second); x1 = std::max(x1, p->first); y1 = std::max(y1, p->second); }
        if (!any) return;
        Element e{Kind::Polyline, Role::Decor, {x0, y0, x1 - x0, y1 - y0}}; e.color = color; e.stroke = stroke; e.id = id; e.pts = pts; s_.els.push_back(e);
    }
    /// Position marker: a triangle pointing along `headingDeg` (0 = up); hollow when the fix is not live.
    void marker(float cx, float cy, float headingDeg, const std::string& color, bool hollow, const std::string& id = "") {
        Element e{Kind::Marker, Role::Icon, {cx - 9, cy - 9, 18, 18}}; e.color = color; e.fill = hollow ? "" : color; e.rot = headingDeg; e.id = id; s_.els.push_back(e);
    }
    void dot(float cx, float cy, float r, const std::string& color, Role role = Role::Indicator) { Element e{Kind::Circle, role, {cx - r, cy - r, 2 * r, 2 * r}}; e.fill = color; s_.els.push_back(e); }
    void panel(const Rect& r, const std::string& fill) { Element e{Kind::Rect, Role::Decor, r}; e.fill = fill; s_.els.push_back(e); }

    /// List row inside the circle at y: full-width band, title left (fitted, 1 line, ellipsis allowed for non-critical), value right.
    Rect row(const std::string& title, const std::string& trailing, float y, float h, const std::string& id, bool critical = false) {
        Rect band = bandAt(y, h, 14);
        if (band.w < 100) { s_.needsMore = true; s_.moreReason += "; row '" + title + "' has no room at y=" + std::to_string(int(y)); return {0, 0, 0, 0}; }
        Element bg{Kind::Rect, Role::Button, band}; bg.fill = "card"; bg.id = id; bg.critical = critical; s_.els.push_back(bg);
        float tw = trailing.empty() ? 0 : m_.width(trailing, 13, false) + 10;
        Rect tb{band.x + 12, y + (h - m_.lineHeight(15)) / 2, band.w - 24 - tw, m_.lineHeight(15)};
        textIn(title, tb, {15, 13, 1, !critical}, Role::Body, true, "text", critical, id + ".title");
        if (!trailing.empty()) { Element t{Kind::Text, Role::Label, {band.right() - 12 - tw + 10, y + (h - m_.lineHeight(13)) / 2, tw - 10, m_.lineHeight(13)}}; t.text = trailing; t.font = 13; t.color = "mut"; s_.els.push_back(t); }
        return band;
    }
private:
    Scene& s_; const TextMeasurer& m_;
};

} // namespace cyw::ui
