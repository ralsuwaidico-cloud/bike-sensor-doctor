// Cyclift Watch v3 — rendering cost benchmark on a computer (frame-time investigation, 9 Nov 2026).
// Runs the watch's own frame loop (v3poc_main.cpp: every 10 ms model.tick → ui.render → lv_timer_handler, LVGL refresh
// period 30 ms, 240 × 240 RGB565, 120-line draw buffer) for scripted scenarios, and records for every frame that did work:
// rebuild or update, pixels sent to the display, number of display transfers, and (under callgrind) the instructions used.
// Computer instruction counts are a PROXY for ESP32 CPU work, never a measurement of watch frame time.
//   ./perf out.csv                 wall-clock + pixels per frame
//   valgrind --tool=callgrind --collect-atstart=no ./perf out.csv     adds one callgrind dump per working frame
#include "../../src/ui/v3/cyv3_ui.hpp"
#include "../../src/ui/v3/cyv3_fonts.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <string>
#include <vector>
#if __has_include(<valgrind/callgrind.h>)
#include <valgrind/callgrind.h>
#else
#define CALLGRIND_ZERO_STATS
#define CALLGRIND_START_INSTRUMENTATION
#define CALLGRIND_TOGGLE_COLLECT
#define CALLGRIND_DUMP_STATS_AT(x)
#define RUNNING_ON_VALGRIND 0
#endif

using namespace cyw::v3;

static lv_color_t g_buf[240 * 120];
static uint16_t g_fb[240 * 240];                    // what the panel would show (only used by --verify)
static bool g_keepFb = false;
static long g_px = 0; static int g_flushes = 0;
static void flush(lv_disp_drv_t* d, const lv_area_t* a, lv_color_t* p) {
    g_px += long(a->x2 - a->x1 + 1) * (a->y2 - a->y1 + 1); g_flushes++;
    if (g_keepFb) for (int y = a->y1; y <= a->y2; y++) for (int x = a->x1; x <= a->x2; x++) g_fb[y * 240 + x] = (p++)->full;
    lv_disp_flush_ready(d);
}

struct Frame { std::string scen; int idx; bool rebuild; long px; int flushes; double us, uiUs; };
static std::vector<Frame> g_frames;

struct Sim {
    Model m; Ui ui; uint32_t now = 100000; std::string scen; int idx = 0, dumps = 0; bool collect = false;
    std::string only; bool skip = false; bool verify = false; long checked = 0; std::vector<std::string> mismatches;
    /// --verify: the picture built from partial updates must equal a full redraw of the same state (no stale pixels).
    void compareWithFullRedraw() {
        lv_refr_now(nullptr);                       // first send any partial update still pending (normal 30 ms refresh)
        static uint16_t inc[240 * 240]; std::memcpy(inc, g_fb, sizeof inc);
        lv_obj_invalidate(lv_scr_act()); lv_refr_now(nullptr);
        int diff = 0; for (int i = 0; i < 240 * 240; i++) diff += inc[i] != g_fb[i];
        checked++;
        if (diff) { char b[128]; std::snprintf(b, sizeof b, "%s frame %d: %d pixels differ from a full redraw", scen.c_str(), idx, diff); mismatches.push_back(b); }
    }
    void reset(const std::string& s) {
        skip = !only.empty() && s.find(only) == std::string::npos;
        scen = s; idx = 0; dumps = 0; lv_obj_clean(lv_scr_act()); m = Model(); ui = Ui(); ui.begin(lv_scr_act());
        m.clock.valid = true; m.synced = true;
    }
    // one device loop iteration (10 ms)
    void frame(const std::function<void()>& input = nullptr) {
        if (skip) return;
        now += 10; lv_tick_inc(10);
        g_px = 0; g_flushes = 0;
        if (collect) { CALLGRIND_ZERO_STATS; }
        auto t0 = std::chrono::steady_clock::now();
        if (input) input();
        m.tick(now);
        bool rb = ui.render(m);
        lv_disp_t* disp = lv_disp_get_default();
        bool inv = disp->inv_p > 0;
        static const bool dbgInv = getenv("PERF_INV") != nullptr;
        if (dbgInv && inv && idx > 300 && idx < 1500 && !rb) { std::printf("%s f%d:", scen.c_str(), idx); for (int k = 0; k < disp->inv_p; k++) std::printf(" [%s%d,%d %dx%d]", disp->inv_area_joined[k] ? "j " : "", disp->inv_areas[k].x1, disp->inv_areas[k].y1, lv_area_get_width(&disp->inv_areas[k]), lv_area_get_height(&disp->inv_areas[k])); std::printf("\n"); }
        auto t1 = std::chrono::steady_clock::now();
        bool dumpThis = collect && (rb || (dumps < 300 && (inv || idx % 500 == 0)));
        char name[96];
        if (dumpThis) { std::snprintf(name, sizeof name, "%s#%d#%s#ui", scen.c_str(), idx, rb ? "rebuild" : inv ? "update" : "idle"); CALLGRIND_DUMP_STATS_AT(name); }
        lv_timer_handler();
        auto t2 = std::chrono::steady_clock::now();
        if (dumpThis || (collect && g_px > 0 && dumps < 300)) {
            std::snprintf(name, sizeof name, "%s#%d#%s#draw", scen.c_str(), idx, rb ? "rebuild" : g_px ? "update" : "idle"); CALLGRIND_DUMP_STATS_AT(name); dumps++;
        }
        double us = std::chrono::duration<double, std::micro>(t2 - t0).count(), uiUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
        bool work = rb || inv || g_px > 0;
        if (work || idx % 500 == 0) g_frames.push_back({scen, idx, rb, g_px, g_flushes, us, uiUs});
        if (verify && idx % 100 == 99) compareWithFullRedraw();
        idx++;
    }
    void seconds(int s, const std::function<void(int)>& atSecond = nullptr) {
        for (int i = 0; i < s * 100; i++) frame(atSecond && i % 100 == 0 ? std::function<void()>([&, i] { atSecond(i / 100); }) : nullptr);
    }
};

