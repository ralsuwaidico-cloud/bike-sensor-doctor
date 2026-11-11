// Stage 1.3 — navigation acceptance tests (computer). The expected results below are written from the approved prototype
// (Deliverable D v3.3: app.js go/back/home/swipe/key1/key2 and each screen's swipe table), NOT derived from the firmware,
// so a firmware mistake shows up as a mismatch. Every input is applied to every screen in scope, in English (left-to-right)
// and Arabic (right-to-left), without and during a workout; then a long random-input run checks the invariants.
#include "../../src/ui/v3/cyv3_model.hpp"
#include <cstdio>
#include <map>
#include <string>
#include <vector>
using namespace cyw::v3;

static int g_checks = 0, g_fail = 0;
#define CHECK(c, ...) do { g_checks++; if (!(c)) { g_fail++; std::printf("FAIL %s:%d  ", __FILE__, __LINE__); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

static const char* name(Screen s) {
    static const char* n[] = {"Face", "Menu", "Cockpit", "Today", "Week", "Quick", "WHealth", "WCoach", "WActivity", "NotYet"};
    return n[int(s)];
}
enum In { SL, SR, SU, SD, K1, K2, NIN };
static const char* inName[] = {"swipe L", "swipe R", "swipe U", "swipe D", "Key 1", "Key 2"};

static void apply(Model& m, In i, uint32_t& t) {
    t += 3000;                                  // past the Key 2 two-press window
    switch (i) {
        case SL: m.swipe(Swipe::Left); break; case SR: m.swipe(Swipe::Right); break;
        case SU: m.swipe(Swipe::Up); break;   case SD: m.swipe(Swipe::Down); break;
        case K1: m.key1(t); break;            case K2: m.key2(t); break;
        default: break;
    }
}

/// A start state and how to reach it from a fresh model.
struct Start { const char* label; std::vector<In> path; bool viaMenuNotYet = false; bool ride = false; };

static Model reach(const Start& st, bool ar, uint32_t& t) {
    Model m; m.settings.lang = ar ? Lang::Ar : Lang::En;
    if (st.ride) { m.key1(t); m.act(Action::MenuItem, int(MenuId::Activities), t); m.key1(t); m.act(Action::MenuItem, int(MenuId::WatchFace), t); }
    for (In i : st.path) apply(m, i, t);
    if (st.viaMenuNotYet) { m.key1(t); m.act(Action::MenuItem, int(MenuId::Health), t); }
    return m;
}

