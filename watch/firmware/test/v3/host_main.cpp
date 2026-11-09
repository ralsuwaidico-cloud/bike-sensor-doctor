// Cyclift Watch v3 — Stage 1 rendering tests on a computer. Runs the real LVGL 8.3.11 code of the watch UI at the
// watch's resolution and colour depth (240 × 240, RGB565, half-screen draw buffer like the device) and checks every
// rendered state automatically:
//   text inside the round screen · no clipped / ellipsised text · no overlapping elements · touch targets ≥ 44 px ·
//   every glyph present in the fonts (Arabic after shaping) · lead number fits for 0…2500 W · navigation by touch ·
//   simulated buttons · LVGL memory · redrawn area per 1 Hz update.
// Writes PNG screenshots and report.json to the output folder. Computer measurements only: NOT watch performance.
#include "../../src/ui/v3/cyv3_ui.hpp"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <cstdlib>

using namespace cyw::v3;

// ---------------------------------------------------------------------------------------------------------------- display
static uint16_t g_fb[240 * 240];
static lv_color_t g_buf[240 * 120];                 // half-screen buffer, as on the watch (57.6 KB)
static long g_flushedPx = 0;
static void flush(lv_disp_drv_t* d, const lv_area_t* a, lv_color_t* p) {
    for (int y = a->y1; y <= a->y2; y++) for (int x = a->x1; x <= a->x2; x++) { lv_color_t c = *p++; g_fb[y * 240 + x] = uint16_t((c.full >> 8) | (c.full << 8)); }   // LV_COLOR_16_SWAP: undo the SPI byte order
    g_flushedPx += long(a->x2 - a->x1 + 1) * (a->y2 - a->y1 + 1);
    lv_disp_flush_ready(d);
}

