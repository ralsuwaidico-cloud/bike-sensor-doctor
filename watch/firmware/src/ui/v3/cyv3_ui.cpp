// Cyclift Watch v3 — Stage 1 LVGL screens. Geometry follows the approved prototype (Deliverable D v3.1, src/screens1.js,
// src/screens2.js, src/core.js): every "top" below is the prototype's line-box top in watch pixels.
#if defined(CYW_V3POC)
#include "cyv3_ui.hpp"
#include <cstring>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#ifndef CYW_HOST
#include <esp_heap_caps.h>
#endif

extern "C" {
extern const lv_img_dsc_t cyv3_ic_face_20, cyv3_ic_today_20, cyv3_ic_plan_20, cyv3_ic_heart_20, cyv3_ic_coach_20, cyv3_ic_hist_20,
    cyv3_ic_util_20, cyv3_ic_gear_20, cyv3_ic_bike_20, cyv3_ic_chev_12, cyv3_ic_chevl_12, cyv3_ic_down_11, cyv3_ic_bolt_12,
    cyv3_ic_check_15, cyv3_ic_warn_15,
    cyv3_ic_sun_20, cyv3_ic_palette_20, cyv3_ic_moon_20, cyv3_ic_lock_20, cyv3_ic_info_20, cyv3_ic_heart_22, cyv3_ic_bike_22,
    cyv3_ic_today_28, cyv3_ic_moon_28, cyv3_ic_heart_28, cyv3_ic_coach_28, cyv3_ic_hist_28, cyv3_ic_util_28, cyv3_ic_gear_28;
}

namespace cyw::v3 {

namespace {
constexpr int C = 120;
constexpr float R = 114.f;                       // safe radius used by the approved layout rules
constexpr float PI_F = 3.14159265f;
float hw(float y) { float d = std::fabs(y - C); return d >= R ? 0.f : std::sqrt(R * R - d * d); }
float chordAt(float top, float bottom) { return 2.f * std::min(hw(top), hw(bottom)); }
void pol(float r, float a, float& x, float& y) { x = C + r * std::sin(a * PI_F / 180.f); y = C - r * std::cos(a * PI_F / 180.f); }
lv_color_t col(uint32_t c) { return lv_color_hex(c); }
float gaugeAngle(float v) { return -135.f + 270.f * std::min(1.f, std::max(0.f, v / float(Model::GAUGE_MAX))); }
std::string fmtTime(int s) { s = std::max(0, s); char b[16]; std::snprintf(b, sizeof b, "%d:%02d", s / 60, s % 60); return b; }
std::string fmtV(int v) { if (v < 0) return "\xE2\x80\x94"; return std::to_string(v); }   // missing value = em dash
const lv_img_dsc_t* menuIcon(MenuId id) {
    switch (id) {
        case MenuId::ReturnToWorkout: return &cyv3_ic_bike_20;
        case MenuId::WatchFace: return &cyv3_ic_face_20;
        case MenuId::Today: return &cyv3_ic_today_20;
        case MenuId::Activities: return &cyv3_ic_plan_20;
        case MenuId::Health: return &cyv3_ic_heart_20;
        case MenuId::Coach: return &cyv3_ic_coach_20;
        case MenuId::History: return &cyv3_ic_hist_20;
        case MenuId::Utilities: return &cyv3_ic_util_20;
        case MenuId::Settings: return &cyv3_ic_gear_20;
    }
    return &cyv3_ic_face_20;
}
S menuText(MenuId id) {
    switch (id) {
        case MenuId::ReturnToWorkout: return S::ReturnToWorkout;
        case MenuId::WatchFace: return S::WatchFace;
        case MenuId::Today: return S::Today;
        case MenuId::Activities: return S::Activities;
        case MenuId::Health: return S::Health;
        case MenuId::Coach: return S::Coach;
        case MenuId::History: return S::History;
        case MenuId::Utilities: return S::Utilities;
        case MenuId::Settings: return S::Settings;
    }
    return S::WatchFace;
}
}  // namespace

// ---------------------------------------------------------------------------------------------------------------- setup
void Ui::begin(lv_obj_t* root) {
    linkFonts();
    root_ = root;
    lv_obj_clear_flag(root_, LV_OBJ_FLAG_SCROLLABLE);
    keyValid_ = false;
}

Ui::Key Ui::structureKey(const Model& m) const {
    // same fields as the Stage 1 key string (screen, settings, workout, links, sensors present, overlays, scroll, rings);
    // integers instead of snprintf: the key is built on every 10 ms frame (Stage 1.1)
    return Key{int(m.screen), int(m.settings.theme), int(m.settings.density), int(m.settings.text), int(m.settings.lang), int(m.wk), int(m.pending),
        int(m.phoneLinked), int(m.synced && m.clock.valid), int(m.charging), int(m.m.power >= 0), int(m.m.hr >= 0), int(m.m.cadence >= 0),
        int(m.toast.kind), int(m.toast.text), int(m.toast.hasSub), int(m.toast.sub), int(m.key2Armed && m.screen == Screen::Cockpit), m.menuScroll,
        m.movePct, m.loadPct,
        // Stage 1.3
        int(m.synced), m.settings.brightness, int(m.settings.dnd), int(m.settings.mode), int(m.locked), int(m.notYet), m.qsScroll,
        int(m.clock.valid), (m.screen == Screen::Today || m.screen == Screen::Week) ? m.clock.weekday * 64 + m.clock.day : 0, 0, 0};
}

bool Ui::render(const Model& m) {
    pal_ = &palette(m.settings.theme); large_ = m.large(); ar_ = m.rtl();
    Key k = structureKey(m);
    if (!keyValid_ || k != key_) {
        static const char* const N[32] = {"screen", "theme", "density", "text size", "language", "workout", "pending", "phone link",
            "synced+clock", "charging", "power present", "hr present", "cadence present", "toast", "toast text", "toast sub", "toast sub text",
            "key2 armed", "menu scroll", "move", "load", "synced", "brightness", "dnd", "mode", "locked", "not-yet page", "qs scroll",
            "clock valid", "today date", "-", "-"};
        cause_[0] = 0;
        if (keyValid_) for (int i = 0; i < 32; i++) if (k[i] != key_[i]) {
            size_t n = std::strlen(cause_); if (n + std::strlen(N[i]) + 3 >= sizeof cause_) break;
            std::snprintf(cause_ + n, sizeof cause_ - n, "%s%s", n ? ", " : "", N[i]);
        }
        key_ = k; keyValid_ = true; build(m); rebuilds++; return true;
    }
    update(m); updates++;
    return false;
}

bool Ui::tap(Model& m, int x, int y, uint32_t now) {
    for (auto& h : hits_)
        if (x >= h.area.x1 && x <= h.area.x2 && y >= h.area.y1 && y <= h.area.y2) { m.act(h.action, h.arg, now); return true; }
    return false;
}

namespace {
/// No watch object scrolls. LVGL still computes the scroll extent of every scrollable object each time it draws one
/// (13 % of a 1 Hz cockpit update on the computer benchmark), so the flag is cleared on the whole tree.
void noScroll(lv_obj_t* o) {
    lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE); lv_obj_set_scrollbar_mode(o, LV_SCROLLBAR_MODE_OFF);
    for (uint32_t i = 0; i < lv_obj_get_child_cnt(o); i++) noScroll(lv_obj_get_child(o, int32_t(i)));
}
/// Ring arcs: skip the arc's own drawing when the area being redrawn lies wholly inside its inner edge (no arc pixels
/// there). A PREPROCESS handler runs before the widget's handler and stops it (LVGL 8.3 event order).
void ringSkipCb(lv_event_t* e) {
    const lv_draw_ctx_t* dc = lv_event_get_draw_ctx(e);
    lv_obj_t* o = lv_event_get_target(e); lv_area_t c; lv_obj_get_coords(o, &c);
    float cx = (c.x1 + c.x2 + 1) / 2.f, cy = (c.y1 + c.y2 + 1) / 2.f, in = float(intptr_t(lv_event_get_user_data(e))) - 2.f;   // 2 px: anti-aliasing
    const lv_area_t* a = dc->clip_area; float far2 = 0;
    for (float x : {float(a->x1), float(a->x2) + 1.f}) for (float y : {float(a->y1), float(a->y2) + 1.f}) far2 = std::max(far2, (x - cx) * (x - cx) + (y - cy) * (y - cy));
    if (far2 < in * in) lv_event_stop_processing(e);
}
/// Cover check for the opaque ring image, answered here: LVGL 8.3.11's lv_img cover check reads the event parameter as
/// an area although it is an lv_cover_check_info_t (uninitialised bytes under memcheck).
void ringCoverCb(lv_event_t* e) {
    lv_cover_check_info_t* info = static_cast<lv_cover_check_info_t*>(lv_event_get_param(e));
    lv_obj_t* o = lv_event_get_target(e);
    if (info->res != LV_COVER_RES_MASKED) info->res = _lv_area_is_in(info->area, &o->coords, 0) ? LV_COVER_RES_COVER : LV_COVER_RES_NOT_COVER;
    lv_event_stop_processing(e);
}
}  // namespace

void Ui::ringSkip(lv_obj_t* a, int innerRadius) {
    lv_obj_add_event_cb(a, ringSkipCb, lv_event_code_t(LV_EVENT_DRAW_MAIN | LV_EVENT_PREPROCESS), reinterpret_cast<void*>(intptr_t(innerRadius)));
}

namespace {
bool hasArabic(const std::string& s) {     // U+0600–U+06FF are encoded with lead bytes 0xD8–0xDB in UTF-8
    for (unsigned char c : s) if (c >= 0xD8 && c <= 0xDB) return true;
    return false;
}
}  // namespace