int main(int argc, char** argv) {
    const char* out = argc > 1 ? argv[1] : "perf.csv";
    std::string only = argc > 2 ? argv[2] : "";   // optional scenario filter (substring)
    lv_init();
    static lv_disp_draw_buf_t db; lv_disp_draw_buf_init(&db, g_buf, nullptr, 240 * 120);
    static lv_disp_drv_t dd; lv_disp_drv_init(&dd); dd.hor_res = 240; dd.ver_res = 240; dd.flush_cb = flush; dd.draw_buf = &db;
    lv_disp_drv_register(&dd);
    Sim s; s.collect = RUNNING_ON_VALGRIND; s.only = only == "--verify" ? "" : only; s.verify = only == "--verify"; g_keepFb = s.verify;
    if (s.collect) { CALLGRIND_START_INSTRUMENTATION; CALLGRIND_TOGGLE_COLLECT; }
    auto lang = [](Sim& x, bool ar) { x.m.settings.lang = ar ? Lang::Ar : Lang::En; };

    for (bool ar : {false, true}) {
        const char* L = ar ? "ar" : "en";
        // 1 watch face, 90 s (clock minute changes at 60 s)
        s.reset(std::string("face_") + L); lang(s, ar);
        s.seconds(90, [&](int sec) { if (sec == 60) { s.m.clock.mm++; } });
        // 2 cockpit during a ride, 120 s, each density / text size
        for (auto [nm, d, t] : {std::tuple<const char*, Density, TextSize>{"std", Density::Standard, TextSize::Default}, {"foc", Density::Focused, TextSize::Default}, {"lt", Density::Standard, TextSize::Large}}) {
            s.reset(std::string("cockpit_") + nm + "_" + L); lang(s, ar); s.m.settings.density = d; s.m.settings.text = t;
            s.m.startRide(s.now); s.seconds(120);
        }
        // 3 navigation: face ↔ menu with Key 1 every 3 s, then ride: cockpit → menu → cockpit with Key 1 / Key 2
        s.reset(std::string("nav_") + L); lang(s, ar);
        s.seconds(30, [&](int sec) { if (sec % 3 == 1) s.m.key1(s.now); });
        s.m.startRide(s.now);
        s.seconds(30, [&](int sec) { if (sec % 6 == 1) s.m.key1(s.now); if (sec % 6 == 4) s.m.key2(s.now); });
        // 4 pause / resume (command sent → confirmed → toast → toast gone: four rebuilds each)
        s.reset(std::string("pause_") + L); lang(s, ar); s.m.startRide(s.now); s.seconds(3);
        s.seconds(20, [&](int sec) { if (sec == 1) s.m.act(Action::Pause, 0, s.now); if (sec == 10) s.m.act(Action::Resume, 0, s.now); });
    }
    if (s.collect) { CALLGRIND_TOGGLE_COLLECT; }
    FILE* f = std::fopen(out, "w");
    std::fprintf(f, "scenario,frame,kind,px,flushes,host_us,host_ui_us\n");
    for (auto& fr : g_frames) std::fprintf(f, "%s,%d,%s,%ld,%d,%.1f,%.1f\n", fr.scen.c_str(), fr.idx, fr.rebuild ? "rebuild" : (fr.px ? "update" : "idle"), fr.px, fr.flushes, fr.us, fr.uiUs);
    std::fclose(f);
    std::printf("frames recorded: %zu -> %s\n", g_frames.size(), out);
    if (s.verify) {
        for (auto& m : s.mismatches) std::printf("STALE: %s\n", m.c_str());
        std::printf("partial-update check: %ld pictures compared with a full redraw, %zu differ\n", s.checked, s.mismatches.size());
        return s.mismatches.empty() ? 0 : 1;
    }
    return 0;
}
