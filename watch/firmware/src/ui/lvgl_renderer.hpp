#pragma once
// Cyclift Watch OS — draws a layout-engine Scene with LVGL 8 on the GC9A01 (device build only).
// One renderer for every screen: the scene is the single source of truth, so what passed the round-display checks on
// the host is exactly what the watch draws. Text is measured with the real LVGL fonts (`LvglMeasurer`), so the fitter
// sees the device's metrics, not the host approximation.
#ifndef CYW_HOST
#include <lvgl.h>
#include "../domain/round_layout.hpp"
#include "../domain/theme_tokens.hpp"

namespace cyw::ui {

/// Font ladder: Montserrat at 12 · 14 · 16 · 20 · 24 · 28 · 32 · 40 · 48 (enabled in lv_conf.h). A requested size maps to
/// the largest font ≤ request (never larger, so a fit proven on the host stays a fit).
inline const lv_font_t* fontFor(float px) {
    struct F { float px; const lv_font_t* f; };
    static const F ladder[] = {{48, &lv_font_montserrat_48}, {40, &lv_font_montserrat_40}, {32, &lv_font_montserrat_32}, {28, &lv_font_montserrat_28}, {24, &lv_font_montserrat_24}, {20, &lv_font_montserrat_20}, {16, &lv_font_montserrat_16}, {14, &lv_font_montserrat_14}, {12, &lv_font_montserrat_12}};
    for (auto& l : ladder) if (px >= l.px - 0.01f) return l.f;
    return &lv_font_montserrat_12;
}

/// Measures with the LVGL font the renderer will use; bold is approximated by +6 % (Montserrat Medium is the only
/// weight compiled in — a bold cut can be added later as a custom font).
struct LvglMeasurer : TextMeasurer {
    float width(const std::string& s, float fontPx, bool bold) const override {
        const lv_font_t* f = fontFor(fontPx); lv_point_t sz; lv_txt_get_size(&sz, s.c_str(), f, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
        return sz.x * (bold ? 1.06f : 1.f);
    }
    float lineHeight(float fontPx) const override { return lv_font_get_line_height(fontFor(fontPx)) + 2.f; }
};

inline lv_color_t colorOf(const Appearance& ap, const std::string& token) { std::string h = ap.resolve(token); return lv_color_hex(uint32_t(std::strtoul(h.c_str() + (h[0] == '#' ? 1 : 0), nullptr, 16))); }

/// Renders `s` into `parent` (a full-screen lv_obj the shell owns), replacing whatever was there.
class SceneRenderer {
public:
    void render(lv_obj_t* parent, const Scene& s, const Appearance& ap) {
        lv_obj_clean(parent);
        lv_obj_set_style_bg_color(parent, colorOf(ap, "bg"), 0); lv_obj_set_style_bg_opa(parent, LV_OPA_COVER, 0);
        for (auto& e : s.els) {
            switch (e.kind) {
                case Kind::Rect: {
                    lv_obj_t* o = lv_obj_create(parent); lv_obj_remove_style_all(o);
                    lv_obj_set_pos(o, int(e.r.x), int(e.r.y)); lv_obj_set_size(o, int(e.r.w), int(e.r.h));
                    lv_obj_set_style_bg_color(o, colorOf(ap, e.fill.empty() ? "card" : e.fill), 0); lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
                    lv_obj_set_style_radius(o, e.role == Role::Button ? 22 : 12, 0);
                    break; }
                case Kind::Circle: {
                    lv_obj_t* o = lv_obj_create(parent); lv_obj_remove_style_all(o);
                    lv_obj_set_pos(o, int(e.r.x), int(e.r.y)); lv_obj_set_size(o, int(e.r.w), int(e.r.h));
                    lv_obj_set_style_bg_color(o, colorOf(ap, e.fill.empty() ? "card" : e.fill), 0); lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
                    lv_obj_set_style_radius(o, LV_RADIUS_CIRCLE, 0);
                    break; }
                case Kind::Arc: {
                    lv_obj_t* a = lv_arc_create(parent); lv_obj_remove_style_all(a);
                    lv_obj_set_pos(a, int(e.r.x), int(e.r.y)); lv_obj_set_size(a, int(e.r.w), int(e.r.h));
                    lv_arc_set_rotation(a, 270); lv_arc_set_bg_angles(a, 0, 360);
                    // the scene's angles are 0 = top, clockwise; LVGL's 0 = 3 o'clock, so rotation 270 brings 0 to the top
                    auto norm = [](float d) { while (d < 0) d += 360; while (d >= 360) d -= 360; return uint16_t(d + 0.5f); };
                    if (e.a1 - e.a0 >= 359.9f) lv_arc_set_angles(a, 0, 360); else lv_arc_set_angles(a, norm(e.a0), norm(e.a1));
                    lv_obj_set_style_arc_width(a, int(e.stroke), LV_PART_INDICATOR); lv_obj_set_style_arc_color(a, colorOf(ap, e.color), LV_PART_INDICATOR); lv_obj_set_style_arc_rounded(a, true, LV_PART_INDICATOR);
                    lv_obj_set_style_arc_opa(a, LV_OPA_TRANSP, LV_PART_MAIN); lv_obj_remove_style(a, nullptr, LV_PART_KNOB); lv_obj_clear_flag(a, LV_OBJ_FLAG_CLICKABLE);
                    break; }
                case Kind::Polyline: {
                    // LVGL lines cannot have gaps: one lv_line per continuous run
                    std::vector<lv_point_t> run; auto flush = [&]() { if (run.size() >= 2) { lv_obj_t* l = lv_line_create(parent); auto* pts = new lv_point_t[run.size()]; std::copy(run.begin(), run.end(), pts); lv_line_set_points(l, pts, uint16_t(run.size())); lv_obj_set_style_line_width(l, int(std::max(1.f, e.stroke)), 0); lv_obj_set_style_line_color(l, colorOf(ap, e.color), 0); lv_obj_set_style_line_rounded(l, true, 0); lv_obj_add_event_cb(l, [](lv_event_t* ev) { delete[] static_cast<lv_point_t*>(lv_event_get_user_data(ev)); }, LV_EVENT_DELETE, pts); } run.clear(); };
                    for (auto& p : e.pts) { if (!p) { flush(); continue; } run.push_back({lv_coord_t(p->first), lv_coord_t(p->second)}); }
                    flush(); break; }
                case Kind::Marker: {
                    float cx = e.r.cx(), cy = e.r.cy(), t = e.rot * 3.14159265f / 180; auto rot = [&](float x, float y) { return lv_point_t{lv_coord_t(cx + x * std::cos(t) - y * std::sin(t)), lv_coord_t(cy + x * std::sin(t) + y * std::cos(t))}; };
                    auto* pts = new lv_point_t[5]{rot(0, -9), rot(7, 7), rot(0, 3), rot(-7, 7), rot(0, -9)};
                    lv_obj_t* l = lv_line_create(parent); lv_line_set_points(l, pts, 5); lv_obj_set_style_line_width(l, 2, 0); lv_obj_set_style_line_color(l, colorOf(ap, e.color), 0); lv_obj_add_event_cb(l, [](lv_event_t* ev) { delete[] static_cast<lv_point_t*>(lv_event_get_user_data(ev)); }, LV_EVENT_DELETE, pts);
                    break; }
                case Kind::Text: {
                    lv_obj_t* lb = lv_label_create(parent); lv_obj_remove_style_all(lb);
                    std::string txt; for (size_t i = 0; i < e.fitLines.size(); i++) { if (i) txt += "\n"; txt += e.fitLines[i]; } if (txt.empty()) txt = e.text;
                    lv_label_set_text(lb, txt.c_str());
                    lv_obj_set_style_text_font(lb, fontFor(e.font), 0); lv_obj_set_style_text_color(lb, colorOf(ap, e.color), 0);
                    bool centred = std::fabs(e.r.cx() - CX) < 1.f || e.role == Role::Button;
                    lv_obj_set_style_text_align(lb, centred ? LV_TEXT_ALIGN_CENTER : LV_TEXT_ALIGN_LEFT, 0);
                    lv_obj_set_pos(lb, int(e.r.x), int(e.r.y)); lv_obj_set_width(lb, int(std::max(e.r.w, 1.f)) + 2);
                    break; }
            }
        }
    }
};

} // namespace cyw::ui
#endif