int main() {
    // Expected screen after each input, per start state (English). "=" = unchanged. RTL differences listed separately.
    // Prototype rules used: face/widgets swipe tables keep physical directions in Arabic; other screens mirror left/right;
    // a swipe with no table entry on a list scrolls (up/down) or goes back (backward direction); Key 1 opens the menu,
    // on the menu returns to the face (or the workout); Key 2 is Back.
    struct Row { Start st; Screen at; Screen exp[NIN]; };
    const Screen F = Screen::Face, M = Screen::Menu, T = Screen::Today, W = Screen::Week, Q = Screen::Quick, H = Screen::WHealth,
                 C = Screen::WCoach, A = Screen::WActivity, N = Screen::NotYet, K = Screen::Cockpit;
    std::vector<Row> rows = {
        //                                     at   swipeL swipeR swipeU swipeD key1 key2
        {{"face", {}},                          F, {H, A, T, Q, M, F}},
        {{"widget Health", {SL}},               H, {C, F, H, H, M, F}},
        {{"widget Coach", {SL, SL}},            C, {A, H, C, C, M, F}},
        {{"widget Activity", {SR}},             A, {F, C, A, A, M, F}},
        {{"Today", {SU}},                       T, {T, F, W, F, M, F}},
        {{"Week", {SU, SU}},                    W, {W, T, W, T, M, T}},
        {{"Quick Settings", {SD}},              Q, {Q, F, F, Q, M, F}},
        {{"menu", {K1}},                        M, {M, F, M, M, F, F}},
        {{"not-yet page", {}, true},            N, {N, M, N, N, M, M}},
    };
    // during a ride (started, then back on the face): Key 1 on the menu returns to the ride; Back with no history → ride
    std::vector<Row> ride = {
        {{"face (ride on)", {}, false, true},              F, {H, A, T, Q, M, K}},
        {{"menu (ride on)", {K1}, false, true},            M, {M, F, M, M, K, F}},
        {{"Today (ride on)", {SU}, false, true},           T, {T, K, W, F, M, K}},
    };
    for (bool ar : {false, true}) {
        for (auto* set : {&rows, &ride}) for (const Row& r : *set) {
            for (int i = 0; i < NIN; i++) {
                uint32_t t = 1000; Model m = reach(r.st, ar, t);
                CHECK(m.screen == r.at, "%s (%s): start at %s, got %s", r.st.label, ar ? "AR" : "EN", name(r.at), name(m.screen));
                Screen e = r.exp[i];
                if (ar && !Model::faceLevel(r.at)) {                    // right-to-left mirrors left/right on non-face screens
                    if (i == SL) e = r.exp[SR]; else if (i == SR) e = r.exp[SL];
                }
                apply(m, In(i), t);
                CHECK(m.screen == e, "%s (%s) + %s: expected %s, got %s", r.st.label, ar ? "AR" : "EN", inName[i], name(e), name(m.screen));
            }
        }
    }

    // repeated gestures never pile up history (owner requirement 11 Nov)
    { uint32_t t = 0; Model m; m.swipe(Swipe::Up);
      for (int i = 0; i < 50; i++) { m.swipe(Swipe::Up); m.swipe(Swipe::Down); }
      CHECK(m.screen == Screen::Today && m.stack.empty(), "Today<->Week x50: screen %s, history %zu", name(m.screen), m.stack.size());
      for (int i = 0; i < 50; i++) { m.key1(t); m.key2(t); }
      CHECK(m.stack.empty(), "Menu<->Today x50 leaves history %zu", m.stack.size());
      m.swipe(Swipe::Down); CHECK(m.screen == Screen::Face, "Today swipe down = face");
      for (int i = 0; i < 40; i++) m.swipe(Swipe::Left);
      CHECK(m.stack.empty() && Model::faceLevel(m.screen), "widget carousel x40: history %zu", m.stack.size()); }

    // Quick Settings rows
    { Model m; uint32_t t = 0; m.swipe(Swipe::Down);
      int b0 = m.settings.brightness; m.act(Action::QsRow, int(QsRow::Brightness), t); CHECK(m.settings.brightness != b0, "brightness cycles");
      for (int i = 0; i < 4; i++) m.act(Action::QsRow, int(QsRow::Brightness), t);
      CHECK(m.settings.brightness == 100, "brightness 70 -> 100 -> 30 -> 50 -> 70 -> 100, got %d", m.settings.brightness);
      for (int i = 0; i < 6; i++) { CHECK(int(m.settings.theme) == i, "theme %d", i); m.act(Action::QsRow, int(QsRow::Theme), t); }
      CHECK(m.settings.theme == ThemeId::Obsidian, "six themes, then back to Obsidian");
      m.act(Action::QsRow, int(QsRow::Dnd), t); CHECK(m.settings.dnd, "do not disturb on");
      m.act(Action::QsRow, int(QsRow::Mode), t); CHECK(m.settings.mode == Mode::Bike, "mode Bike");
      m.act(Action::QsRow, int(QsRow::Mode), t); m.act(Action::QsRow, int(QsRow::Mode), t); CHECK(m.settings.mode == Mode::Wrist, "mode cycles");
      m.act(Action::QsRow, int(QsRow::Lock), t); CHECK(m.locked && m.screen == Screen::Face, "lock goes to the face, locked");
      Screen before = m.screen;
      for (In i : {SL, SR, SU, SD, K1, K2}) apply(m, i, t);
      m.act(Action::MenuItem, int(MenuId::Today), t);
      CHECK(m.screen == before && m.locked, "locked: swipes, keys and taps are ignored (screen %s)", name(m.screen));
      m.key1Hold(t); CHECK(!m.locked, "hold Key 1 unlocks");
      m.key1(t); CHECK(m.screen == Screen::Menu, "after unlock Key 1 works"); }

    // Today Start begins the (simulated) ride; with the honest default the "Simulated ride" banner appears
    { Model m; uint32_t t = 0; m.simRideNotice = true; m.swipe(Swipe::Up); m.act(Action::StartPlan, 0, t);
      CHECK(m.screen == Screen::Cockpit && m.inWorkout(), "Today Start opens the cockpit");
      CHECK(m.toast.kind == Toast::Info && m.toast.text == S::SimRide, "simulated-ride banner shown");
      CHECK(m.stack.empty(), "starting a workout clears the history"); }

    // RC2 lap regression (owner report 11 Nov: restart after Key 2 during a ride): every language × mode × entry route,
    // the exact owner sequence (Today → Start, or Menu → Activities; Key 2 twice quickly) and its variants
    { int laps = 0;
      for (int ar = 0; ar < 2; ar++) for (int mode = 0; mode < 3; mode++) for (int route = 0; route < 2; route++) {
          Model m; m.setDemo(route == 0); m.simRideNotice = true; m.settings.lang = ar ? Lang::Ar : Lang::En; m.settings.mode = Mode(mode);
          uint32_t t = 100000; m.tick(t);
          if (route == 0) { m.swipe(Swipe::Up); CHECK(m.screen == Screen::Today, "lap: Today opens"); m.act(Action::StartPlan, 0, t); }
          else { m.key1(t); m.act(Action::MenuItem, int(MenuId::Activities), t); }
          CHECK(m.screen == Screen::Cockpit && m.inWorkout(), "lap: ride started (route %d)", route);
          t += 10000; m.tick(t);
          for (int k = 0; k < 3; k++) {                                   // owner: lower button twice ~0.5 s apart, 3 times
              int before = m.laps;
              m.key2(t); CHECK(m.key2Armed && m.screen == Screen::Cockpit, "lap: first press arms, stays on the ride");
              t += 500; m.key2(t); CHECK(!m.key2Armed && m.pending == Cmd::Lap, "lap: second press sends Lap");
              t += 500; m.tick(t); CHECK(m.pending == Cmd::None && m.laps == before + 1 && m.screen == Screen::Cockpit, "lap: confirmed, still on the ride");
              t += 10000; m.tick(t); laps++;
          }
          m.key2(t); t += 3000; m.tick(t); CHECK(!m.key2Armed && m.screen == Screen::Cockpit, "lap: single press expires, no Back");
          m.key2(t); t += 2600; m.key2(t); CHECK(m.key2Armed && m.pending == Cmd::None, "lap: presses 2.6 s apart do not make a lap");
          t += 3000; m.tick(t);
          m.key2(t); m.key2(t + 1); m.key2(t + 2); m.key2(t + 3);         // contact bounce / four very fast presses
          CHECK(m.screen == Screen::Cockpit && m.inWorkout(), "lap: rapid presses never leave the ride");
          t += 5000; m.tick(t); CHECK(m.pending == Cmd::None, "lap: rapid presses settle");
          m.act(Action::Pause, 0, t); t += 600; m.tick(t); m.key2(t); m.key2(t + 300);
          CHECK(m.screen == Screen::Cockpit, "lap: Key 2 twice while paused stays on the ride");
      }
      std::printf("lap regression: %d laps in 12 rides\n", laps); }

    // random-input soak: 200 000 inputs; invariants hold throughout
    { Model m; uint32_t t = 0, rng = 12345; size_t maxStack = 0; int faceReturns = 0;
      for (int step = 0; step < 200000; step++) {
          rng = rng * 1664525u + 1013904223u; int r = int((rng >> 8) % 100);
          t += 37 + (rng >> 20) % 900;
          if (r < 60) apply(m, In(r % 6), t);
          else if (r < 75) m.act(Action::MenuItem, int((rng >> 12) % 9), t);
          else if (r < 82) m.act(Action::QsRow, int((rng >> 12) % 4), t);         // never Lock here (checked separately)
          else if (r < 86) m.act(Action::Go, int(Screen::Week), t);
          else if (r < 90) m.act(r % 2 ? Action::Pause : Action::Resume, 0, t);
          else if (r < 92) m.settings.lang = m.settings.lang == Lang::En ? Lang::Ar : Lang::En;
          else m.tick(t);
          maxStack = std::max(maxStack, m.stack.size());
          for (size_t i = 1; i < m.stack.size(); i++) if (m.stack[i] == m.stack[i - 1]) { CHECK(false, "duplicate adjacent history at step %d", step); break; }
          if (!m.stack.empty() && m.stack.back() == m.screen) { CHECK(false, "history top equals current screen at step %d", step); }
          if (step % 5000 == 0) {                                     // Back always leads home (or to the workout) in bounded steps
              Model c = m; uint32_t tt = t; int n = 0;
              while (!(c.screen == Screen::Face || c.screen == Screen::Cockpit) && n < Model::MAX_STACK + 3) { tt += 3000; c.key2(tt); n++; }
              CHECK(c.screen == Screen::Face || c.screen == Screen::Cockpit, "Back from %s did not reach the face/workout in %d presses", name(m.screen), n);
              faceReturns++;
          }
      }
      CHECK(maxStack <= size_t(Model::MAX_STACK), "history bounded (max %zu)", maxStack);
      CHECK(m.log.size() <= 64, "log bounded");
      std::printf("random soak: 200000 inputs, max history %zu, %d back-to-home checks\n", maxStack, faceReturns); }

    std::printf("navigation tests: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
