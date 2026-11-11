// Cyclift Watch v3 — Stage 1 rendering tests on a computer. Runs the real LVGL 8.3.11 code of the watch UI at the
// watch's resolution and colour depth (240 × 240, RGB565, half-screen draw buffer like the device) and checks every
// rendered state automatically:
//   text inside the round screen · no clipped / ellipsised text · no overlapping elements · touch targets ≥ 44 px ·
//   every glyph present in the fonts (Arabic after shaping) · lead number fits for 0…2500 W · navigation by touch ·
//   simulated buttons · LVGL memory · redrawn area per 1 Hz update.
// Writes PNG screenshots and report.json to the output folder. Computer measurements only: NOT watch performance.
#include "../../src/ui/v3/cyv3_ui.hpp"
#include "../../src/ui/v3/cyv3_fonts.hpp"
#include "../../src/hal/rtc_time.hpp"
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
static double g_minContrast = 99.0;
/// Findings recorded in the Stage 1 report as remaining defects that need a design decision; listed, never hidden.
static bool knownDefect(const std::string&, const std::string&) { return false; }   // none since the 9 Nov menu fix
static void fail(const std::string& st, const std::string& rule, const std::string& d) { g_findings.push_back({st, rule, d, knownDefect(rule, d)}); }

struct Box { int x1, y1, x2, y2; lv_obj_t* obj; std::string what; bool overlay; };
static bool isBackground(lv_obj_t* o) { void* u = lv_obj_get_user_data(o); return u && std::strcmp(static_cast<const char*>(u), "background") == 0; }
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
        if (o == ui.root() || isBackground(o)) continue;   // the cockpit ring background image (not a content element)
        lv_area_t a; lv_obj_get_coords(o, &a);
        if (lv_obj_check_type(o, &lv_label_class)) {
            const char* t = lv_label_get_text(o); if (!t || !*t || lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) continue;
            Box b = inkBox(o); boxes.push_back(b);
            // 1 inside the round screen (2 px margin from the glass edge)
            for (auto [x, y] : {std::pair<int, int>{b.x1, b.y1}, {b.x2, b.y1}, {b.x1, b.y2}, {b.x2, b.y2}}) {
                g_checks++; float d = std::hypot(x - 119.5f, y - 119.5f);
                if (d > 118.f) { fail(st, "outside-circle", b.what + " corner (" + std::to_string(x) + "," + std::to_string(y) + ") is " + std::to_string(int(d)) + " px from centre"); break; }
            }
            // 2 nothing clipped or ellipsised
            g_checks++;
            if (lv_label_get_long_mode(o) == LV_LABEL_LONG_DOT) {
                // LVGL's own decision: dot_end is set when it had to replace the end of the text with "..."
                const lv_label_t* lb = reinterpret_cast<const lv_label_t*>(o);
                if (lb->dot_end != 0xFFFFFFFFu   /* LV_LABEL_DOT_END_INV (private to lv_label.c) */) fail(st, "clipped-text", std::string("\"") + t + "\" is cut short with an ellipsis");
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
    // 5 touch targets: each must hold a 44 × 44 px square that lies wholly on the round glass (radius 120)
    for (auto& h : ui.hits()) {
        g_checks++; bool fits = false;
        for (int y = h.area.y1; y + TOUCH_MIN - 1 <= h.area.y2 && !fits; y++)
            for (int x = h.area.x1; x + TOUCH_MIN - 1 <= h.area.x2 && !fits; x++) {
                bool in = true;
                for (auto [cx, cy] : {std::pair<int, int>{x, y}, {x + TOUCH_MIN - 1, y}, {x, y + TOUCH_MIN - 1}, {x + TOUCH_MIN - 1, y + TOUCH_MIN - 1}})
                    if (std::hypot(cx - 119.5f, cy - 119.5f) > 120.f) in = false;
                fits = in;
            }
        if (!fits) fail(st, "touch-target", std::string(h.name) + " has no 44x44 px area on the glass (" + std::to_string(h.area.x2 - h.area.x1 + 1) + "x" + std::to_string(h.area.y2 - h.area.y1 + 1) + " px box)");
    }
    // 6 a banner, toast or key chip never covers a control the rider may need to press
    for (lv_obj_t* o : all) {
        void* u = lv_obj_get_user_data(o); if (!u || std::strcmp(static_cast<const char*>(u), "overlay") != 0) continue;
        lv_area_t a; lv_obj_get_coords(o, &a);
        for (auto& h : ui.hits()) {
            if (std::string(h.name) == "banner") continue; g_checks++;
            if (std::min(a.x2, h.area.x2) >= std::max(a.x1, h.area.x1) && std::min(a.y2, h.area.y2) >= std::max(a.y1, h.area.y1))
                fail(st, "overlay-covers-control", std::string("overlay covers the ") + h.name);
        }
    }
    // 7 touch areas never overlap each other
    for (size_t i = 0; i < ui.hits().size(); i++) for (size_t j = i + 1; j < ui.hits().size(); j++) {
        const auto &a = ui.hits()[i].area, &b = ui.hits()[j].area; g_checks++;
        if (std::min(a.x2, b.x2) >= std::max(a.x1, b.x1) && std::min(a.y2, b.y2) >= std::max(a.y1, b.y1))
            fail(st, "touch-overlap", std::string(ui.hits()[i].name) + " overlaps " + ui.hits()[j].name);
    }
    // 8 text contrast against the screen background: >= 3:1 for every visible label (WCAG large-text level; Stage 1.3)
    {
        auto lin = [](uint32_t c8) { double c = c8 / 255.0; return c <= 0.03928 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); };
        auto lum = [&](uint32_t rgb) { return 0.2126 * lin((rgb >> 16) & 255) + 0.7152 * lin((rgb >> 8) & 255) + 0.0722 * lin(rgb & 255); };
        auto bgOf = [&](lv_obj_t* o) { for (lv_obj_t* q = lv_obj_get_parent(o); q; q = lv_obj_get_parent(q))
            if (lv_obj_get_style_bg_opa(q, 0) >= LV_OPA_50) { lv_color_t c = lv_obj_get_style_bg_color(q, 0); return uint32_t(lv_color_to32(c) & 0xFFFFFF); }
            return 0u; };
        for (lv_obj_t* o : all) {
            if (!lv_obj_check_type(o, &lv_label_class) || lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN) || !*lv_label_get_text(o)) continue;
            uint32_t fg = lv_color_to32(lv_obj_get_style_text_color(o, 0)) & 0xFFFFFF, bg = bgOf(o);
            double a = lum(fg), b = lum(bg), ratio = (std::max(a, b) + 0.05) / (std::min(a, b) + 0.05); g_checks++;
            g_minContrast = std::min(g_minContrast, ratio);
            if (ratio < 3.0) fail(st, "contrast", std::string("text '") + lv_label_get_text(o) + "' contrast " + std::to_string(ratio).substr(0, 4) + ":1");
        }
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

/// True if any label under `o` shows exactly `t` (after LVGL's own copy).
static bool hasText(lv_obj_t* o, const char* t) {
    if (lv_obj_check_type(o, &lv_label_class) && std::strcmp(lv_label_get_text(o), t) == 0) return true;
    for (uint32_t i = 0; i < lv_obj_get_child_cnt(o); i++) if (hasText(lv_obj_get_child(o, int32_t(i)), t)) return true;
    return false;
}

/// Render and run every layout check, without saving a picture (for sweeps over many values).
static void check(Ctx& c, const std::string& name) {
    c.ui.render(c.m); lv_obj_invalidate(g_screen); lv_refr_now(nullptr);
    checkState(name, c.ui, c.m);
}

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

    // ---------------------------------------------------------------- 0 the checker catches what it should (self-test)
    {
        auto cnt = [](const char* rule) { int n = 0; for (auto& f : g_findings) if (f.rule == rule) n++; return n; };
        lv_obj_t* a = lv_label_create(g_screen); lv_obj_set_style_text_font(a, &cyv3_inter600_15, 0); lv_label_set_long_mode(a, LV_LABEL_LONG_DOT);
        lv_label_set_text(a, "Workout changed on iPhone"); lv_obj_set_width(a, 60); lv_obj_set_pos(a, 90, 100);          // cut short
        lv_obj_t* b = lv_label_create(g_screen); lv_obj_set_style_text_font(b, &cyv3_inter600_15, 0); lv_label_set_text(b, "Edge"); lv_obj_set_pos(b, 2, 2);   // off the glass
        lv_obj_t* d = lv_label_create(g_screen); lv_obj_set_style_text_font(d, &cyv3_inter600_15, 0); lv_label_set_text(d, "Overlap"); lv_obj_set_pos(d, 95, 100); // on top of a
        lv_obj_update_layout(g_screen);
        size_t before = g_findings.size(); int checks = g_checks;
        checkState("self-test", c.ui, c.m);
        bool ok = cnt("clipped-text") == 1 && cnt("outside-circle") >= 1 && cnt("overlap") >= 1;
        if (!ok) std::printf("  self-test: clipped %d, outside %d, overlap %d\n", cnt("clipped-text"), cnt("outside-circle"), cnt("overlap"));
        g_findings.resize(before); g_checks = checks + 1;
        if (!ok) fail("self-test", "checker", "layout checker did not detect a planted cut-off, off-screen or overlapping label");
        lv_obj_clean(g_screen);
    }

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

    // ---------------------------------------------------------------- 1b Stage 1.3 screens: every screen × data state × density ×
    // text size × language, in all six themes (the first theme also covers the special states)
    const char* THEME[] = {"obsidian", "arctic", "ocean", "forest", "sandstone", "contrast"};
    for (int th = 0; th < 6; th++) for (Lang lang : {Lang::En, Lang::Ar}) for (auto& md : modes) {
        std::string sfx = std::string("--") + md.n + (lang == Lang::Ar ? "-ar" : "-en") + (th ? std::string("-") + THEME[th] : "");
        auto base = [&](Ctx& x, bool demo) { x.m = Model(); x.m.settings.lang = lang; x.m.settings.density = md.d; x.m.settings.text = md.t;
            x.m.settings.theme = ThemeId(th); x.m.setDemo(demo); fresh(x); };
        for (bool demo : {false, true}) {
            std::string d = demo ? "__demo" : "";
            base(c, demo); c.m.swipe(Swipe::Up); shoot(c, "today" + d + sfx);
            base(c, demo); c.m.swipe(Swipe::Up); c.m.swipe(Swipe::Up); shoot(c, "week" + d + sfx);
            base(c, demo); c.m.swipe(Swipe::Left); shoot(c, "w-health" + d + sfx);
            base(c, demo); c.m.swipe(Swipe::Left); c.m.swipe(Swipe::Left); shoot(c, "w-coach" + d + sfx);
            base(c, demo); c.m.swipe(Swipe::Right); shoot(c, "w-activity" + d + sfx);
            base(c, demo); shoot(c, "face" + std::string(demo ? "__demo" : "__honest") + sfx);
        }
        base(c, false); c.m.swipe(Swipe::Down); shoot(c, "quick" + sfx);
        base(c, false); c.m.swipe(Swipe::Down); c.m.qsScroll = c.m.qsMaxScroll(); shoot(c, "quick__scrolled-end" + sfx);
        base(c, false); c.m.key1(c.now); c.m.act(Action::MenuItem, int(MenuId::Settings), c.now); shoot(c, "not-yet__settings" + sfx);
        base(c, false); c.m.settings.mode = Mode::Bike; ridePreset(c.m, c.now); shoot(c, "cockpit__bike" + sfx);
        base(c, false); c.m.locked = true; shoot(c, "face__locked" + sfx);
        if (th) continue;
        // Milestone C: every month and weekday name on the face and the Today caption (both widest day numbers), checked for
        // glyphs, fit, clipping and overlap without saving images (the PNG set stays one picture per screen)
        for (int mo = 1; mo <= 12; mo++) for (int wd = 0; wd < 7; wd++) for (bool today : {false, true}) {
            base(c, true); c.m.clock.month = mo; c.m.clock.weekday = wd; c.m.clock.day = (mo + wd) % 2 ? 28 : 31;
            if (today) c.m.swipe(Swipe::Up);
            check(c, std::string(today ? "today" : "face") + "__date-" + std::to_string(mo) + "-" + std::to_string(wd) + sfx);
        }
        // RC2 clock rule: the face shows the chip's time whenever it is valid, whatever the iPhone / demo state; never otherwise
        for (int demo = 0; demo < 2; demo++) for (int valid = 0; valid < 2; valid++) for (int phone = 0; phone < 2; phone++) {
            base(c, demo); c.m.clock.valid = valid; c.m.phoneLinked = phone; c.m.clock.hh = 7; c.m.clock.mm = 5;
            c.ui.render(c.m); lv_refr_now(nullptr);
            bool time = hasText(lv_scr_act(), "07:05"), dashes = hasText(lv_scr_act(), "--:--");
            g_checks++;
            if (!(valid ? (time && !dashes) : (dashes && !time)))
                fail("face" + sfx, "clock-rule", "demo " + std::to_string(demo) + ", clock valid " + std::to_string(valid) + ", phone " + std::to_string(phone));
        }
        base(c, false); c.m.clock.valid = false; shoot(c, "face__clock-invalid" + sfx);
        base(c, false); c.m.clock.valid = false; c.m.swipe(Swipe::Up); shoot(c, "today__clock-invalid" + sfx);
        base(c, true); c.m.settings.dnd = true; c.m.settings.mode = Mode::Gym; c.m.settings.brightness = 100; c.m.settings.theme = ThemeId::Contrast; c.m.swipe(Swipe::Down); shoot(c, "quick__values" + sfx);
        for (MenuId id : {MenuId::Health, MenuId::Coach, MenuId::History, MenuId::Utilities}) {
            static const char* nm[] = {"", "", "", "", "health", "coach", "history", "utilities", ""};
            base(c, false); c.m.key1(c.now); c.m.act(Action::MenuItem, int(id), c.now); shoot(c, std::string("not-yet__") + nm[int(id)] + sfx); }
        base(c, false); c.m.settings.mode = Mode::Bike; ridePreset(c.m, c.now); c.m.setMetrics(-1, 152, 92); shoot(c, "cockpit__bike-hr-lead" + sfx);
        base(c, false); c.m.settings.mode = Mode::Bike; ridePreset(c.m, c.now); c.m.setMetrics(1999, 188, 118); shoot(c, "cockpit__bike-1999" + sfx);
        base(c, false); c.m.settings.mode = Mode::Bike; ridePreset(c.m, c.now); c.m.act(Action::Pause, 0, c.now); c.m.tick(c.now + 450); c.m.toast.kind = Toast::None; shoot(c, "cockpit__bike-paused" + sfx);
        base(c, false); c.m.simRideNotice = true; c.m.key1(c.now); c.m.act(Action::MenuItem, int(MenuId::Activities), c.now); c.m.setMetrics(246, 152, 92); shoot(c, "cockpit__simulated-banner" + sfx);
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
    // Stage 1.3: through the real touch areas of the new screens
    c.m = Model(); fresh(c); c.m.setDemo(false); c.m.swipe(Swipe::Up); c.ui.render(c.m);
    expect(tapAt(c, Action::Go, int(Screen::Week)) && c.m.screen == Screen::Week, "Today: tap Week opens the week strip");
    c.m = Model(); fresh(c); c.m.swipe(Swipe::Up);
    expect(tapAt(c, Action::StartPlan, 0) && c.m.screen == Screen::Cockpit && c.m.inWorkout(), "Today (demo plan): tap Start begins the ride");
    c.m = Model(); fresh(c); c.m.setDemo(false); c.m.swipe(Swipe::Up); c.ui.render(c.m);
    { bool start = false; for (auto& h : c.ui.hits()) start = start || h.action == Action::StartPlan; expect(!start, "Today without a plan offers no Start button"); }
    c.m = Model(); fresh(c); c.m.swipe(Swipe::Down);
    expect(tapAt(c, Action::QsRow, int(QsRow::Brightness)) && c.m.settings.brightness == 100, "Quick Settings: tap Brightness 70 -> 100");
    expect(tapAt(c, Action::QsRow, int(QsRow::Theme)) && c.m.settings.theme == ThemeId::Arctic, "Quick Settings: tap Theme -> Arctic");
    expect(tapAt(c, Action::QsMore, 0) && c.m.qsScroll == 1, "Quick Settings: tap the more hint scrolls");
    for (int i = 0; i < 3; i++) tapAt(c, Action::QsMore, 0);
    expect(tapAt(c, Action::QsRow, int(QsRow::Lock)) && c.m.locked && c.m.screen == Screen::Face, "Quick Settings: Screen lock locks and shows the face");
    { c.ui.render(c.m); bool chipShown = false; std::vector<lv_obj_t*> a; walk(g_screen, a);
      for (auto* o : a) if (lv_obj_check_type(o, &lv_label_class) && std::strstr(lv_label_get_text(o), "HOLD KEY 1")) chipShown = true;
      expect(chipShown, "locked face shows LOCKED · HOLD KEY 1"); }
    c.m.key1Hold(c.now); c.ui.render(c.m); expect(!c.m.locked, "hold Key 1 unlocks");
    c.m = Model(); fresh(c); c.m.swipe(Swipe::Left);
    expect(tapAt(c, Action::MenuItem, int(MenuId::Health)) && c.m.screen == Screen::NotYet && c.m.notYet == MenuId::Health, "Health widget tap opens the Health page (not in this release)");
    c.m = Model(); fresh(c); c.m.swipe(Swipe::Left); c.m.swipe(Swipe::Left);
    expect(tapAt(c, Action::MenuItem, int(MenuId::Coach)) && c.m.notYet == MenuId::Coach, "Coach widget: Why? opens the Coach page (not in this release)");
    c.m.key2(c.now); expect(c.m.screen == Screen::WCoach, "Back from the page returns to the widget");
    // Stage 1.2 temporary time command, end to end: serial "T<seconds>" -> clock-chip registers -> integrity check ->
    // model clock -> face (same steps as readClock() on the watch; the chip itself is replaced by its 7 registers)
    { c.m = Model(); fresh(c);
      uint8_t regs[7] = {0x80, 0, 0, 0x01, 6, 0x01, 0x00};                        // after power loss: VL set, 2000-01-01
      auto readClock = [&] { cyw::rtc::Reading r = cyw::rtc::fromRegs(regs); c.m.clock.valid = r.integrity; if (!r.integrity) return;
          int y, mo, d, h, mi, s; cyw::rtc::fromUnix(r.t, y, mo, d, h, mi, s); c.m.clock.hh = h; c.m.clock.mm = mi; c.m.clock.day = d;
          c.m.clock.month = mo; c.m.clock.weekday = cyw::rtc::weekday(r.t); };
      auto faceText = [&] { std::string all; std::vector<lv_obj_t*> a; walk(g_screen, a); for (auto* o : a) if (lv_obj_check_type(o, &lv_label_class)) all += std::string(lv_label_get_text(o)) + "|"; return all; };
      readClock(); c.ui.render(c.m); lv_refr_now(nullptr);
      expect(faceText().find("--:--") != std::string::npos && faceText().find("NOT SYNCED") != std::string::npos, "unset clock shows --:-- and NOT SYNCED");
      cyw::rtc::TimeCommand cmd; cyw::rtc::TimeCommand::Result res = cyw::rtc::TimeCommand::Idle;
      for (char ch : std::string("T1794331800\n")) res = cmd.feed(ch);
      expect(res == cyw::rtc::TimeCommand::Done, "serial T1794331800 accepted");
      cyw::rtc::toRegs(uint32_t(cmd.value), regs); readClock(); c.ui.render(c.m); lv_refr_now(nullptr);
      expect(faceText().find("17:30") != std::string::npos && faceText().find("NOT SYNCED") == std::string::npos, "after T: face shows 17:30, no NOT SYNCED");
      expect(faceText().find("TUE 10 NOV") != std::string::npos || faceText().find("Tue 10 Nov") != std::string::npos, "after T: date Tue 10 Nov");
      shoot(c, "face__time-set-from-pc--std-en");
      regs[0] |= 0x80; readClock(); c.ui.render(c.m); lv_refr_now(nullptr);   // USB unplugged (no battery): VL set again
      expect(faceText().find("--:--") != std::string::npos, "after power loss: back to --:--"); }

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

    // ---------------------------------------------------------------- soak (Stage 1.3): 30 000 random inputs through the real UI
    // (swipes, keys, key hold, taps on the drawn touch areas, ticks, ride start), every one rendered. Every 1 000 inputs the
    // same reference state is rendered through the same Ui: LVGL memory in use must come back within 64 B of the first (no leak),
    // and the sampled pool peak (total − free after each render; LVGL's own max_used under-reads) must stay under 32 KB.
    {
        c.m = Model(); fresh(c); c.m.setDemo(true);
        Model ref = c.m; uint32_t seed = 12345, refUsed = 0, refMax = 0, peak = 0, steps = 0; int leaks = 0;
        auto rnd = [&](uint32_t n) { seed = seed * 1103515245u + 12345u; return (seed >> 8) % n; };
        auto used = [] { lv_mem_monitor_t q; lv_mem_monitor(&q); return uint32_t(q.total_size - q.free_size); };
        for (int i = 0; i < 30000; i++) {
            switch (rnd(10)) {
                case 0: case 1: case 2: c.m.swipe(Swipe(rnd(4))); break;
                case 3: c.m.key1(c.now); break;
                case 4: c.m.key2(c.now); break;
                case 5: c.m.key1Hold(c.now); break;
                case 6: case 7: { auto& h = c.ui.hits(); if (!h.empty()) { auto& a = h[rnd(uint32_t(h.size()))].area;
                    c.ui.tap(c.m, (a.x1 + a.x2) / 2, (a.y1 + a.y2) / 2, c.now); } break; }
                case 8: c.now += 1000; break;
                case 9: if (!c.m.inWorkout() && rnd(4) == 0) c.m.startRide(c.now); else c.now += 300; break;
            }
            c.m.tick(c.now); c.ui.render(c.m); lv_timer_handler(); steps++;
            peak = std::max(peak, used());
            if (i % 1000 == 999) {
                Model keep = c.m; c.m = ref; c.ui.render(c.m); lv_refr_now(nullptr);
                uint32_t u = used(); if (getenv("SOAK_DEBUG")) std::printf("ref %d: %u\n", i, unsigned(u));
                // the allocator rounds block splits differently with fragmentation (seen: ±32 B); a leak grows without bound
                if (!refUsed) refUsed = refMax = u; else { refMax = std::max(refMax, u); if (u > refUsed + 64) leaks++; }
                c.m = keep; c.ui.render(c.m);
            }
        }
        g_checks += 2;
        if (leaks) fail("soak", "lv-leak", std::to_string(leaks) + " of 30 reference renders used over 64 B more LVGL memory than the first (" + std::to_string(refUsed) + " B)");
        if (peak > 32768) fail("soak", "lv-peak", "sampled LVGL pool peak " + std::to_string(peak) + " B over 32 KB");
        g_metrics["soak_inputs"] = steps; g_metrics["soak_lv_used_reference"] = refUsed; g_metrics["soak_lv_peak_sampled"] = peak; g_metrics["soak_lv_reference_max"] = refMax; g_metrics["soak_lv_reference_growth_failures"] = leaks;
        std::printf("soak: %u inputs rendered · LVGL in use at the reference state %u–%u B (%d over +64 B) · sampled pool peak %u B\n", unsigned(steps), unsigned(refUsed), unsigned(refMax), leaks, unsigned(peak));
    }

    lv_mem_monitor_t mm; lv_mem_monitor(&mm);
    g_metrics["lv_mem_total"] = mm.total_size; g_metrics["lv_mem_peak"] = mm.max_used; g_metrics["lv_mem_frag_pct"] = mm.frag_pct;
    g_metrics["draw_buffer_bytes"] = sizeof(g_buf);
    g_metrics["text_contrast_min"] = g_minContrast;

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
