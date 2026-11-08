#pragma once
// Cyclift Watch OS — host renderer: a Scene → SVG with the appearance's tokens, used for screenshot evidence.
// The device draws the same scene with LVGL; positions come from the same layout engine.
#include "round_layout.hpp"
#include "theme_tokens.hpp"
#include <sstream>
#include <iomanip>

namespace cyw::ui {

inline std::string esc(const std::string& s) { std::string o; for (char c : s) { switch (c) { case '&': o += "&amp;"; break; case '<': o += "&lt;"; break; case '>': o += "&gt;"; break; case '"': o += "&quot;"; break; default: o += c; } } return o; }

inline std::string toSvg(const Scene& s, const Appearance& ap, const TextMeasurer& m, bool showBounds = false) {
    std::ostringstream o; o << std::fixed << std::setprecision(1);
    o << "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 240 240' width='240' height='240'><defs><clipPath id='c'><circle cx='120' cy='120' r='120'/></clipPath></defs><g clip-path='url(#c)'>";
    o << "<rect width='240' height='240' fill='" << ap.resolve("bg") << "'/>";
    for (auto& e : s.els) {
        switch (e.kind) {
            case Kind::Rect: o << "<rect x='" << e.r.x << "' y='" << e.r.y << "' width='" << e.r.w << "' height='" << e.r.h << "' rx='" << (e.role == Role::Button ? 22 : 12) << "' fill='" << ap.resolve(e.fill) << "'/>"; break;
            case Kind::Circle: o << "<circle cx='" << e.r.cx() << "' cy='" << e.r.cy() << "' r='" << e.r.w / 2 << "' fill='" << ap.resolve(e.fill) << "'/>"; break;
            case Kind::Arc: {
                float r = e.r.w / 2; auto pt = [&](float a) { float t = (a - 90) * 3.14159265f / 180; return std::make_pair(CX + r * std::cos(t), CY + r * std::sin(t)); };
                if (e.a1 - e.a0 >= 359.9f) { o << "<circle cx='120' cy='120' r='" << r << "' fill='none' stroke='" << ap.resolve(e.color) << "' stroke-width='" << e.stroke << "'/>"; break; }
                auto p0 = pt(e.a0), p1 = pt(e.a1); int large = (e.a1 - e.a0) > 180 ? 1 : 0;
                o << "<path d='M" << p0.first << "," << p0.second << " A" << r << "," << r << " 0 " << large << " 1 " << p1.first << "," << p1.second << "' fill='none' stroke='" << ap.resolve(e.color) << "' stroke-width='" << e.stroke << "' stroke-linecap='round'/>"; break; }
            case Kind::Text: {
                float lh = m.lineHeight(e.font); std::vector<std::string> lines = e.fitLines; if (lines.empty()) { wrap(m, e.text, e.font, e.bold, e.r.w + 0.5f, e.lines, lines); if (lines.empty()) lines = {e.text}; }
                for (size_t i = 0; i < lines.size(); i++) {
                    float tw = m.width(lines[i], e.font, e.bold); float x = (e.role == Role::Label && e.r.x < CX - 60 && e.r.w < 60) ? e.r.x : (std::fabs(e.r.cx() - CX) < 1.f ? CX - tw / 2 : e.r.x);
                    o << "<text x='" << x << "' y='" << e.r.y + lh * i + lh * 0.78f << "' font-family='Inter,Montserrat,system-ui,sans-serif' font-size='" << e.font << "' font-weight='" << (e.bold ? 700 : 500) << "' fill='" << ap.resolve(e.color) << "'>" << esc(lines[i]) << "</text>";
                }
                if (showBounds) o << "<rect x='" << e.r.x << "' y='" << e.r.y << "' width='" << e.r.w << "' height='" << e.r.h << "' fill='none' stroke='#FF00FF' stroke-width='0.5'/>";
                break; }
        }
    }
    o << "</g><circle cx='120' cy='120' r='119' fill='none' stroke='#000' stroke-opacity='0.4' stroke-width='2'/>";
    if (showBounds) o << "<circle cx='120' cy='120' r='" << RADIUS - EDGE_INSET << "' fill='none' stroke='#FF00FF' stroke-width='0.5' stroke-dasharray='3 3'/>";
    o << "</svg>";
    return o.str();
}

} // namespace cyw::ui