// ---------------------------------------------------------------------------------------------------------------- PNG (stored deflate, no dependencies)
static uint32_t crcTab[256];
static uint32_t crc(const uint8_t* b, size_t n, uint32_t c = 0xffffffffu) { for (size_t i = 0; i < n; i++) c = crcTab[(c ^ b[i]) & 0xff] ^ (c >> 8); return c; }
static void be32(std::vector<uint8_t>& v, uint32_t x) { for (int i = 3; i >= 0; i--) v.push_back(uint8_t(x >> (8 * i))); }
static void chunk(std::vector<uint8_t>& out, const char* type, const std::vector<uint8_t>& data) {
    be32(out, uint32_t(data.size())); std::vector<uint8_t> td(type, type + 4); td.insert(td.end(), data.begin(), data.end());
    out.insert(out.end(), td.begin(), td.end()); be32(out, crc(td.data(), td.size()) ^ 0xffffffffu);
}
static void savePng(const std::string& path) {
    for (uint32_t n = 0; n < 256; n++) { uint32_t c = n; for (int k = 0; k < 8; k++) c = c & 1 ? 0xedb88320u ^ (c >> 1) : c >> 1; crcTab[n] = c; }
    std::vector<uint8_t> raw;
    for (int y = 0; y < 240; y++) { raw.push_back(0); for (int x = 0; x < 240; x++) { uint16_t c = g_fb[y * 240 + x];
        raw.push_back(uint8_t(((c >> 11) & 31) * 255 / 31)); raw.push_back(uint8_t(((c >> 5) & 63) * 255 / 63)); raw.push_back(uint8_t((c & 31) * 255 / 31)); } }
    std::vector<uint8_t> z{0x78, 0x01}; uint32_t a = 1, b = 0; size_t i = 0;
    for (uint8_t ch : raw) { a = (a + ch) % 65521; b = (b + a) % 65521; }
    while (i < raw.size()) { size_t n = std::min<size_t>(65535, raw.size() - i); z.push_back(i + n == raw.size()); z.push_back(uint8_t(n)); z.push_back(uint8_t(n >> 8)); z.push_back(uint8_t(~n)); z.push_back(uint8_t(~n >> 8)); z.insert(z.end(), raw.begin() + i, raw.begin() + i + n); i += n; }
    be32(z, (b << 16) | a);
    std::vector<uint8_t> out{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, ih; be32(ih, 240); be32(ih, 240); ih.insert(ih.end(), {8, 2, 0, 0, 0});
    chunk(out, "IHDR", ih); chunk(out, "IDAT", z); chunk(out, "IEND", {});
    FILE* f = std::fopen(path.c_str(), "wb"); if (f) { std::fwrite(out.data(), 1, out.size(), f); std::fclose(f); }
}

// ---------------------------------------------------------------------------------------------------------------- checks
struct Finding { std::string state, rule, detail; bool known = false; };
static std::vector<Finding> g_findings;
static std::vector<std::string> g_infos;
static int g_checks = 0;
/// Findings recorded in the Stage 1 report as remaining defects that need a design decision; listed, never hidden.
static bool knownDefect(const std::string& rule, const std::string& d) { return rule == "touch-target" && d.rfind("more hint", 0) == 0; }
static void fail(const std::string& st, const std::string& rule, const std::string& d) { g_findings.push_back({st, rule, d, knownDefect(rule, d)}); }

struct Box { int x1, y1, x2, y2; lv_obj_t* obj; std::string what; bool overlay; };
static bool isOverlay(lv_obj_t* o) { for (; o; o = lv_obj_get_parent(o)) { void* u = lv_obj_get_user_data(o); if (u && std::strcmp(static_cast<const char*>(u), "overlay") == 0) return true; } return false; }
static bool ancestor(lv_obj_t* a, lv_obj_t* b) { for (lv_obj_t* o = lv_obj_get_parent(b); o; o = lv_obj_get_parent(o)) if (o == a) return true; return false; }

/// The visible ink box of a label: its LVGL box, narrowed vertically to the real glyph extents of its text
/// (glyph descriptors after Arabic shaping, fallback fonts included).
static Box inkBox(lv_obj_t* l) {
    lv_area_t a; lv_obj_get_coords(l, &a);
    const lv_font_t* f = lv_obj_get_style_text_font(l, 0); const char* t = lv_label_get_text(l);
    int lines = 1; for (const char* c = t; *c; c++) if (*c == '\n') lines++;
    if (lv_label_get_long_mode(l) == LV_LABEL_LONG_DOT && lv_obj_get_height(l) > f->line_height + 2) lines = 2;
    int up = 0, down = -1000; uint32_t i = 0;
    while (t[i]) { uint32_t cp = _lv_txt_encoded_next(t, &i); lv_font_glyph_dsc_t g; if (cp == ' ' || !lv_font_get_glyph_dsc(f, &g, cp, 0) || !g.box_h) continue;
        up = std::max(up, int(g.box_h) + g.ofs_y); down = std::max(down, -int(g.ofs_y)); }
    if (down == -1000) down = 0;
    int base = a.y1 + (f->line_height - f->base_line);
    int lastBase = base + (lines - 1) * (f->line_height + lv_obj_get_style_text_line_space(l, 0));
    return {a.x1, base - up, a.x2, lastBase + std::max(0, down), l, std::string("text \"") + t + "\"", isOverlay(l)};
}

static void walk(lv_obj_t* o, std::vector<lv_obj_t*>& out) { out.push_back(o); for (uint32_t i = 0; i < lv_obj_get_child_cnt(o); i++) walk(lv_obj_get_child(o, int32_t(i)), out); }

static int g_glyphMissing = 0;
static void checkState(const std::string& st, Ui& ui, const Model& m) {
    std::vector<lv_obj_t*> all; walk(ui.root(), all);
    std::vector<Box> boxes;
    for (lv_obj_t* o : all) {
        if (o == ui.root()) continue;
        lv_area_t a; lv_obj_get_coords(o, &a);
        if (lv_obj_check_type(o, &lv_label_class)) {
            const char* t = lv_label_get_text(o); if (!t || !*t) continue;
            Box b = inkBox(o); boxes.push_back(b);
            // 1 inside the round screen (2 px margin from the glass edge)
            for (auto [x, y] : {std::pair<int, int>{b.x1, b.y1}, {b.x2, b.y1}, {b.x1, b.y2}, {b.x2, b.y2}}) {
                g_checks++; float d = std::hypot(x - 119.5f, y - 119.5f);
                if (d > 118.f) { fail(st, "outside-circle", b.what + " corner (" + std::to_string(x) + "," + std::to_string(y) + ") is " + std::to_string(int(d)) + " px from centre"); break; }
            }
            // 2 nothing clipped or ellipsised
            g_checks++;
            if (lv_label_get_long_mode(o) == LV_LABEL_LONG_DOT) {
                lv_point_t sz; const lv_font_t* f = lv_obj_get_style_text_font(o, 0);
                lv_txt_get_size(&sz, t, f, lv_obj_get_style_text_letter_space(o, 0), lv_obj_get_style_text_line_space(o, 0), lv_obj_get_width(o), LV_TEXT_FLAG_NONE);
                if (sz.y > lv_obj_get_height(o) + 1) fail(st, "clipped-text", std::string("\"") + t + "\" needs " + std::to_string(sz.y) + " px, has " + std::to_string(lv_obj_get_height(o)));
                lv_point_t one; lv_txt_get_size(&one, t, f, lv_obj_get_style_text_letter_space(o, 0), 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
                if (sz.y <= f->line_height + 1 && one.x > lv_obj_get_width(o) + 1) fail(st, "clipped-text", std::string("\"") + t + "\" is cut to " + std::to_string(lv_obj_get_width(o)) + " of " + std::to_string(one.x) + " px");
            }
            // 3 every glyph exists (the label stores Arabic already shaped into presentation forms)
            const lv_font_t* f = lv_obj_get_style_text_font(o, 0); uint32_t i = 0;
            while (t[i]) { uint32_t cp = _lv_txt_encoded_next(t, &i); if (cp == '\n' || cp == 0x200F || cp == 0x200E) continue; g_checks++;
                lv_font_glyph_dsc_t g; if (!lv_font_get_glyph_dsc(f, &g, cp, 0)) { g_glyphMissing++; char h[16]; std::snprintf(h, sizeof h, "U+%04X", cp); fail(st, "missing-glyph", std::string(h) + " in \"" + t + "\""); } }
        } else if (lv_obj_check_type(o, &lv_img_class)) {
            boxes.push_back({a.x1, a.y1, a.x2, a.y2, o, "icon", isOverlay(o)});
        } else if (lv_obj_check_type(o, &lv_obj_class)) {
            int w = a.x2 - a.x1 + 1, h = a.y2 - a.y1 + 1;
            if (w >= 236 && h >= 236) continue;
            std::string what = w == 7 && h == 7 ? "dot" : w == 17 && h == 17 ? "gauge marker" : "box " + std::to_string(w) + "x" + std::to_string(h);
            boxes.push_back({a.x1, a.y1, a.x2, a.y2, o, what, isOverlay(o)});
            // boxes (rows, buttons, chips): rounded corners must stay on the glass
            int r = std::min<int>(lv_obj_get_style_radius(o, 0), std::min(w, h) / 2); float in = r * (1 - 0.7071f);
            for (auto [x, y] : {std::pair<float, float>{a.x1 + in, a.y1 + in}, {a.x2 - in, a.y1 + in}, {a.x1 + in, a.y2 - in}, {a.x2 - in, a.y2 - in}}) {
                g_checks++; if (std::hypot(x - 119.5f, y - 119.5f) > 120.f) { fail(st, "outside-circle", what + " corner off the screen"); break; }
            }
        }
    }
    // 4 overlaps: unrelated elements may not intersect (overlays are allowed on top, and listed)
    for (size_t i = 0; i < boxes.size(); i++) for (size_t j = i + 1; j < boxes.size(); j++) {
        const Box &a = boxes[i], &b = boxes[j];
        if (ancestor(a.obj, b.obj) || ancestor(b.obj, a.obj)) continue;
        int ix = std::min(a.x2, b.x2) - std::max(a.x1, b.x1), iy = std::min(a.y2, b.y2) - std::max(a.y1, b.y1);
        g_checks++;
        if (ix <= 0 || iy <= 0) continue;
        if (a.overlay != b.overlay) { g_infos.push_back(st + ": overlay covers " + (a.overlay ? b.what : a.what)); continue; }
        fail(st, "overlap", a.what + " overlaps " + b.what + " by " + std::to_string(ix) + "x" + std::to_string(iy) + " px");
    }
    // 5 touch targets ≥ 44 × 44 on the glass
    for (auto& h : ui.hits()) {
        int w = h.area.x2 - h.area.x1 + 1, hh = std::min<int>(h.area.y2, 239) - h.area.y1 + 1;
        g_checks++; if (w < TOUCH_MIN || hh < TOUCH_MIN) fail(st, "touch-target", std::string(h.name) + " is " + std::to_string(w) + "x" + std::to_string(hh) + " px");
    }
    (void)m;
}

// ---------------------------------------------------------------------------------------------------------------- harness
struct Ctx { Model m; Ui ui; uint32_t now = 100000; };
static std::string g_out;
static std::map<std::string, double> g_metrics;
static std::vector<std::string> g_states;
static lv_obj_t* g_screen = nullptr;

static void fresh(Ctx& c) { lv_obj_clean(g_screen); c.ui = Ui(); c.ui.begin(g_screen); }
static double ms(std::chrono::steady_clock::time_point a) { return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - a).count(); }

static void shoot(Ctx& c, const std::string& name) {
    auto t0 = std::chrono::steady_clock::now();
    c.ui.render(c.m); lv_obj_invalidate(g_screen); lv_refr_now(nullptr);
    g_metrics["render_ms_max"] = std::max(g_metrics["render_ms_max"], ms(t0));
    savePng(g_out + "/" + name + ".png");
    checkState(name, c.ui, c.m);
    g_states.push_back(name);
}

static void ridePreset(Model& m, uint32_t now) { m.startRide(now); m.setMetrics(246, 152, 92); m.interval = 2; m.remainS = 492; }

int main(int argc, char** argv) {
    g_out = argc > 1 ? argv[1] : "out"; mkdir(g_out.c_str(), 0755);
    lv_init();
    static lv_disp_draw_buf_t db; lv_disp_draw_buf_init(&db, g_buf, nullptr, 240 * 120);
    static lv_disp_drv_t dd; lv_disp_drv_init(&dd); dd.hor_res = 240; dd.ver_res = 240; dd.flush_cb = flush; dd.draw_buf = &db; lv_disp_drv_register(&dd);
    g_screen = lv_scr_act();
    Ctx c; c.ui.begin(g_screen);

    // ---------------------------------------------------------------- 1 every state × density × text size × language
    const struct { const char* n; Density d; TextSize t; } modes[] = {{"std", Density::Standard, TextSize::Default}, {"foc", Density::Focused, TextSize::Default}, {"lt", Density::Standard, TextSize::Large}};
    for (Lang lang : {Lang::En, Lang::Ar}) for (auto& md : modes) {
        std::string sfx = std::string("--") + md.n + (lang == Lang::Ar ? "-ar" : "-en");
        auto base = [&](Ctx& x) { x.m = Model(); x.m.settings.lang = lang; x.m.settings.density = md.d; x.m.settings.text = md.t; fresh(x); };
        base(c); shoot(c, "face" + sfx);
        base(c); c.m.phoneLinked = false; c.m.battery = 9; shoot(c, "face__phone-lost-battery-9" + sfx);
        base(c); c.m.synced = false; c.m.movePct = 0; shoot(c, "face__not-synced" + sfx);
        base(c); c.m.charging = true; c.m.battery = 64; shoot(c, "face__charging" + sfx);
        base(c); c.m.key1(c.now); shoot(c, "menu" + sfx);
        base(c); c.m.key1(c.now); c.m.menuScroll = c.m.menuMaxScroll(); shoot(c, "menu__scrolled-end" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.key1(c.now); shoot(c, "menu__during-workout" + sfx);
        base(c); ridePreset(c.m, c.now); shoot(c, "cockpit" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(1999, 188, 118); shoot(c, "cockpit__power-1999" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(2500, 199, 120); shoot(c, "cockpit__power-2500" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(210, 145, 84); shoot(c, "cockpit__push" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(-1, 152, 92); shoot(c, "cockpit__no-power" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(-1, 152, -1); shoot(c, "cockpit__hr-only" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.setMetrics(-1, -1, -1); shoot(c, "cockpit__no-sensors" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.phoneLinked = false; shoot(c, "cockpit__phone-lost" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.act(Action::Pause, 0, c.now); shoot(c, "cockpit__pause-pending" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.act(Action::Pause, 0, c.now); c.m.tick(c.now + 450); c.m.toast.kind = Toast::None; shoot(c, "cockpit__paused" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.act(Action::Pause, 0, c.now); c.m.tick(c.now + 450); shoot(c, "cockpit__paused-toast" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.nextReply = Reply::Refuse; c.m.act(Action::Pause, 0, c.now); c.m.tick(c.now + 450); shoot(c, "cockpit__refused" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.nextReply = Reply::NoAnswer; c.m.act(Action::Pause, 0, c.now); c.m.tick(c.now + 5000); shoot(c, "cockpit__no-answer" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.phoneLinked = false; c.m.act(Action::Pause, 0, c.now); shoot(c, "cockpit__phone-lost-refused" + sfx);
        base(c); ridePreset(c.m, c.now); c.m.key2(c.now); shoot(c, "cockpit__key2-first-press" + sfx);
    }

    // ---------------------------------------------------------------- 2 numeric range: the lead number always fits
    for (int v : {0, 7, 42, 99, 246, 999, 1000, 1500, 1999, 2000, 2500}) for (TextSize t : {TextSize::Default, TextSize::Large}) {
        c.m = Model(); c.m.settings.text = t; fresh(c); ridePreset(c.m, c.now); c.m.setMetrics(v, 150, 90);
        c.ui.render(c.m); lv_refr_now(nullptr); g_checks++;
        if (c.ui.leadPx() == 0) fail("power-" + std::to_string(v), "numeric-overflow", "lead number does not fit at 32 px");
        checkState("power-" + std::to_string(v) + (t == TextSize::Large ? "-lt" : ""), c.ui, c.m);
        if (v == 1999 || v == 2500 || v == 999) g_infos.push_back("power " + std::to_string(v) + " W → lead font " + std::to_string(c.ui.leadPx()) + " px");
    }

    // ---------------------------------------------------------------- 3 touch navigation through the real hit areas
    auto tapAt = [&](Ctx& x, Action a, int arg) -> bool {
        x.ui.render(x.m); for (auto& h : x.ui.hits()) if (h.action == a && h.arg == arg) {
            x.ui.tap(x.m, (h.area.x1 + h.area.x2) / 2, (h.area.y1 + h.area.y2) / 2, x.now); x.ui.render(x.m); return true; }
        return false; };
    auto expect = [&](bool ok, const char* what) { g_checks++; if (!ok) fail("navigation", "touch-navigation", what); };
    c.m = Model(); fresh(c);
    c.m.key1(c.now); c.ui.render(c.m);
    expect(tapAt(c, Action::MenuItem, int(MenuId::Activities)) && c.m.screen == Screen::Cockpit, "tap Activities starts the ride");
    c.m.setMetrics(246, 152, 92);
    expect(tapAt(c, Action::Pause, 0) && c.m.pending == Cmd::Pause, "tap Pause sends Pause");
    c.now += 450; c.m.tick(c.now); c.ui.render(c.m);
    expect(c.m.wk == WkState::Paused && tapAt(c, Action::Resume, 0) && c.m.pending == Cmd::Resume, "tap Resume after pause");
    c.now += 450; c.m.tick(c.now);
    c.m.key1(c.now); c.ui.render(c.m);
    expect(tapAt(c, Action::MenuItem, int(MenuId::ReturnToWorkout)) && c.m.screen == Screen::Cockpit, "tap Return to workout");
    c.m.key1(c.now);
    expect(tapAt(c, Action::MenuItem, int(MenuId::WatchFace)) && c.m.screen == Screen::Face, "tap Watch Face goes home");
    c.m = Model(); fresh(c); c.m.key1(c.now);
    expect(tapAt(c, Action::MenuMore, 0) && c.m.menuScroll == 1, "tap the more hint scrolls");
    { c.m = Model(); fresh(c); c.m.key1(c.now); c.ui.render(c.m); bool clean = true;   // no touch area overlaps another one
      const auto& hs = c.ui.hits(); for (size_t i = 0; i < hs.size(); i++) for (size_t j = i + 1; j < hs.size(); j++) {
        const auto &a = hs[i].area, &b = hs[j].area; if (std::min(a.x2, b.x2) >= std::max(a.x1, b.x1) && std::min(a.y2, b.y2) >= std::max(a.y1, b.y1)) clean = false; }
      expect(clean, "menu touch areas do not overlap"); }
    c.m = Model(); fresh(c); ridePreset(c.m, c.now); c.m.nextReply = Reply::Refuse; c.m.act(Action::Pause, 0, c.now); c.now += 450; c.m.tick(c.now);
    expect(tapAt(c, Action::DismissToast, 0) && c.m.toast.kind == Toast::None, "tap the banner dismisses it");
    // simulated physical buttons on the rendered UI
    c.m = Model(); fresh(c); ridePreset(c.m, c.now);
    c.m.key2(c.now); c.ui.render(c.m); bool chip = false; { std::vector<lv_obj_t*> a; walk(g_screen, a); for (auto* o : a) if (lv_obj_check_type(o, &lv_label_class) && std::strstr(lv_label_get_text(o), "PRESS AGAIN")) chip = true; }
    expect(chip, "Key 2 first press shows LAP · PRESS AGAIN");
    c.now += 800; c.m.key2(c.now); c.now += 450; c.m.tick(c.now); c.ui.render(c.m); expect(c.m.laps == 1, "Key 2 second press saves a lap");
    c.m.key1(c.now); c.ui.render(c.m); expect(c.m.screen == Screen::Menu, "Key 1 opens the menu during a ride");

    // ---------------------------------------------------------------- 4 partial updates: redrawn area per 1 Hz cockpit update
    for (auto [name, d, t] : {std::tuple<const char*, Density, TextSize>{"std", Density::Standard, TextSize::Default}, {"foc", Density::Focused, TextSize::Default}, {"lt", Density::Standard, TextSize::Large}}) {
        c.m = Model(); c.m.settings.density = d; c.m.settings.text = t; fresh(c); c.m.startRide(c.now);
        c.m.tick(c.now + 1000); c.ui.render(c.m); lv_obj_invalidate(g_screen); lv_refr_now(nullptr);
        long px = 0, maxPx = 0; double tms = 0, maxMs = 0; int n = 0, rebuilt = 0;
        for (int s = 2; s < 122; s++) {
            c.m.tick(c.now + s * 1000u); g_flushedPx = 0; auto t0 = std::chrono::steady_clock::now();
            if (c.ui.render(c.m)) rebuilt++;
            if (getenv("CYV3_DEBUG_INV") && s < 5) { lv_disp_t* dp = lv_disp_get_default(); for (int k = 0; k < dp->inv_p; k++) if (!dp->inv_area_joined[k]) std::printf("  inv %s s%d: %d,%d %dx%d\n", name, s, dp->inv_areas[k].x1, dp->inv_areas[k].y1, lv_area_get_width(&dp->inv_areas[k]), lv_area_get_height(&dp->inv_areas[k])); }
            lv_refr_now(nullptr); double e = ms(t0); tms += e; maxMs = std::max(maxMs, e); px += g_flushedPx; maxPx = std::max(maxPx, g_flushedPx); n++;
        }
        g_metrics[std::string("update_px_avg_") + name] = double(px) / n; g_metrics[std::string("update_px_max_") + name] = double(maxPx);
        g_metrics[std::string("update_ms_avg_host_") + name] = tms / n; g_metrics[std::string("update_ms_max_host_") + name] = maxMs;
        g_metrics[std::string("update_rebuilds_") + name] = rebuilt;
        // full redraw for comparison
        g_flushedPx = 0; auto t0 = std::chrono::steady_clock::now(); lv_obj_invalidate(g_screen); lv_refr_now(nullptr);
        g_metrics[std::string("full_redraw_ms_host_") + name] = ms(t0); g_metrics["full_redraw_px"] = double(g_flushedPx);
    }
    // screen switch cost (rebuild + full redraw)
    { c.m = Model(); fresh(c); double mx = 0; for (int i = 0; i < 20; i++) { auto t0 = std::chrono::steady_clock::now(); c.m.key1(c.now); c.ui.render(c.m); lv_refr_now(nullptr); mx = std::max(mx, ms(t0)); }
      g_metrics["screen_switch_ms_max_host"] = mx; }

    lv_mem_monitor_t mm; lv_mem_monitor(&mm);
    g_metrics["lv_mem_total"] = mm.total_size; g_metrics["lv_mem_peak"] = mm.max_used; g_metrics["lv_mem_frag_pct"] = mm.frag_pct;
    g_metrics["draw_buffer_bytes"] = sizeof(g_buf);

    // ---------------------------------------------------------------- report
    FILE* f = std::fopen((g_out + "/report.json").c_str(), "w");
    std::fprintf(f, "{\n  \"note\": \"Computer (x86) run of the watch UI code with LVGL 8.3.11. Timings are NOT watch timings.\",\n  \"checks\": %d,\n  \"states\": %zu,\n  \"metrics\": {", g_checks, g_states.size());
    bool first = true; for (auto& [k, v] : g_metrics) { std::fprintf(f, "%s\n    \"%s\": %.3f", first ? "" : ",", k.c_str(), v); first = false; }
    std::fprintf(f, "\n  },\n  \"findings\": [");
    auto esc = [](std::string s) { std::string o; for (char ch : s) { if (ch == '"' || ch == '\\') o += '\\'; o += ch; } return o; };
    for (size_t i = 0; i < g_findings.size(); i++) std::fprintf(f, "%s\n    {\"state\": \"%s\", \"rule\": \"%s\", \"detail\": \"%s\", \"known_defect\": %s}", i ? "," : "", esc(g_findings[i].state).c_str(), g_findings[i].rule.c_str(), esc(g_findings[i].detail).c_str(), g_findings[i].known ? "true" : "false");
    std::fprintf(f, "\n  ],\n  \"info\": [");
    for (size_t i = 0; i < g_infos.size(); i++) std::fprintf(f, "%s\n    \"%s\"", i ? "," : "", esc(g_infos[i]).c_str());
    std::fprintf(f, "\n  ]\n}\n"); std::fclose(f);

    std::map<std::string, int> byRule; size_t open = 0, known = 0; for (auto& x : g_findings) { byRule[x.rule + (x.known ? " (known defect)" : "")]++; (x.known ? known : open)++; }
    std::printf("v3 render: %zu states, %d checks, %zu open findings, %zu known defects", g_states.size(), g_checks, open, known);
    for (auto& [k, v] : byRule) std::printf(" · %s %d", k.c_str(), v);
    std::printf("\n  lv_mem peak %u of %u bytes · partial update avg %.0f px (std) vs full %.0f px · host only: update %.3f ms avg\n",
        unsigned(mm.max_used), unsigned(mm.total_size), g_metrics["update_px_avg_std"], g_metrics["full_redraw_px"], g_metrics["update_ms_avg_host_std"]);
    int shown = 0; for (auto& x : g_findings) if (!x.known && shown++ < 40) std::printf("  %s · %s · %s\n", x.state.c_str(), x.rule.c_str(), x.detail.c_str());
    return open ? 1 : 0;
}