void Ui::putText(lv_obj_t* l, const std::string& s) {
    std::string& keep = src_[l];
    keep = s;
    if (hasArabic(s)) lv_label_set_text(l, s.c_str());
    else lv_label_set_text_static(l, keep.c_str());   // unordered_map nodes never move: the pointer stays valid
}

void Ui::dotMode(lv_obj_t* l) {
    lv_label_set_text(l, src_[l].c_str());           // private copy (and shaping) before LVGL may write dots into it
    lv_label_set_long_mode(l, LV_LABEL_LONG_DOT);
}

bool Ui::setText(lv_obj_t* l, const std::string& s) {
    auto it = src_.find(l);
    if (it != src_.end() && it->second == s) return false;
    if (lv_label_get_long_mode(l) == LV_LABEL_LONG_DOT) { src_[l] = s; lv_label_set_text(l, s.c_str()); }
    else putText(l, s);
    return true;
}

void Ui::build(const Model& m) {
    lv_obj_clean(root_);
    lines_.clear(); hits_.clear(); groups_.clear(); src_.clear();
    clock_ = date_ = interval_ = lead_ = hrTile_ = cadTile_ = bikeInfo_ = Run{};
    cmd_ = marker_ = ivArc_ = ringImg_ = nullptr;
    lv_obj_set_style_bg_color(root_, col(pal_->bg), 0); lv_obj_set_style_bg_opa(root_, LV_OPA_COVER, 0);
    switch (m.screen) {
        case Screen::Face: buildFace(m); break;
        case Screen::Menu: buildMenu(m); break;
        case Screen::Cockpit: buildCockpit(m); break;
        case Screen::Today: buildToday(m); break;
        case Screen::Week: buildWeek(m); break;
        case Screen::Quick: buildQuick(m); break;
        case Screen::WHealth: buildWHealth(m); break;
        case Screen::WCoach: buildWCoach(m); break;
        case Screen::WActivity: buildWActivity(m); break;
        case Screen::NotYet: buildNotYet(m); break;
    }
    buildOverlays(m);
    noScroll(root_);
}

void Ui::update(const Model& m) {
    if (m.screen == Screen::Face) updateFace(m);
    else if (m.screen == Screen::Cockpit) updateCockpit(m);
}

// ---------------------------------------------------------------------------------------------------------------- primitives
lv_obj_t* Ui::label(lv_obj_t* parent, const std::string& s, const Font& f, uint32_t color, bool rtlText) {
    lv_obj_t* l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, f.f, 0);
    lv_obj_set_style_text_color(l, col(color), 0);
    lv_obj_set_style_text_letter_space(l, (f.tracked && !ar_) ? 1 : 0, 0);
    lv_obj_set_style_base_dir(l, rtlText ? LV_BASE_DIR_RTL : LV_BASE_DIR_LTR, 0);
    lv_obj_clear_flag(l, LV_OBJ_FLAG_CLICKABLE);
    putText(l, s);
    return l;
}

void Ui::makeRun(Run& r) {
    for (auto& p : r.pieces) {
        switch (p.kind) {
            case Piece::Text: p.obj = label(root_, p.text, p.font, p.color, p.rtlText); break;
            case Piece::Dot: case Piece::RingDot: {
                p.obj = lv_obj_create(root_); lv_obj_remove_style_all(p.obj); lv_obj_set_size(p.obj, 7, 7);
                lv_obj_set_style_radius(p.obj, LV_RADIUS_CIRCLE, 0);
                if (p.kind == Piece::Dot) { lv_obj_set_style_bg_color(p.obj, col(p.color), 0); lv_obj_set_style_bg_opa(p.obj, LV_OPA_COVER, 0); }
                else { lv_obj_set_style_border_color(p.obj, col(p.color), 0); lv_obj_set_style_border_width(p.obj, 2, 0); lv_obj_set_style_border_opa(p.obj, LV_OPA_COVER, 0); }
                lv_obj_clear_flag(p.obj, LV_OBJ_FLAG_CLICKABLE); break; }
            case Piece::Icon: {
                p.obj = lv_img_create(root_); lv_img_set_src(p.obj, p.icon);
                lv_obj_set_style_img_recolor(p.obj, col(p.color), 0); lv_obj_set_style_img_recolor_opa(p.obj, LV_OPA_COVER, 0);
                lv_obj_clear_flag(p.obj, LV_OBJ_FLAG_CLICKABLE); break; }
        }
    }
    std::vector<lv_obj_t*> g; for (auto& p : r.pieces) g.push_back(p.obj); groups_.push_back(g);
    layoutRun(r);
}

void Ui::layoutRun(Run& r) {
    lv_obj_update_layout(root_);
    std::vector<int> w(r.pieces.size());
    int total = 0;
    for (size_t i = 0; i < r.pieces.size(); i++) {
        auto& p = r.pieces[i];
        w[i] = p.kind == Piece::Text ? lv_obj_get_width(p.obj) : p.kind == Piece::Icon ? int(p.icon->header.w) : 7;
        total += w[i] + (i ? p.gapBefore : 0);
    }
    r.width = total;
    int baseline = baselineOf(r.top, r.lineBox, r.mainCss);
    int x = int(std::lround(r.centerX - total / 2.0));
    for (size_t k = 0; k < r.pieces.size(); k++) {
        size_t i = r.reverse ? r.pieces.size() - 1 - k : k;
        auto& p = r.pieces[i];
        if (k) x += r.reverse ? r.pieces[i + 1].gapBefore : p.gapBefore;
        int y = p.kind == Piece::Text ? labelYFor(baseline, p.font.f) : p.kind == Piece::Icon ? baseline - int(p.icon->header.h) + p.iconDrop : baseline - 7;
        lv_obj_set_pos(p.obj, x, y);
        x += w[i];
    }
}

lv_obj_t* Ui::arc(int r, int width, float a0, float a1, uint32_t color, lv_opa_t opa) {
    if (a1 - a0 < 0.5f) return nullptr;
    lv_obj_t* a = lv_arc_create(root_); lv_obj_remove_style_all(a);
    int outer = int(std::lround(r + width / 2.0));
    lv_obj_set_size(a, 2 * outer, 2 * outer); lv_obj_set_pos(a, C - outer, C - outer);
    lv_arc_set_rotation(a, 270);                  // 0° at 12 o'clock, clockwise (the prototype's convention)
    auto norm = [](float d) { while (d < 0) d += 360; while (d >= 360) d -= 360; return uint16_t(std::lround(d)) % 360; };
    if (a1 - a0 >= 359.9f) lv_arc_set_angles(a, 0, 360); else lv_arc_set_angles(a, norm(a0), norm(a1));
    lv_obj_set_style_arc_width(a, width, LV_PART_INDICATOR); lv_obj_set_style_arc_color(a, col(color), LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(a, true, LV_PART_INDICATOR); lv_obj_set_style_arc_opa(a, opa, LV_PART_INDICATOR);
    lv_obj_clear_flag(a, LV_OBJ_FLAG_CLICKABLE);
    ringSkip(a, outer - width);
    return a;
}

lv_obj_t* Ui::line(std::vector<lv_point_t> pts, int width, uint32_t color) {
    lines_.push_back(std::move(pts));
    lv_obj_t* l = lv_line_create(root_);
    lv_line_set_points(l, lines_.back().data(), uint16_t(lines_.back().size()));
    lv_obj_set_style_line_width(l, width, 0); lv_obj_set_style_line_color(l, col(color), 0); lv_obj_set_style_line_rounded(l, true, 0);
    lv_obj_clear_flag(l, LV_OBJ_FLAG_CLICKABLE);
    return l;
}

lv_obj_t* Ui::chip(int top, const std::string& text, uint32_t color, int dot, uint32_t bg, int outline) {
    Font f = font(Type::Chip, false);
    lv_obj_t* box = lv_obj_create(root_); lv_obj_remove_style_all(box);
    lv_obj_set_style_bg_color(box, col(bg), 0); lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0); lv_obj_set_style_radius(box, RADIUS_S, 0);
    if (outline) { lv_obj_set_style_outline_width(box, outline, 0); lv_obj_set_style_outline_color(box, col(pal_->bg), 0); lv_obj_set_style_outline_opa(box, LV_OPA_COVER, 0); }
    lv_obj_clear_flag(box, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_t* t = label(box, text, f, color, ar_);
    lv_obj_update_layout(t);
    int tw = lv_obj_get_width(t), dw = dot ? 7 + 6 : 0, w = 9 + dw + tw + 9, h = 22;
    lv_obj_set_size(box, w, h); lv_obj_set_pos(box, C - w / 2, top);
    int ty = labelYFor(baselineOf(int((h - f.lineBox) / 2), f.lineBox, f.css), f.f);
    lv_obj_set_pos(t, ar_ ? 9 : 9 + dw, ty);
    if (dot) {
        lv_obj_t* d = lv_obj_create(box); lv_obj_remove_style_all(d); lv_obj_set_size(d, 7, 7); lv_obj_set_style_radius(d, LV_RADIUS_CIRCLE, 0);
        if (dot == 1) { lv_obj_set_style_bg_color(d, col(color), 0); lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0); }
        else { lv_obj_set_style_border_color(d, col(color), 0); lv_obj_set_style_border_width(d, 2, 0); lv_obj_set_style_border_opa(d, LV_OPA_COVER, 0); }
        lv_obj_set_pos(d, ar_ ? w - 9 - 7 : 9, (h - 7) / 2);
    }
    return box;
}

