#pragma once
// Cyclift Watch OS — round-display quality checks (owner §4): bounding-box overflow, text overlap, critical-control
// visibility, contrast, no silent truncation, touch-target size, grading colours untouched by the theme. Runs on the
// host over the scenes the layout engine produced; a screen is not "complete" until every check passes in all six
// appearances and at every text-length variant.
#include "round_layout.hpp"
#include "theme_tokens.hpp"
#include <sstream>

namespace cyw::ui {

struct Finding { std::string screen, theme, variant, rule, detail; };

inline double luminance(const std::string& hex) {
    auto ch = [&](int i) { double c = std::stoi(hex.substr(i, 2), nullptr, 16) / 255.0; return c <= 0.03928 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); };
    return 0.2126 * ch(1) + 0.7152 * ch(3) + 0.0722 * ch(5);
}
inline double contrast(const std::string& a, const std::string& b) { double la = luminance(a), lb = luminance(b); if (la < lb) std::swap(la, lb); return (la + 0.05) / (lb + 0.05); }

inline std::vector<Finding> check(const Scene& s, const Appearance& ap, const std::string& variant) {
    std::vector<Finding> out;
    auto add = [&](const std::string& rule, const std::string& detail) { out.push_back({s.name, ap.name, variant, rule, detail}); };
    // 1. nothing leaves the usable circle
    for (auto& e : s.els) if (e.kind == Kind::Polyline) { float rr = (RADIUS - EDGE_INSET) * (RADIUS - EDGE_INSET); for (auto& p : e.pts) if (p && (p->first - CX) * (p->first - CX) + (p->second - CY) * (p->second - CY) > rr + 0.5f) { add("overflow", "polyline '" + e.id + "' has a point outside the circle"); break; } }
    for (auto& e : s.els) if (e.kind != Kind::Arc && e.kind != Kind::Polyline && !insideCircle(e.r)) add("overflow", "'" + (e.text.empty() ? e.id : e.text) + "' crosses the circular boundary (" + std::to_string(int(e.r.x)) + "," + std::to_string(int(e.r.y)) + " " + std::to_string(int(e.r.w)) + "×" + std::to_string(int(e.r.h)) + ")");
    // 2. no text overlaps another text, icon or button label (buttons' own labels sit on their rect by design)
    for (size_t i = 0; i < s.els.size(); i++) for (size_t j = i + 1; j < s.els.size(); j++) {
        auto& a = s.els[i]; auto& b = s.els[j];
        auto textish = [](const Element& e) { return e.kind == Kind::Text || e.role == Role::Icon; };
        if (!(textish(a) && textish(b))) continue;
        if (a.r.intersects(b.r)) add("overlap", "'" + a.text + "' overlaps '" + b.text + "'");
    }
    // 3. text inside a button stays inside it; buttons ≥ 44 pt; critical controls present
    bool sawCritical = false;
    for (auto& e : s.els) if (e.kind == Kind::Rect && e.role == Role::Button) {
        if (e.r.w < MIN_TOUCH - 0.01f || e.r.h < MIN_TOUCH - 0.01f) add("touch-size", e.id + " is " + std::to_string(int(e.r.w)) + "×" + std::to_string(int(e.r.h)) + " (< 44)");
        if (e.critical) sawCritical = true;
        for (auto& t : s.els) if (t.kind == Kind::Text && t.id == e.id + ".label" && !(t.r.x >= e.r.x - 0.5f && t.r.right() <= e.r.right() + 0.5f && t.r.y >= e.r.y - 0.5f && t.r.bottom() <= e.r.bottom() + 0.5f)) add("label-outside-button", t.text);
    }
    if (s.name.rfind("live:", 0) == 0 && !sawCritical) add("critical-missing", "a live activity screen has no critical control");
    // 4. truncation is never silent on critical text; any truncation is reported
    // an ellipsis is acceptable only when the screen offers an explicit More / detail control (owner §1), never on critical text
    bool hasMore = false; for (auto& e : s.els) if (e.kind == Kind::Rect && e.role == Role::Button && e.id == "more") hasMore = true;
    for (auto& e : s.els) if (e.kind == Kind::Text && e.truncated) {
        bool inRow = e.id.size() > 6 && e.id.compare(e.id.size() - 6, 6, ".title") == 0;      // a list row is itself the tap-to-open control
        if (e.critical) add("critical-truncated", "'" + e.text + "'"); else if (!hasMore && !inRow) add("truncated-without-more", "'" + e.text + "' shown with an ellipsis and no More control"); }
    if (s.needsMore) add("does-not-fit", s.moreReason + " → needs paging / detail / More");
    // 5. minimum font sizes by role
    for (auto& e : s.els) if (e.kind == Kind::Text) {
        float mn = e.role == Role::Value ? MIN_FONT_NUMBER : e.role == Role::Comp ? MIN_FONT_COMP : (e.role == Role::Label || e.role == Role::Unit) ? MIN_FONT_LABEL : e.role == Role::Button ? MIN_FONT_BUTTON : MIN_FONT_BODY;
        if (e.font < mn - 0.01f) add("font-too-small", "'" + e.text + "' at " + std::to_string(int(e.font)) + " px (min " + std::to_string(int(mn)) + ")");
    }
    // 6. contrast: text tokens on the canvas / card ≥ 4.5:1 (≥ 3:1 for ≥ 24 px bold), grading colours ≥ 3:1 on the canvas
    for (auto& e : s.els) if (e.kind == Kind::Text) {
        std::string fg = ap.resolve(e.color); std::string bg = ap.resolve("bg");
        for (auto& p : s.els) if (p.kind == Kind::Rect && p.r.intersects(e.r) && !p.fill.empty()) bg = ap.resolve(p.fill);   // last panel under the text
        double c = contrast(fg, bg); double need = (e.font >= 24 && e.bold) ? 3.0 : 4.5;
        if (c < need) add("contrast", "'" + e.text + "' " + e.color + " on " + bg + " = " + std::to_string(c).substr(0, 4) + " (need " + std::to_string(need).substr(0, 3) + ")");
    }
    for (auto g : {"grade.red", "grade.yellow", "grade.blue", "grade.green"}) if (contrast(ap.resolve(g), ap.resolve("bg")) < 3.0) add("grading-contrast", std::string(g) + " on the canvas < 3:1");
    return out;
}

} // namespace cyw::ui