lv_obj_t* Ui::button(int top, const std::string& text, int kind, Action a) {
    Font f = font(Type::Button, large_);
    int h = large_ ? 48 : BUTTON_H, minW = large_ ? 84 : 76;
    // kind 2 = command pending: blue text (approved status colours: blue = pending)
    uint32_t bg = kind == 1 ? pal_->accent : pal_->surface_2, fg = kind == 1 ? pal_->on_accent : kind == 2 ? pal_->status_info : pal_->ink;
    lv_obj_t* b = lv_obj_create(root_); lv_obj_remove_style_all(b);
    lv_obj_set_style_bg_color(b, col(bg), 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0); lv_obj_set_style_radius(b, LV_RADIUS_CIRCLE, 0);
    lv_obj_clear_flag(b, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t* t = label(b, text, f, fg, ar_);
    lv_obj_update_layout(t);
    int w = std::max(minW, int(lv_obj_get_width(t)) + 2 * SPACE_XL);
    lv_obj_set_size(b, w, h); lv_obj_set_pos(b, C - w / 2, top);
    lv_obj_set_pos(t, (w - lv_obj_get_width(t)) / 2, labelYFor(baselineOf((h - f.lineBox) / 2, f.lineBox, f.css), f.f));
    if (kind != 2) hit(C - w / 2, top, w, h, a, 0, "button");
    return b;
}

void Ui::hit(int x, int y, int w, int h, Action a, int arg, const char* name) {
    lv_area_t ar{lv_coord_t(x), lv_coord_t(y), lv_coord_t(x + w - 1), lv_coord_t(y + h - 1)};
    hits_.push_back({ar, a, arg, name});
}

// ---------------------------------------------------------------------------------------------------------------- face (Orbit)
void Ui::buildFace(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    bool synced = m.synced && m.clock.valid;
    arc(110, 5, 0, 360, p.line); arc(99, 5, 0, 360, p.line);
    if (synced) { arc(110, 5, 0, 3.6f * m.movePct, p.accent); arc(99, 5, 0, 3.6f * m.loadPct, p.ink_2); }
    if (!m.phoneLinked) chip(40, tr(S::PhoneLost, l), p.status_critical, 1, p.surface);

    clock_ = Run{}; clock_.top = 64; clock_.lineBox = 58; clock_.mainCss = 54;
    // RC2 (owner decision 11 Nov 20:51): the time and date follow the clock chip alone; "synced" governs only the
    // iPhone data on this face (rings, next ride, Move / Load)
    Piece c; c.text = m.clock.valid ? "00:00" : "--:--"; c.font = font(Type::Clock54, false); c.color = p.ink; clock_.pieces.push_back(c);
    makeRun(clock_);

    Font lbl = font(Type::Label, large_);
    date_ = Run{}; date_.top = 126; date_.lineBox = lbl.lineBox; date_.mainCss = lbl.css; date_.reverse = ar_;
    Piece d; d.text = "-"; d.font = lbl; d.color = p.ink_2; d.rtlText = ar_; date_.pieces.push_back(d);
    if (m.charging) { Piece b; b.kind = Piece::Icon; b.icon = &cyv3_ic_bolt_12; b.gapBefore = 8; b.iconDrop = 1; b.color = p.ink_2; date_.pieces.push_back(b); }
    Piece bt; bt.text = "0%"; bt.font = lbl; bt.color = p.ink_2; bt.gapBefore = m.charging ? 4 : 8; date_.pieces.push_back(bt);
    makeRun(date_);
    updateFace(m);

    if (synced) {
        Run n; n.top = 148; n.lineBox = 16; n.mainCss = 13;
        // the time is its own left-to-right piece: LVGL 8.3's bidi algorithm reverses "18:30" inside right-to-left text
        n.reverse = ar_;
        std::string lead = trs(S::NextRide, l, ""); while (!lead.empty() && lead.back() == ' ') lead.pop_back();
        Piece t; t.text = lead; t.font = font(Type::Small13, false); t.color = p.ink; t.rtlText = ar_; n.pieces.push_back(t);
        Piece tm; tm.text = "18:30"; tm.font = t.font; tm.color = p.ink; tm.gapBefore = 4; n.pieces.push_back(tm);
        makeRun(n);
    } else {
        chip(146, tr(S::NotSynced, l), p.status_caution, 2, p.surface);
    }
    Font cap = font(Type::Caption, large_);
    Run ml; ml.top = 170; ml.lineBox = cap.lineBox; ml.mainCss = cap.css; ml.reverse = ar_;
    char a[48], b2[48];
    std::snprintf(a, sizeof a, "%s %d%%", tr(S::Move, l), synced ? m.movePct : 0);
    std::snprintf(b2, sizeof b2, "%s %d%%", tr(S::Load, l), synced ? m.loadPct : 0);
    Piece d1; d1.kind = Piece::Dot; d1.color = p.accent; ml.pieces.push_back(d1);
    Piece t1; t1.text = a; t1.font = cap; t1.color = p.ink_2; t1.gapBefore = 3; t1.rtlText = ar_; ml.pieces.push_back(t1);
    Piece d2; d2.kind = Piece::Dot; d2.color = p.ink_2; d2.gapBefore = 7; ml.pieces.push_back(d2);
    Piece t2; t2.text = b2; t2.font = cap; t2.color = p.ink_2; t2.gapBefore = 3; t2.rtlText = ar_; ml.pieces.push_back(t2);
    makeRun(ml);
}

void Ui::updateFace(const Model& m) {
    if (clock_.pieces.empty()) return;
    const Palette& p = *pal_; Lang l = m.settings.lang;
    bool changed = false;
    char clk[8]; if (m.clock.valid) std::snprintf(clk, sizeof clk, "%02d:%02d", m.clock.hh, m.clock.mm); else std::snprintf(clk, sizeof clk, "--:--");
    if (setText(clock_.pieces[0].obj, clk)) changed = true;
    if (changed) layoutRun(clock_);
    // an invalid clock has no date either (defect D1, 11 Nov): only the battery stays on that line
    char dt[64]; if (m.clock.valid) std::snprintf(dt, sizeof dt, "%s %d %s", weekday(m.clock.weekday, l), m.clock.day, month(m.clock.month, l)); else dt[0] = 0;
    char bt[8]; std::snprintf(bt, sizeof bt, "%d%%", m.battery);
    uint32_t bc = m.battery <= 10 ? p.status_critical : m.battery <= 20 ? p.status_caution : p.ink_2;
    auto& dp = date_.pieces.front(); auto& bp = date_.pieces.back(); changed = false;
    if (setText(dp.obj, dt)) changed = true;
    if (setText(bp.obj, bt)) { lv_obj_set_style_text_color(bp.obj, col(bc), 0); changed = true; }
    if (date_.pieces.size() == 3 && lv_obj_get_style_img_recolor(date_.pieces[1].obj, 0).full != col(bc).full) lv_obj_set_style_img_recolor(date_.pieces[1].obj, col(bc), 0);
    if (changed) layoutRun(date_);
}

// ---------------------------------------------------------------------------------------------------------------- app menu
void Ui::buildMenu(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    auto items = m.menuItems();
    // 5 px gaps (approved 9 Nov): the last row ends at y 194, leaving a 44 px touch area for the "more" hint below it
    const int h = ROW_H + (large_ ? 8 : 0), gap = 5, minW = 132, yMax = 202, off = m.menuScroll;
    int y0 = 36;
    while (chordAt(float(y0), float(y0 + h)) - 6 < 156 && y0 + h / 2 < 120) y0++;   // first row starts where the circle is wide enough
    int y = y0 - off * (h + gap), shown = 0;
    for (MenuId id : items) {
        int top = y, bottom = y + h; y += h + gap;
        if (top < y0 - 1 || bottom > yMax) continue;
        int w = int(std::floor(chordAt(float(top), float(bottom)) - 6));
        if (w < minW) continue;
        shown++;
        int left = int(std::lround(C - w / 2.0));
        bool sel = id == MenuId::ReturnToWorkout;
        lv_obj_t* row = lv_obj_create(root_); lv_obj_remove_style_all(row);
        lv_obj_set_pos(row, left, top); lv_obj_set_size(row, w, h);
        lv_obj_set_style_bg_color(row, col(p.surface), 0); lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0); lv_obj_set_style_radius(row, RADIUS_M, 0);
        if (sel) { lv_obj_set_style_border_color(row, col(p.accent), 0); lv_obj_set_style_border_width(row, 2, 0); lv_obj_set_style_border_opa(row, LV_OPA_COVER, 0); }
        lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);

        // fitting rule (prototype fitText): drop the icon, then the chevron, then the smaller size, then two lines
        Font f = font(Type::Row, large_);
        std::string text = tr(menuText(id), l);
        lv_obj_t* t = label(row, text, f, p.ink, ar_);
        lv_obj_update_layout(t);
        int tw = lv_obj_get_width(t);
        bool icon = true, chev = true, two = false;
        auto avail = [&]() { return w - 28 - (icon ? 30 : 0) - (chev ? 22 : 0); };
        if (tw > avail()) icon = false;
        if (tw > avail()) chev = false;
        if (tw > avail()) { f = font(Type::RowShrink, large_); lv_obj_set_style_text_font(t, f.f, 0); lv_obj_update_layout(t); tw = lv_obj_get_width(t); }
        if (tw > avail()) {
            two = true; int lh = large_ ? 17 : 15;                       // prototype two-line rule: 15 px lines (17 px in Large Text), at most 2
            lv_obj_set_style_text_line_space(t, lh - f.f->line_height, 0);
            lv_obj_set_width(t, avail()); lv_obj_set_height(t, 2 * lh + 1); dotMode(t);
            lv_obj_set_style_text_align(t, ar_ ? LV_TEXT_ALIGN_RIGHT : LV_TEXT_ALIGN_LEFT, 0);
        }
        int textW = two ? avail() : tw;
        int startX = 14 + (icon ? 30 : 0);                        // logical start edge (left in LTR, right in RTL)
        int tx = ar_ ? w - startX - textW : startX;
        int ty = two ? (h - 2 * (large_ ? 17 : 15)) / 2 : labelYFor(baselineOf((h - f.lineBox) / 2, f.lineBox, f.css), f.f);
        lv_obj_set_pos(t, tx, ty);
        if (icon) {
            lv_obj_t* ic = lv_img_create(row); lv_img_set_src(ic, menuIcon(id));
            lv_obj_set_style_img_recolor(ic, col(p.ink_2), 0); lv_obj_set_style_img_recolor_opa(ic, LV_OPA_COVER, 0);
            lv_obj_set_pos(ic, ar_ ? w - 14 - 20 : 14, (h - 20) / 2);
        }
        if (chev) {
            lv_obj_t* cv = lv_img_create(row); lv_img_set_src(cv, ar_ ? &cyv3_ic_chevl_12 : &cyv3_ic_chev_12);
            lv_obj_set_style_img_recolor(cv, col(p.ink_3), 0); lv_obj_set_style_img_recolor_opa(cv, LV_OPA_COVER, 0);
            lv_obj_set_pos(cv, ar_ ? 14 : w - 14 - 12, (h - 12) / 2);
        }
        hit(left, top, w, h, Action::MenuItem, int(id), "menu row");
    }
    int n = int(items.size()), more = n - shown - std::min(off, n);
    if (more > 0) {
        Font cap = font(Type::Caption, large_);
        Run r; r.top = ar_ ? 202 : 205; r.lineBox = cap.lineBox; r.mainCss = cap.css; r.reverse = ar_;
        Piece t; t.text = trf(S::More, l, more); t.font = cap; t.color = p.ink_2; t.rtlText = ar_; r.pieces.push_back(t);
        Piece c; c.kind = Piece::Icon; c.icon = &cyv3_ic_down_11; c.gapBefore = 4; c.iconDrop = 1; c.color = p.ink_2; r.pieces.push_back(c);
        makeRun(r);
        hit(C - 60, 194, 120, 44, Action::MenuMore, 0, "more hint");   // 44 px, below the last row (ends at 193); swipe up scrolls too
    }
    if (n > shown) {                                                  // scroll position: short arc on the trailing edge
        float a0 = ar_ ? 235.f : 55.f, span = 70.f, f0 = float(std::min(off, n - shown)) / n, f1 = f0 + float(shown) / n;
        arc(112, 3, a0, a0 + span, p.line);
        arc(112, 3, a0 + span * f0, a0 + span * std::min(1.f, f1), p.ink_2);
    }
}

// ---------------------------------------------------------------------------------------------------------------- cycling cockpit
void Ui::staticRing() {
    const Palette& p = *pal_;
    arc(110, 6, -135, 135, p.line);
    arc(110, 6, gaugeAngle(Model::TARGET_LO), gaugeAngle(Model::TARGET_HI), p.grade_on, 140);
    for (int z : {100, 200, 300}) {
        float x0, y0, x1, y1; pol(103, gaugeAngle(z), x0, y0); pol(116, gaugeAngle(z), x1, y1);
        line({{lv_coord_t(std::lround(x0)), lv_coord_t(std::lround(y0))}, {lv_coord_t(std::lround(x1)), lv_coord_t(std::lround(y1))}}, 2, p.ink_3);
    }
    arc(110, 4, 145, 215, p.line);
}

namespace {
struct RingCache { const void* pal = nullptr; lv_img_dsc_t dsc{}; void* buf = nullptr; uint32_t size = 0; };
RingCache g_ring;
}  // namespace

bool Ui::ringBackground() {
    if (g_ring.pal != pal_ || !g_ring.buf) {
        lv_obj_t* keep = root_;
        lv_obj_t* scr = lv_obj_create(nullptr);            // detached screen: never shown, only rendered into the buffer
        lv_obj_remove_style_all(scr); lv_obj_set_size(scr, 240, 240);
        lv_obj_set_style_bg_color(scr, col(pal_->bg), 0); lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
        root_ = scr; staticRing(); root_ = keep;
        lv_obj_update_layout(scr);
        uint32_t need = lv_snapshot_buf_size_needed(scr, LV_IMG_CF_TRUE_COLOR);
        if (!g_ring.buf || g_ring.size < need) {
            std::free(g_ring.buf); g_ring.buf = nullptr;
#ifdef CYW_HOST
            g_ring.buf = std::malloc(need);
#else
            g_ring.buf = heap_caps_malloc(need, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);   // 115 KB: external PSRAM
#endif
            g_ring.size = g_ring.buf ? need : 0;
        }
        bool ok = g_ring.buf && lv_snapshot_take_to_buf(scr, LV_IMG_CF_TRUE_COLOR, &g_ring.dsc, g_ring.buf, g_ring.size) == LV_RES_OK;
        lv_obj_del(scr);
        g_ring.pal = ok ? pal_ : nullptr;
        if (!ok) return false;
    }
    ringImg_ = lv_img_create(root_); lv_img_set_src(ringImg_, &g_ring.dsc); lv_obj_set_pos(ringImg_, 0, 0);
    lv_obj_clear_flag(ringImg_, LV_OBJ_FLAG_CLICKABLE); lv_obj_set_user_data(ringImg_, (void*)"background");
    lv_obj_add_event_cb(ringImg_, ringCoverCb, lv_event_code_t(LV_EVENT_COVER_CHECK | LV_EVENT_PREPROCESS), nullptr);
    return true;
}

void Ui::buildCockpit(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    bool focused = m.focused(), keyChip = m.key2Armed;
    if (!ringBackground()) staticRing();
    ivArc_ = nullptr;
    {   // interval progress arc: kept and updated in place
        ivArc_ = lv_arc_create(root_); lv_obj_remove_style_all(ivArc_);
        int outer = 112; lv_obj_set_size(ivArc_, 2 * outer, 2 * outer); lv_obj_set_pos(ivArc_, C - outer, C - outer);
        lv_arc_set_rotation(ivArc_, 270); lv_arc_set_angles(ivArc_, 145, 146);
        lv_obj_set_style_arc_width(ivArc_, 4, LV_PART_INDICATOR); lv_obj_set_style_arc_color(ivArc_, col(p.ink_2), LV_PART_INDICATOR);
        lv_obj_set_style_arc_rounded(ivArc_, true, LV_PART_INDICATOR); lv_obj_clear_flag(ivArc_, LV_OBJ_FLAG_CLICKABLE);
        ringSkip(ivArc_, outer - 4);
    }
    if (m.m.power >= 0) {
        marker_ = lv_obj_create(root_); lv_obj_remove_style_all(marker_); lv_obj_set_size(marker_, 17, 17);
        lv_obj_set_style_radius(marker_, LV_RADIUS_CIRCLE, 0); lv_obj_set_style_bg_color(marker_, col(p.bg), 0); lv_obj_set_style_bg_opa(marker_, LV_OPA_COVER, 0);
        lv_obj_set_style_border_color(marker_, col(p.ink), 0); lv_obj_set_style_border_width(marker_, 3, 0); lv_obj_set_style_border_opa(marker_, LV_OPA_COVER, 0);
        lv_obj_clear_flag(marker_, LV_OBJ_FLAG_CLICKABLE);
    }
    // status line: a chip when something needs attention, otherwise the interval
    if (!m.phoneLinked) chip(34, tr(S::PhoneLost, l), p.status_critical, 1, p.surface);
    else if (m.wk == WkState::Paused) chip(34, tr(S::Paused, l), p.status_caution, 1, p.surface);
    else {
        Font lbl = font(Type::Label, large_);
        interval_ = Run{}; interval_.top = 38; interval_.lineBox = lbl.lineBox; interval_.mainCss = lbl.css; interval_.reverse = ar_;
        char iv[48]; std::snprintf(iv, sizeof iv, "%s %d/%d \xC2\xB7", tr(S::Interval, l), m.interval, Model::INTERVALS);
        Piece a; a.text = iv; a.font = lbl; a.color = p.ink_2; a.rtlText = ar_; interval_.pieces.push_back(a);
        Piece t; t.text = fmtTime(m.remainS); t.font = lbl; t.color = p.ink; t.gapBefore = 4; interval_.pieces.push_back(t);
        makeRun(interval_);
    }
    // lead metric + unit (fit 58 → 44 → 32 px); Bike Mode: 76 → 58 → 44 px, unit moves to the label line (prototype bike)
    bool bike = m.bike();
    lead_ = Run{}; lead_.top = bike ? 56 : 58; lead_.lineBox = bike ? 76 : 58; lead_.mainCss = lead_.lineBox;
    Piece v; v.text = "0"; v.font = font(bike ? Type::Display76 : Type::Display58, false); v.color = p.ink; lead_.pieces.push_back(v);
    Piece u; u.text = bike ? "" : "W"; u.font = unitFor(58); u.color = p.ink_2; u.gapBefore = bike ? 0 : 4; lead_.pieces.push_back(u);
    makeRun(lead_);
    if (bike) {
        Font lbl = font(Type::Label, large_);
        bikeInfo_ = Run{}; bikeInfo_.top = 134; bikeInfo_.lineBox = lbl.lineBox; bikeInfo_.mainCss = lbl.css; bikeInfo_.reverse = ar_;
        Piece a; a.text = "WATTS"; a.font = lbl; a.color = p.ink_2; a.rtlText = ar_; bikeInfo_.pieces.push_back(a);
        if (!focused) { Piece b; b.text = "0"; b.font = lbl; b.color = p.ink; b.gapBefore = 4; bikeInfo_.pieces.push_back(b); }
        makeRun(bikeInfo_);
    } else if (!focused) {
        Font cap = font(Type::Caption, large_);
        auto tile = [&](Run& r, int cx, S name) {
            r = Run{}; r.top = 116; r.lineBox = 28; r.mainCss = 24; r.centerX = cx;
            Piece n; n.text = "0"; n.font = font(Type::Metric24, false); n.color = p.ink; r.pieces.push_back(n);
            Piece un; un.text = "bpm"; un.font = font(Type::Unit, false); un.color = p.ink_2; un.gapBefore = 4; r.pieces.push_back(un);
            makeRun(r);
            if (keyChip) return;                                         // the Key 2 chip covers this line (as in the prototype)
            Run c; c.top = 144; c.lineBox = cap.lineBox; c.mainCss = cap.css; c.centerX = cx;
            Piece t; t.text = tr(name, l); t.font = cap; t.color = p.ink_2; t.rtlText = ar_; c.pieces.push_back(t);
            makeRun(c);
            auto cg = groups_.back(); groups_.pop_back(); groups_.back().insert(groups_.back().end(), cg.begin(), cg.end());   // number, unit and caption: one tile
        };
        tile(hrTile_, C - 42, S::HeartRate); tile(cadTile_, C + 42, S::Cadence);
    }
    cmdTop_ = bike ? 152 : focused ? 130 : 160;
    Font f13 = font(Type::Small13, false); f13.tracked = true;
    cmd_ = label(root_, "", f13, p.ink_2, ar_);
    if (keyChip && cmdTop_ + 16 > keyChipTop() - 6 && cmdTop_ < keyChipTop() + 22 + 6) lv_obj_add_flag(cmd_, LV_OBJ_FLAG_HIDDEN);   // under the Key 2 chip
    bool paused = m.wk == WkState::Paused;
    int btop = bike ? 170 : large_ ? 168 : (paused ? 180 : 182);
    auto btn = [&](const std::string& t, int kind, Action a) { if (bike) bikeButton(btop, t, kind, a); else button(btop, t, kind, a); };
    if (paused) btn(tr(m.pending == Cmd::Resume ? S::Resuming : S::Resume, l), m.pending == Cmd::Resume ? 2 : 1, Action::Resume);
    else btn(tr(m.pending == Cmd::Pause ? S::Pausing : S::Pause, l), m.pending == Cmd::Pause ? 2 : 0, Action::Pause);
    updateCockpit(m);
}

void Ui::setLead(const Model& m) {
    const Palette& p = *pal_;
    int value = m.m.power >= 0 ? m.m.power : m.m.hr;
    bool bike = m.bike();
    const char* unit = bike ? "" : m.m.power >= 0 ? "W" : m.m.hr >= 0 ? "bpm" : "W";
    uint32_t color = p.ink;
    if (m.m.power >= 0) {
        auto g = Model::gradeOf(m.m.power);
        color = g == Model::Grade::On ? p.grade_on : g == Model::Grade::Far ? p.grade_far : p.grade_adjust;
    } else if (m.m.hr < 0) color = p.ink_3;
    std::string text = fmtV(value);
    auto& vp = lead_.pieces[0]; auto& up = lead_.pieces[1];
    // tabular figures: same digit count = same width, so only the text changes (LVGL redraws just that label)
    std::string before = src_[vp.obj];
    setText(vp.obj, text);
    bool unitChanged = setText(up.obj, unit);
    if (lv_obj_get_style_text_color(vp.obj, 0).full != col(color).full) lv_obj_set_style_text_color(vp.obj, col(color), 0);
    if (leadPx_ && !unitChanged && before.size() == text.size()) return;
    // fit: the whole line box must sit inside the safe circle (prototype fitText, conservative rule)
    leadPx_ = 0;
    static const int WRIST[] = {58, 44, 32}, BIKE[] = {76, 58, 44};
    for (int px : bike ? BIKE : WRIST) {
        Font vf = font(px == 76 ? Type::Display76 : px == 58 ? Type::Display58 : px == 44 ? Type::Display44 : Type::Display32, false), uf = unitFor(px);
        lv_obj_set_style_text_font(vp.obj, vf.f, 0); lv_obj_set_style_text_font(up.obj, uf.f, 0);
        vp.font = vf; up.font = uf; lead_.lineBox = px; lead_.mainCss = px;
        layoutRun(lead_);
        float half = std::min(hw(float(lead_.top)), hw(float(lead_.top + px)));
        if (lead_.width / 2.f <= half + 0.5f) { leadPx_ = px; break; }
    }
}

void Ui::setTile(Run& r, int v, const char* unit) {
    std::string s = fmtV(v);
    bool changed = false;
    if (setText(r.pieces[0].obj, s)) changed = true;
    if (setText(r.pieces[1].obj, unit)) changed = true;
    if (changed) layoutRun(r);
}

void Ui::setCommand(const Model& m) {
    const Palette& p = *pal_;
    auto c = m.command();
    uint32_t color = c.color == Model::Command::On ? p.grade_on : c.color == Model::Command::Adjust ? p.grade_adjust
                   : c.color == Model::Command::Far ? p.grade_far : c.color == Model::Command::Crit ? p.status_critical : p.ink_2;
    if (setText(cmd_, c.text)) {
        lv_obj_update_layout(cmd_);
        Font f = font(Type::Small13, false);
        int lb = large_ ? 16 : 14;
        lv_obj_set_pos(cmd_, C - lv_obj_get_width(cmd_) / 2, labelYFor(baselineOf(cmdTop_, lb, f.css), f.f));
    }
    if (lv_obj_get_style_text_color(cmd_, 0).full != col(color).full) lv_obj_set_style_text_color(cmd_, col(color), 0);
}

void Ui::placeMarker(const Model& m) {
    if (!marker_ || m.m.power < 0) return;
    float x, y; pol(110, gaugeAngle(float(m.m.power)), x, y);
    lv_coord_t nx = lv_coord_t(std::lround(x - 8.5f)), ny = lv_coord_t(std::lround(y - 8.5f));
    if (lv_obj_get_x(marker_) != nx || lv_obj_get_y(marker_) != ny) lv_obj_set_pos(marker_, nx, ny);
}

void Ui::updateCockpit(const Model& m) {
    if (lead_.pieces.empty()) return;
    if (!interval_.pieces.empty()) {
        std::string t = fmtTime(m.remainS);
        char iv[48]; std::snprintf(iv, sizeof iv, "%s %d/%d \xC2\xB7", tr(S::Interval, m.settings.lang), m.interval, Model::INTERVALS);
        bool changed = false;
        if (setText(interval_.pieces[1].obj, t)) changed = true;
        if (setText(interval_.pieces[0].obj, iv)) changed = true;
        if (changed) layoutRun(interval_);
    }
    if (ivArc_) {
        float f = 1.f - float(m.remainS) / float(Model::INTERVAL_S);
        uint16_t end = uint16_t(std::lround(145 + 70 * std::max(0.f, std::min(1.f, f))));
        if (lv_arc_get_angle_end(ivArc_) != end) lv_arc_set_angles(ivArc_, 145, std::max<uint16_t>(146, end));
    }
    setLead(m);
    if (!hrTile_.pieces.empty()) { setTile(hrTile_, m.m.hr, "bpm"); setTile(cadTile_, m.m.cadence, "rpm"); }
    if (!bikeInfo_.pieces.empty()) {          // 'WATTS · 152 bpm' (power lead) or 'BPM · 92 rpm' (heart-rate lead)
        bool pw = m.m.power >= 0; bool changed = setText(bikeInfo_.pieces[0].obj, pw ? (ar_ ? std::string(tr(S::Watts, m.settings.lang)) + " \xC2\xB7" : "WATTS \xC2\xB7") : "BPM \xC2\xB7");
        if (bikeInfo_.pieces.size() == 1) changed = setText(bikeInfo_.pieces[0].obj, pw ? tr(S::Watts, m.settings.lang) : "BPM") || changed;
        else changed = setText(bikeInfo_.pieces[1].obj, pw ? fmtV(m.m.hr) + " bpm" : fmtV(m.m.cadence) + " rpm") || changed;
        if (changed) layoutRun(bikeInfo_);
    }
    setCommand(m);
    placeMarker(m);
}

// ---------------------------------------------------------------------------------------------------------------- overlays
/// Hides text and icons that an overlay (banner, toast, Key 2 chip) would partly cover, so no half-covered numbers or
/// letter fragments show around it. They reappear when the overlay goes (the screen is rebuilt then).
void Ui::hideUnder(lv_obj_t* overlay, int margin) {
    lv_obj_update_layout(root_);
    lv_area_t o; lv_obj_get_coords(overlay, &o); o.x1 -= margin; o.y1 -= margin; o.x2 += margin; o.y2 += margin;
    for (uint32_t i = 0; i < lv_obj_get_child_cnt(root_); i++) {
        lv_obj_t* c = lv_obj_get_child(root_, int32_t(i));
        if (c == overlay || c == ringImg_ || !(lv_obj_check_type(c, &lv_label_class) || lv_obj_check_type(c, &lv_img_class))) continue;
        lv_area_t a; lv_obj_get_coords(c, &a);
        if (std::min(a.x2, o.x2) >= std::max(a.x1, o.x1) && std::min(a.y2, o.y2) >= std::max(a.y1, o.y1)) lv_obj_add_flag(c, LV_OBJ_FLAG_HIDDEN);
    }
    for (auto& g : groups_) {                      // never leave half a group behind (e.g. "rpm" without its number)
        bool any = false; for (auto* o : g) any = any || lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN);
        if (any) for (auto* o : g) lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    }
}

void Ui::buildOverlays(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    // approved text 'Locked · hold Key 1'; prototype y 200 puts the 157 px chip off the round glass, so it sits at y 178 (the
    // widest point that keeps it whole) and hides the line under it while the screen is locked
    if (m.locked) { lv_obj_t* k = chip(178, tr(S::LockedHoldKey1, l), p.ink_2, 0, p.surface); lv_obj_set_user_data(k, (void*)"overlay"); hideUnder(k, 4); }
    if (m.key2Armed && m.screen == Screen::Cockpit) { lv_obj_t* k = chip(keyChipTop(), tr(S::KeyLapPressAgain, l), p.status_info, 0, p.surface, 6); lv_obj_set_user_data(k, (void*)"overlay"); hideUnder(k, 6); }
    if (m.toast.kind == Toast::None) return;
    if (m.toast.hasSub) {                                             // banner: result + reason, tap to dismiss
        // on the cockpit the banner sits wholly above the Pause/Resume button, so both stay visible and tappable (9 Nov fix)
        bool ck = m.screen == Screen::Cockpit;
        int top = ck ? (large_ ? 112 : 130) : 142, w = 166, h = 48;
        lv_obj_t* b = lv_obj_create(root_); lv_obj_remove_style_all(b);
        lv_obj_set_style_bg_color(b, col(p.surface_2), 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0); lv_obj_set_style_radius(b, RADIUS_M, 0);
        lv_obj_clear_flag(b, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE); lv_obj_set_user_data(b, (void*)"overlay");
        Font t13 = font(Type::Small13, false), c11 = font(Type::Caption, false);
        lv_obj_t* t = label(b, tr(m.toast.text, l), t13, m.toast.kind == Toast::Crit ? p.status_critical : m.toast.kind == Toast::Info ? p.status_info : p.ink, ar_);
        lv_obj_t* s = label(b, tr(m.toast.sub, l), c11, p.ink_2, ar_);
        for (lv_obj_t* o : {t, s}) dotMode(o);
        lv_obj_update_layout(b);
        // approved width 166 px; widened only as far as the circle allows when the reason is longer (no cut-off text)
        lv_point_t ts, ss;   // full single-line widths (the labels are already in ellipsis mode)
        lv_txt_get_size(&ts, lv_label_get_text(t), t13.f, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
        lv_txt_get_size(&ss, lv_label_get_text(s), c11.f, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
        auto glass = [&](float y) { float d = std::fabs(y - C); return d >= 118.f ? 0.f : 2.f * std::sqrt(118.f * 118.f - d * d); };
        int need = std::max<int>(ts.x, ss.x) + 24 + 2, maxW = int(std::min(glass(float(top)), glass(float(top + h)))) - 6;
        w = std::max(w, std::min(need, maxW));
        lv_obj_set_pos(b, C - w / 2, top); lv_obj_set_size(b, w, h);
        int tw = std::min<int>(w - 24, ts.x + 2), sw = std::min<int>(w - 24, ss.x + 2);
        lv_obj_set_width(t, tw); lv_obj_set_width(s, sw);
        lv_obj_set_pos(t, (w - tw) / 2, labelYFor(baselineOf(9, 16, 13), t13.f));
        lv_obj_set_pos(s, (w - sw) / 2, labelYFor(baselineOf(25, 14, 11), c11.f));
        hit(C - w / 2, top, w, h, Action::DismissToast, 0, "banner");
        hideUnder(b, 2);
        return;
    }
    bool ok = m.toast.kind == Toast::Ok;                              // short result: pill with a check or a warning sign
    Font f = font(Type::Small13, false);
    lv_obj_t* box = lv_obj_create(root_); lv_obj_remove_style_all(box);
    lv_obj_set_style_bg_color(box, col(p.surface_2), 0); lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0); lv_obj_set_style_radius(box, LV_RADIUS_CIRCLE, 0);
    lv_obj_clear_flag(box, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE); lv_obj_set_user_data(box, (void*)"overlay");
    lv_obj_t* t = label(box, tr(m.toast.text, l), f, p.ink, ar_);
    lv_obj_t* ic = lv_img_create(box); lv_img_set_src(ic, ok ? &cyv3_ic_check_15 : &cyv3_ic_warn_15);
    lv_obj_set_style_img_recolor(ic, col(ok ? p.status_ok : p.status_critical), 0); lv_obj_set_style_img_recolor_opa(ic, LV_OPA_COVER, 0);
    lv_obj_update_layout(box);
    int tw = lv_obj_get_width(t), w = 13 + 15 + 7 + tw + 13, h = 32;
    int toastTop = m.screen == Screen::Cockpit ? (large_ ? 128 : 140) : 184;   // cockpit: above the button, never over it
    lv_obj_set_size(box, w, h); lv_obj_set_pos(box, C - w / 2, toastTop);
    lv_obj_set_pos(ic, ar_ ? w - 13 - 15 : 13, (h - 15) / 2);
    lv_obj_set_pos(t, ar_ ? 13 : 13 + 15 + 7, labelYFor(baselineOf((h - 16) / 2, 16, 13), f.f));
    hideUnder(box, 2);
}


// ---------------------------------------------------------------------------------------------------------------- Stage 1.3
// Face neighbourhood of the approved prototype (Deliverable D v3.3, src/screens1.js): Today, Week strip, Quick Settings,
// the Health / Coach / Activity glance widgets, and an explicit "not in this release" page. Without iPhone data every
// screen shows its honest empty / not-synced state; demo values appear only when the simulated iPhone is switched on.
namespace {
std::string upperAscii(std::string s) { for (char& c : s) if (c >= 'a' && c <= 'z') c = char(c - 32); return s; }
const lv_img_dsc_t* emptyIcon(MenuId id) {
    switch (id) {
        case MenuId::Health: return &cyv3_ic_heart_28;
        case MenuId::Coach: return &cyv3_ic_coach_28;
        case MenuId::History: return &cyv3_ic_hist_28;
        case MenuId::Utilities: return &cyv3_ic_util_28;
        case MenuId::Settings: return &cyv3_ic_gear_28;
        default: return &cyv3_ic_today_28;
    }
}
/// "Sun 8 Nov" (caption style) — or nothing when the clock is not valid.
std::string dateCaption(const Model& m) {
    if (!m.clock.valid) return "";
    Lang l = m.settings.lang;
    std::string wd = weekday(m.clock.weekday, l), mo = month(m.clock.month, l);
    if (l == Lang::En) { for (size_t i = 1; i < wd.size(); i++) wd[i] = char(wd[i] + 32); for (size_t i = 1; i < mo.size(); i++) mo[i] = char(mo[i] + 32); }
    char b[64]; std::snprintf(b, sizeof b, "%s %d %s", wd.c_str(), m.clock.day, mo.c_str()); return b;
}
}  // namespace

lv_obj_t* Ui::textLine(int top, const std::string& s, const Font& f, uint32_t color, int centerX) {
    lv_obj_t* l = label(root_, s, f, color, ar_ && hasArabic(s));
    lv_obj_update_layout(l);
    lv_obj_set_pos(l, centerX - lv_obj_get_width(l) / 2, labelYFor(baselineOf(top, f.lineBox, f.css), f.f));
    return l;
}

lv_obj_t* Ui::paragraph(int top, int left, int width, const std::string& s, const Font& f, int lineH, uint32_t color, bool center) {
    lv_obj_t* l = label(root_, s, f, color, ar_);
    lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(l, width);
    lv_obj_set_style_text_line_space(l, lineH - f.f->line_height, 0);
    lv_obj_set_style_text_align(l, center ? LV_TEXT_ALIGN_CENTER : (ar_ ? LV_TEXT_ALIGN_RIGHT : LV_TEXT_ALIGN_LEFT), 0);
    lv_obj_set_pos(l, left, labelYFor(baselineOf(top, lineH, f.css), f.f));
    return l;
}

void Ui::icon(int top, const lv_img_dsc_t* ic, uint32_t color, int centerX) {
    lv_obj_t* i = lv_img_create(root_); lv_img_set_src(i, ic);
    lv_obj_set_style_img_recolor(i, col(color), 0); lv_obj_set_style_img_recolor_opa(i, LV_OPA_COVER, 0);
    lv_obj_set_pos(i, centerX - int(ic->header.w) / 2, top); lv_obj_clear_flag(i, LV_OBJ_FLAG_CLICKABLE);
}

void Ui::header(const std::string& title, const std::string& sub) {
    Font lbl = font(Type::Label, large_), cap = font(Type::Caption, large_);
    int t = sub.empty() ? (large_ ? 26 : 24) : (large_ ? (ar_ ? 26 : 27) : ar_ ? 22 : 23);
    textLine(t, title, lbl, pal_->ink_2);
    // Arabic month and weekday names carry tall letters (ل ك أ) that reached the title by 1 px in the date sweep: 1 px more air
    if (!sub.empty()) textLine(large_ ? 44 : ar_ ? 39 : 38, sub, cap, pal_->ink_2);
}

void Ui::pageDots(int n, int index, int top) {
    int total = 0; for (int k = 0; k < n; k++) total += (k == index ? 12 : 5) + (k ? 5 : 0);
    int x = C - total / 2;
    for (int k = 0; k < n; k++) {
        int i = ar_ ? n - 1 - k : k;                 // right-to-left: the first page is on the right
        int w = i == index ? 12 : 5;
        lv_obj_t* d = lv_obj_create(root_); lv_obj_remove_style_all(d);
        lv_obj_set_size(d, w, 5); lv_obj_set_pos(d, x, top); lv_obj_set_style_radius(d, i == index ? 3 : LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_bg_color(d, col(i == index ? pal_->ink : pal_->ink_3), 0); lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
        lv_obj_clear_flag(d, LV_OBJ_FLAG_CLICKABLE);
        x += w + 5;
    }
}

void Ui::emptyState(const lv_img_dsc_t* ic, const std::string& title, const std::string& sub) {
    icon(70, ic, pal_->ink_3);
    textLine(108, title, font(Type::BodyStrong, large_), pal_->ink);
    Font cap = font(Type::Caption, large_);
    paragraph(134, 46, 148, sub, cap, cap.lineBox, pal_->ink_2, true);
}

lv_obj_t* Ui::bikeButton(int top, const std::string& text, int kind, Action a) {
    Font f = font(Type::BikeButton, false);
    int h = BUTTON_H_BIKE, minW = 96;
    uint32_t bg = kind == 1 ? pal_->accent : pal_->surface_2, fg = kind == 1 ? pal_->on_accent : kind == 2 ? pal_->status_info : pal_->ink;
    lv_obj_t* b = lv_obj_create(root_); lv_obj_remove_style_all(b);
    lv_obj_set_style_bg_color(b, col(bg), 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0); lv_obj_set_style_radius(b, LV_RADIUS_CIRCLE, 0);
    lv_obj_clear_flag(b, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t* t = label(b, text, f, fg, ar_);
    lv_obj_update_layout(t);
    int w = std::max(minW, int(lv_obj_get_width(t)) + 2 * SPACE_XL);
    lv_obj_set_size(b, w, h); lv_obj_set_pos(b, C - w / 2, top);
    lv_obj_set_pos(t, (w - lv_obj_get_width(t)) / 2, labelYFor(baselineOf((h - f.lineBox) / 2, f.lineBox, f.css), f.f));
    if (kind != 2) hit(C - w / 2, top, w, h, a, 0, "button");
    return b;
}

// ---- Today (prototype def('today')) ----
void Ui::buildToday(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    header(tr(S::TodayHdr, l), dateCaption(m));
    if (!m.synced) {                                  // no plan from the iPhone: say so, offer nothing to start
        emptyState(&cyv3_ic_today_28, tr(S::NoPlanTitle, l), tr(S::NoPlanSub, l));
    } else {
        icon(ar_ || large_ ? 61 : 58, &cyv3_ic_bike_22, p.ink_2);   // Arabic / Large Text date caption reaches y 59
        Font tf = font(Type::Title, large_);
        lv_obj_t* t = textLine(90, tr(S::PlanName, l), tf, p.ink);
        for (Type ty : {Type::Title18, Type::Title16}) {   // shrink until the title fits the circle at that height
            lv_obj_update_layout(t);
            if (lv_obj_get_width(t) <= int(chordAt(90.f, 90.f + tf.lineBox)) - 12) break;
            lv_obj_del(t); tf = font(ty, false); t = textLine(90, tr(S::PlanName, l), tf, p.ink);
        }
        Font body = font(Type::Body, large_);
        textLine(118, trds(S::PlanSub, l, 60, "3 \xC3\x97 12"), body, p.ink_2);
        Font lbl = font(Type::Label, large_);
        Run r; r.top = 140; r.lineBox = lbl.lineBox; r.mainCss = lbl.css; r.reverse = ar_;
        Piece a; a.text = tr(S::Target, l); a.font = lbl; a.color = p.ink_2; a.rtlText = ar_; r.pieces.push_back(a);
        Piece v; v.text = "235\xE2\x80\x93" "255 W"; v.font = lbl; v.color = p.ink; v.gapBefore = 5; r.pieces.push_back(v);
        makeRun(r);
        button(large_ ? 156 : 162, tr(S::Start, l), 1, Action::StartPlan);
    }
    // "⌄ Week" link at y 207 (44 px touch area); swipe up does the same
    Font cap = font(Type::Caption, large_);
    Run w; w.top = 207; w.lineBox = cap.lineBox; w.mainCss = cap.css; w.reverse = ar_;
    Piece c; c.kind = Piece::Icon; c.icon = &cyv3_ic_down_11; c.iconDrop = 1; c.color = p.ink_2; w.pieces.push_back(c);
    Piece t2; t2.text = tr(S::WeekLink, l); t2.font = cap; t2.color = p.ink_2; t2.gapBefore = 4; t2.rtlText = ar_; w.pieces.push_back(t2);
    makeRun(w);
    // 44 px touch area under the content (as the menu's "more" hint); with a Start button above it there is no room for one
    // (the button ends at y 206), so the week strip is reached by swiping up — the prototype's gesture for it
    if (!m.synced) hit(C - 60, 194, 120, 44, Action::Go, int(Screen::Week), "week link");
}

void Ui::updateToday(const Model&) {}

// ---- Week strip (prototype def('today-week')) ----
void Ui::buildWeek(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    header(tr(S::WeekHdr, l), "");
    static const char* EN[] = {"M", "T", "W", "T", "F", "S", "S"};
    static const char* AR[] = {"ن", "ث", "ر", "خ", "ج", "س", "ح"};
    static const char ST[] = {'d', 'r', 'm', 'd', 'r', 'd', 'p'};    // demo week: done, rest, missed, plan
    int today = m.clock.valid ? (m.clock.weekday + 6) % 7 : -1;   // Monday first
    Font f = font(Type::Chip, false);
    for (int i = 0; i < 7; i++) {
        int x = ar_ ? 30 + (6 - i) * 30 : 30 + i * 30;                // right-to-left: Monday on the right
        lv_obj_t* t = label(root_, (ar_ ? AR : EN)[i], f, i == today ? p.ink : p.ink_2, ar_);
        lv_obj_set_style_text_letter_space(t, 0, 0);
        lv_obj_update_layout(t); lv_obj_set_pos(t, x - lv_obj_get_width(t) / 2, labelYFor(92, f.f));
        char st = m.synced ? ST[i] : 'r';                              // without iPhone data no day has a status
        if (st == 'd') {
            lv_obj_t* d = lv_obj_create(root_); lv_obj_remove_style_all(d); lv_obj_set_size(d, 18, 18); lv_obj_set_pos(d, x - 9, 103);
            lv_obj_set_style_radius(d, LV_RADIUS_CIRCLE, 0); lv_obj_set_style_bg_color(d, col(p.ink), 0); lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
        } else if (st == 'p') {
            lv_obj_t* d = lv_obj_create(root_); lv_obj_remove_style_all(d); lv_obj_set_size(d, 19, 19); lv_obj_set_pos(d, x - 9, 103);   // r 8 + 2.5 stroke
            lv_obj_set_style_radius(d, LV_RADIUS_CIRCLE, 0); lv_obj_set_style_border_color(d, col(p.accent), 0); lv_obj_set_style_border_width(d, 3, 0); lv_obj_set_style_border_opa(d, LV_OPA_COVER, 0);
        } else if (st == 'm') {                                        // dashed ring: six short arcs
            for (int k = 0; k < 6; k++) {
                lv_obj_t* a = lv_arc_create(root_); lv_obj_remove_style_all(a); lv_obj_set_size(a, 18, 18); lv_obj_set_pos(a, x - 9, 103);
                lv_arc_set_angles(a, uint16_t(k * 60), uint16_t(k * 60 + 30));
                lv_obj_set_style_arc_width(a, 2, LV_PART_INDICATOR); lv_obj_set_style_arc_color(a, col(p.status_caution), LV_PART_INDICATOR);
                lv_obj_clear_flag(a, LV_OBJ_FLAG_CLICKABLE);
            }
        } else line({{lv_coord_t(x - 5), 112}, {lv_coord_t(x + 5), 112}}, 2, p.ink_3);
        if (i == today) line({{lv_coord_t(x - 8), 128}, {lv_coord_t(x + 8), 128}}, 2, p.ink);
    }
    Font body = font(Type::Body, large_), cap = font(Type::Caption, large_);
    if (!m.synced) { textLine(148, tr(S::PlanOneOnIphone, l), body, p.ink_2); return; }
    textLine(144, trf(S::SessionsDone, l, 3, 4), body, p.ink);
    textLine(168, tr(S::MissedWed, l), cap, p.status_caution);
    textLine(186, tr(S::IphoneAdjusts, l), cap, p.ink_2);
}

// ---- Quick Settings (prototype def('qs'): rows from y 56, values on the trailing edge) ----
void Ui::buildQuick(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    char bat[8]; std::snprintf(bat, sizeof bat, "%d%%", m.battery);
    header(tr(S::QuickSettings, l), bat);
    static const S THEMES[] = {S::ThObsidian, S::ThArctic, S::ThOcean, S::ThForest, S::ThSandstone, S::ThContrast};
    static const S MODES[] = {S::Wrist, S::Bike, S::Gym};
    struct Item { S label; const lv_img_dsc_t* ic; std::string val; };
    char br[8]; std::snprintf(br, sizeof br, "%d%%", m.settings.brightness);
    std::vector<Item> items = {
        {S::Brightness, &cyv3_ic_sun_20, br}, {S::Theme, &cyv3_ic_palette_20, tr(THEMES[int(m.settings.theme)], l)},
        {S::Dnd, &cyv3_ic_moon_20, tr(m.settings.dnd ? S::On : S::Off, l)}, {S::Mode, &cyv3_ic_bike_20, tr(MODES[int(m.settings.mode)], l)},
        {S::ScreenLock, &cyv3_ic_lock_20, ""}};
    const int h = ROW_H + (large_ ? 8 : 0), gap = 6, minW = 132, yMax = 202, off = m.qsScroll;
    int y0 = 56 + (large_ ? 6 : 0);
    while (chordAt(float(y0), float(y0 + h)) - 6 < 156 && y0 + h / 2 < 120) y0++;
    int y = y0 - off * (h + gap), shown = 0, n = int(items.size());
    for (int idx = 0; idx < n; idx++) {
        const Item& it = items[idx];
        int top = y, bottom = y + h; y += h + gap;
        if (top < y0 - 1 || bottom > yMax) continue;
        int w = int(std::floor(chordAt(float(top), float(bottom)) - 6));
        if (w < minW) continue;
        shown++;
        int left = int(std::lround(C - w / 2.0));
        lv_obj_t* row = lv_obj_create(root_); lv_obj_remove_style_all(row);
        lv_obj_set_pos(row, left, top); lv_obj_set_size(row, w, h);
        lv_obj_set_style_bg_color(row, col(p.surface), 0); lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0); lv_obj_set_style_radius(row, RADIUS_M, 0);
        lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
        Font f = font(Type::Row, large_);
        bool hasVal = !it.val.empty(), sub = hasVal && large_;          // Large Text: the value moves under the label
        lv_obj_t* ic = lv_img_create(row); lv_img_set_src(ic, it.ic);
        lv_obj_set_style_img_recolor(ic, col(p.ink_2), 0); lv_obj_set_style_img_recolor_opa(ic, LV_OPA_COVER, 0);
        lv_obj_set_pos(ic, ar_ ? w - 14 - 20 : 14, (h - 20) / 2);
        int startX = 14 + 30;
        lv_obj_t* t = label(row, tr(it.label, l), f, p.ink, ar_);
        lv_obj_update_layout(t);
        int valW = 0; lv_obj_t* v = nullptr;
        if (hasVal) {
            Font vf = sub ? font(Type::Caption, true) : (large_ ? Font{&cyv3_inter600_15, 15, 18, false} : Font{&cyv3_inter600_13, 13, 16, false});
            v = label(row, it.val, vf, p.ink_2, ar_); lv_obj_update_layout(v); valW = sub ? 0 : lv_obj_get_width(v);
            if (sub) {
                int lt = (h - 20 - 15) / 2;
                lv_obj_set_pos(t, ar_ ? w - startX - lv_obj_get_width(t) : startX, labelYFor(baselineOf(lt, 20, f.css), f.f));
                lv_obj_set_pos(v, ar_ ? w - startX - lv_obj_get_width(v) : startX, labelYFor(baselineOf(lt + 20, 15, vf.css), vf.f));
            } else {
                lv_obj_set_pos(v, ar_ ? 14 : w - 14 - valW, labelYFor(baselineOf((h - vf.lineBox) / 2, vf.lineBox, vf.css), vf.f));
            }
        }
        if (!sub) {
            int avail = w - startX - 14 - (hasVal ? valW + 10 : 22);
            if (lv_obj_get_width(t) > avail) { lv_obj_set_width(t, avail); dotMode(t); }
            int tw = std::min<int>(lv_obj_get_width(t), avail);
            lv_obj_set_pos(t, ar_ ? w - startX - tw : startX, labelYFor(baselineOf((h - f.lineBox) / 2, f.lineBox, f.css), f.f));
        }
        if (!hasVal) {                                   // Screen lock: an action row with a chevron
            lv_obj_t* cv = lv_img_create(row); lv_img_set_src(cv, ar_ ? &cyv3_ic_chevl_12 : &cyv3_ic_chev_12);
            lv_obj_set_style_img_recolor(cv, col(p.ink_3), 0); lv_obj_set_style_img_recolor_opa(cv, LV_OPA_COVER, 0);
            lv_obj_set_pos(cv, ar_ ? 14 : w - 14 - 12, (h - 12) / 2);
        }
        hit(left, top, w, h, Action::QsRow, idx, "quick settings row");
    }
    int more = n - shown - std::min(off, n);
    if (more > 0) {
        Font cap = font(Type::Caption, large_);
        Run r; r.top = ar_ ? 202 : 205; r.lineBox = cap.lineBox; r.mainCss = cap.css; r.reverse = ar_;
        Piece t; t.text = trf(S::More, l, more); t.font = cap; t.color = p.ink_2; t.rtlText = ar_; r.pieces.push_back(t);
        Piece c; c.kind = Piece::Icon; c.icon = &cyv3_ic_down_11; c.gapBefore = 4; c.iconDrop = 1; c.color = p.ink_2; r.pieces.push_back(c);
        makeRun(r);
        hit(C - 60, 194, 120, 44, Action::QsMore, 0, "more hint");
    }
    if (n > shown) {
        float a0 = ar_ ? 235.f : 55.f, span = 70.f, f0 = float(std::min(off, n - shown)) / n, f1 = f0 + float(shown) / n;
        arc(112, 3, a0, a0 + span, p.line);
        arc(112, 3, a0 + span * f0, a0 + span * std::min(1.f, f1), p.ink_2);
    }
}

// ---- glance widgets (prototype w-health, w-coach, w-activity; page dots 4: face = 0) ----
void Ui::buildWHealth(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    header(tr(S::HealthHdr, l), "");
    icon(54, &cyv3_ic_heart_22, p.ink_2);
    // no heart-rate source on this watch yet (Polar link is Stage 2b/4): the value is a dash, the reason is shown
    lead_ = Run{}; lead_.top = 78; lead_.lineBox = 58; lead_.mainCss = 58;
    Piece v; v.text = "\xE2\x80\x94"; v.font = font(Type::Display58, false); v.color = p.ink_3; lead_.pieces.push_back(v);
    Piece u; u.text = "bpm"; u.font = unitFor(58); u.color = p.ink_2; u.gapBefore = 4; lead_.pieces.push_back(u);
    makeRun(lead_);
    hit(C - 70, 54, 140, 84, Action::MenuItem, int(MenuId::Health), "health");
    Font cap = font(Type::Caption, large_);
    textLine(140, tr(m.synced ? S::WaitingHr : S::NotSynced, l), cap, p.ink_2);
    if (!large_) {
        auto tile = [&](int cx, S name, const char* unit) {
            Run r; r.top = 162; r.lineBox = 28; r.mainCss = 24; r.centerX = cx;
            Piece n; n.text = "\xE2\x80\x94"; n.font = font(Type::Metric24, false); n.color = p.ink; r.pieces.push_back(n);
            Piece un; un.text = unit; un.font = font(Type::Unit, false); un.color = p.ink_2; un.gapBefore = 4; r.pieces.push_back(un);
            makeRun(r);
            Run c; c.top = 190; c.lineBox = cap.lineBox; c.mainCss = cap.css; c.centerX = cx;
            Piece t; t.text = tr(name, l); t.font = cap; t.color = p.ink_2; t.rtlText = ar_; c.pieces.push_back(t);
            makeRun(c);
        };
        tile(ar_ ? C + 44 : C - 44, S::RestingHr, "bpm"); tile(ar_ ? C - 44 : C + 44, S::Hrv, "ms");
    }
    pageDots(4, 1, 222);
}

void Ui::buildWCoach(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    header(tr(S::CoachHdr, l), "");
    Font b = font(Type::BodyMedium, large_);
    paragraph(58, 31, 178, tr(m.synced ? S::CoachNote : S::NoNote, l), b, large_ ? 22 : 20, p.ink, false);
    if (m.synced) {                                   // "Why?" needs the coach's reasoning from the iPhone
        Font f = font(Type::Button, large_);
        int hgt = large_ ? 48 : BUTTON_H;
        lv_obj_t* bt = lv_obj_create(root_); lv_obj_remove_style_all(bt);
        lv_obj_set_style_bg_color(bt, col(p.surface_2), 0); lv_obj_set_style_bg_opa(bt, LV_OPA_COVER, 0); lv_obj_set_style_radius(bt, LV_RADIUS_CIRCLE, 0);
        lv_obj_clear_flag(bt, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
        lv_obj_t* t = label(bt, tr(S::Why, l), f, p.ink, ar_); lv_obj_update_layout(t);
        int w = std::max(large_ ? 84 : 76, int(lv_obj_get_width(t)) + 2 * SPACE_XL);
        lv_obj_set_size(bt, w, hgt); lv_obj_set_pos(bt, C - w / 2, 160);
        lv_obj_set_pos(t, (w - lv_obj_get_width(t)) / 2, labelYFor(baselineOf((hgt - f.lineBox) / 2, f.lineBox, f.css), f.f));
        hit(C - w / 2, 160, w, hgt, Action::MenuItem, int(MenuId::Coach), "why");
    }
    pageDots(4, 2, 222);
}

void Ui::buildWActivity(const Model& m) {
    const Palette& p = *pal_; Lang l = m.settings.lang;
    static const int R[] = {110, 98, 86};
    // steps / minutes / calories need the accelerometer step counter (not built) or iPhone data: tracks only, no progress
    for (int i = 0; i < 3; i++) arc(R[i], 8, 0, 360, p.line);
    Font lbl = font(Type::Label, large_), cap = font(Type::Caption, large_);
    textLine(60, tr(S::StepsLbl, l), lbl, p.ink_2);
    textLine(86, "\xE2\x80\x94", font(Type::Display44, false), p.ink_3);
    Run g; g.top = 134; g.lineBox = cap.lineBox; g.mainCss = cap.css; g.reverse = ar_;
    Piece a; a.text = trs(S::OfGoal, l, "10 000") + " \xC2\xB7"; a.font = cap; a.color = p.ink_2; a.rtlText = ar_; g.pieces.push_back(a);
    Piece t; t.text = tr(S::Estimated, l); t.font = cap; t.color = p.status_info; t.gapBefore = 4; t.rtlText = ar_; g.pieces.push_back(t);
    makeRun(g);
    textLine(152, trss(S::MinKcal, l, "\xE2\x80\x94", "\xE2\x80\x94"), cap, p.ink_2);
    pageDots(4, 3, 176);
}

// ---- destinations that are not in this release (prototype emptyState pattern) ----
void Ui::buildNotYet(const Model& m) {
    Lang l = m.settings.lang;
    S name = menuText(m.notYet);
    header(l == Lang::En ? upperAscii(tr(name, l)) : std::string(tr(name, l)), "");
    emptyState(emptyIcon(m.notYet), tr(S::NotInRelease, l), tr(S::ArrivesLater, l));
}

} // namespace cyw::v3
#endif // CYW_V3POC
