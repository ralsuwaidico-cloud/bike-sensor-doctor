// Stage 1.4 — button system tests (computer, no hardware). Raw button levels are fed through the SAME path the watch uses
// (cyv3_input.hpp: KeyDecoder → model), sampled every 10 ms like the firmware loop. Expected results come from the owner's
// decisions of 12 Nov 2026 (G2–G10) and BUTTON_UX_RECOMMENDATION.md §3, not from the implementation.
#include "../../src/ui/v3/cyv3_input.hpp"
#include <cstdio>
#include <string>
using namespace cyw::v3;

static int g_checks = 0, g_fail = 0;
#define CHECK(c, ...) do { g_checks++; if (!(c)) { g_fail++; std::printf("FAIL %s:%d  ", __FILE__, __LINE__); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

enum : int { L1 = 1, L2 = 2, R2 = 4 };

struct Rig {
    Model m; ButtonInput in; uint32_t t = 100000;
    Rig() { m.tick(t); }
    /// Hold `mask` for `ms`, then release and let 200 ms pass (all at 10 ms steps, model ticked like the firmware).
    void hold(int mask, uint32_t ms, uint32_t after = 200) { level(mask, ms); level(0, after); }
    void level(int mask, uint32_t ms) {
        for (uint32_t e = 0; e < ms; e += 10) { t += 10; in.sample(m, mask & L1, mask & L2, mask & R2, t); m.tick(t); }
    }
    void press(int mask) { hold(mask, 120); }
    void wait(uint32_t ms) { level(0, ms); }
    void startRide() { m.key1(t); m.act(Action::MenuItem, int(MenuId::Activities), t); }
};

static const char* nm(Screen s) {
    static const char* n[] = {"Face", "Menu", "Cockpit", "Today", "Week", "Quick", "WHealth", "WCoach", "WActivity", "NotYet",
                              "Controls", "EndConfirm", "RestartConfirm", "RidePower", "RideHr", "RideCad"};
    return n[int(s)];
}

static void selectBackNext() {
    Rig r;
    r.press(L1); CHECK(r.m.screen == Screen::Menu && r.m.focus == 0, "Face + L1 = Menu, first row highlighted (%s)", nm(r.m.screen));
    r.press(R2); r.press(R2); CHECK(r.m.focus == 2, "R2 moves the highlight (focus %d)", r.m.focus);
    auto items = r.m.menuItems(); CHECK(items[2] == MenuId::Activities, "row 2 = Activities");
    r.press(L2); CHECK(r.m.screen == Screen::Face, "L2 = Back");
    r.press(L1); CHECK(r.m.focus == 0, "reopened menu starts at the first row");
    for (int i = 0; i < int(items.size()); i++) r.press(R2);
    CHECK(r.m.focus == 0, "the highlight wraps after the last row");
    for (int i = 0; i < 7; i++) r.press(R2);
    CHECK(r.m.focus == 7 && r.m.menuScroll == r.m.menuMaxScroll(), "the highlighted row is scrolled into view (scroll %d)", r.m.menuScroll);
    r.press(L1); CHECK(r.m.screen == Screen::NotYet, "L1 opens the highlighted row (Settings: not in this release)");
    r.press(L2); r.press(L2); CHECK(r.m.screen == Screen::Face, "Back, Back = face");
    r.press(R2); CHECK(r.m.screen == Screen::WHealth, "Face + R2 = next widget");
    r.press(R2); r.press(R2); r.press(R2); CHECK(r.m.screen == Screen::Face, "R2 x4 = round the widgets");
    r.hold(L1, 1200); CHECK(r.m.screen == Screen::Quick, "hold L1 1 s outside a workout = Quick Settings");
    r.press(R2); r.press(R2); r.press(R2); r.press(R2);
    CHECK(r.m.focus == 4, "Quick Settings: R2 moves the highlight to Lock (row %d)", r.m.focus);
    r.hold(L2, 1200); CHECK(r.m.screen == Screen::Face, "hold L2 = home");
    r.m.swipe(Swipe::Up); CHECK(r.m.screen == Screen::Today, "Today");
    r.press(R2); CHECK(r.m.screen == Screen::Week, "Today + R2 = Week");
    r.press(L2); CHECK(r.m.screen == Screen::Today, "Week + L2 = Today");
}

static void rideControls(bool ar) {
    Rig r; r.m.settings.lang = ar ? Lang::Ar : Lang::En; r.startRide(); r.wait(500);
    const char* L = ar ? "AR" : "EN";
    CHECK(r.m.screen == Screen::Cockpit && r.m.wk == WkState::Active, "%s ride started", L);
    // G7: L1 opens Controls with Pause highlighted; a second deliberate L1 confirms
    r.press(L1); CHECK(r.m.screen == Screen::Controls && r.m.focus == int(Ctl::PauseResume), "%s L1 = Controls, Pause highlighted", L);
    CHECK(r.m.wk == WkState::Active && r.m.pending == Cmd::None, "%s opening Controls changes nothing yet", L);
    r.press(L1); CHECK(r.m.pending == Cmd::Pause || r.m.wk == WkState::Paused, "%s 2nd L1 = Pause sent", L);
    r.wait(800); CHECK(r.m.wk == WkState::Paused && r.m.screen == Screen::Cockpit, "%s paused, back on the ride (%s)", L, nm(r.m.screen));
    r.press(L1); r.press(L1); r.wait(800); CHECK(r.m.wk == WkState::Active, "%s L1 L1 = Resume", L);
    // Controls: L2 closes without acting
    r.press(L1); r.press(L2); r.wait(800); CHECK(r.m.screen == Screen::Cockpit && r.m.wk == WkState::Active, "%s Controls + L2 = close, no action", L);
    // Lap: L2 twice within 2.5 s on any ride page
    int laps = r.m.laps;
    r.press(L2); CHECK(r.m.screen == Screen::Cockpit && r.m.key2Armed, "%s L2 once = lap armed, still riding", L);
    r.wait(600); r.press(L2); r.wait(800); CHECK(r.m.laps == laps + 1, "%s L2 L2 = lap", L);
    r.press(L2); r.wait(2700); r.press(L2); r.wait(800); CHECK(r.m.laps == laps + 1 && r.m.screen == Screen::Cockpit, "%s presses 2.8 s apart: no lap, no Back", L);
    r.wait(2700);
    // R2: next data page, wraps
    Screen seq[] = {Screen::RidePower, Screen::RideHr, Screen::RideCad, Screen::Cockpit};
    for (Screen s : seq) { r.press(R2); CHECK(r.m.screen == s, "%s R2 → %s (got %s)", L, nm(s), nm(r.m.screen)); }
    r.press(R2); laps = r.m.laps; r.press(L2); r.wait(300); r.press(L2); r.wait(800);
    CHECK(r.m.laps == laps + 1 && r.m.screen == Screen::RidePower, "%s lap works on a data page too", L);
    r.press(L1); CHECK(r.m.screen == Screen::Controls, "%s L1 on a data page = Controls", L);
    r.press(L2); CHECK(r.m.screen == Screen::RidePower, "%s closing Controls returns to the same page", L);
    // the menu is reached through Controls → Menu; L2 hold returns to the ride
    r.press(L1); for (int i = 0; i < 4; i++) r.press(R2); r.press(L1);
    CHECK(r.m.screen == Screen::Menu, "%s Controls → Menu", L);
    r.hold(L2, 1200); CHECK(Model::workoutPage(r.m.screen), "%s hold L2 = back to the ride", L);
    // Bike mode: two pages
    r.m.settings.mode = Mode::Bike; r.m.toWorkout(); r.press(R2); r.press(R2);
    CHECK(r.m.screen == Screen::Cockpit, "%s Bike mode: Cockpit ↔ Power", L);
    r.m.settings.mode = Mode::Wrist;
}

static void endFlow() {
    Rig r; r.startRide(); r.wait(500);
    // releasing before 2 s does nothing (ring only)
    r.level(L1, 200); CHECK(r.m.endHoldMs == 0, "no ring before 0.3 s");
    r.level(L1, 800); CHECK(r.m.endHoldMs >= 900 && r.m.endHoldMs <= 1100, "ring at ~1 s (%u)", r.m.endHoldMs);
    CHECK(r.m.screen == Screen::Cockpit, "1 s hold in a ride does NOT open Quick Settings");
    r.level(L1, 500); r.level(0, 300);
    CHECK(r.m.screen == Screen::Cockpit && r.m.endHoldMs == 0 && r.m.wk == WkState::Active, "released at 1.5 s: nothing happens (%s)", nm(r.m.screen));
    // G8: hold 2 s → confirmation with Cancel highlighted
    r.hold(L1, 2100); CHECK(r.m.screen == Screen::EndConfirm && r.m.focus == 0, "hold L1 2 s = End request, Cancel highlighted");
    CHECK(r.m.wk == WkState::Active && r.m.pending == Cmd::None, "the request alone ends nothing");
    r.press(L1); CHECK(Model::workoutPage(r.m.screen) && r.m.wk == WkState::Active, "L1 on Cancel = back to the ride");
    r.hold(L1, 2100); r.press(L2); CHECK(r.m.screen == Screen::Cockpit && r.m.wk == WkState::Active, "L2 on the confirmation = cancel");
    r.hold(L1, 2100); r.hold(L1, 1200); CHECK(r.m.screen == Screen::EndConfirm, "L1 hold on the confirmation does not leave it");
    r.press(L2); r.hold(L1, 2100); r.press(R2); CHECK(r.m.focus == 1, "R2 moves to End");
    r.press(L1); CHECK(r.m.pending == Cmd::End, "L1 on End = End sent");
    r.wait(800); CHECK(!r.m.inWorkout() && r.m.screen == Screen::Face, "ended → face");
    CHECK(r.m.toast.kind == Toast::Ok && r.m.toast.text == S::ToastEnded && r.m.toast.sub == S::IphoneKeepsRecord, "toast: Ride ended · iPhone keeps the record");
    // phone lost: End refused at once, ride continues
    Rig p; p.startRide(); p.wait(500); p.m.phoneLinked = false;
    p.hold(L1, 2100); p.press(R2); p.press(L1);
    CHECK(p.m.inWorkout() && p.m.toast.kind == Toast::Crit && p.m.toast.text == S::UnableEnd, "phone lost: Unable to end");
    // End through Controls
    Rig c; c.startRide(); c.wait(500); c.press(L1); c.press(R2); c.press(R2); CHECK(c.m.focus == int(Ctl::End), "Controls: End row");
    c.press(L1); CHECK(c.m.screen == Screen::EndConfirm && c.m.focus == 0, "Controls → End = confirmation, Cancel highlighted");
}

static void touchLock() {
    Rig r; r.startRide(); r.wait(500);
    r.hold(R2, 1200); CHECK(r.m.locked, "hold R2 = touch lock");
    CHECK(r.m.screen == Screen::Cockpit, "locking does not leave the ride");
    r.m.swipe(Swipe::Left); r.m.act(Action::Pause, 0, r.t); CHECK(r.m.screen == Screen::Cockpit && r.m.pending == Cmd::None, "locked: touch ignored");
    r.press(L1); r.press(L1); r.wait(800); CHECK(r.m.wk == WkState::Paused, "locked: L1 L1 still pauses (G4)");
    r.press(L1); r.press(L1); r.wait(800);
    int laps = r.m.laps; r.press(L2); r.press(L2); r.wait(800); CHECK(r.m.laps == laps + 1, "locked: lap still works");
    r.wait(3000); r.press(R2); CHECK(r.m.screen == Screen::RidePower, "locked: R2 still changes page");
    r.hold(L1, 2100); CHECK(r.m.screen == Screen::EndConfirm, "locked: End request still works");
    r.press(L2); r.hold(R2, 1200); CHECK(!r.m.locked, "hold R2 again = unlock");
}

static void restart() {
    // outside a workout: 10 s of L1 + L2, countdown visible, restart only after release
    { Rig r; r.level(L1 | L2, 1000); CHECK(r.m.restartMs == 0, "no countdown in the first 2 s");
      r.level(L1 | L2, 1500); CHECK(r.m.restartMs >= 2000, "countdown shown after 2 s (%u)", r.m.restartMs);
      r.level(L1 | L2, 7600); CHECK(r.m.restartRequested, "10 s → restart requested");
      CHECK(!r.in.restartReady(r.m), "not executed while the buttons are still held");
      Screen s = r.m.screen; r.level(0, 200); CHECK(r.in.restartReady(r.m), "executed after release");
      CHECK(r.m.screen == s, "no single-button action leaked from the combination (%s)", nm(r.m.screen)); }
    // early release cancels immediately; neither button acts afterwards
    for (uint32_t ms : {300u, 2500u, 9900u}) {
        Rig r; r.level(L1 | L2, ms); r.level(L1, 150); r.level(0, 300);
        CHECK(!r.m.restartRequested && r.m.restartMs == 0, "release at %u ms cancels", ms);
        CHECK(r.m.screen == Screen::Face, "release at %u ms: no Menu / Back / Quick leaked (%s)", ms, nm(r.m.screen));
    }
    // L2 + R2 is not a restart (G5) — and nothing restarts
    { Rig r; r.hold(L2 | R2, 11000); CHECK(!r.m.restartRequested && r.m.restartMs == 0, "L2 + R2 is not the restart combination"); }
    // second button too late (> 1 s): not a combination
    { Rig r; r.level(L1, 600); r.level(L1 | L2, 11000); r.level(0, 300);
      CHECK(r.m.restartRequested, "L2 0.6 s after L1 still pairs (within 1 s)"); }
    { Rig r; r.level(L2, 1100); r.level(L1 | L2, 11000); r.level(0, 300);
      CHECK(!r.m.restartRequested, "L2 held 1.1 s before L1: not a combination"); }
    // during a workout: explicit warning first (G5), Cancel highlighted
    { Rig r; r.startRide(); r.wait(500);
      r.hold(L1 | L2, 10300); CHECK(r.m.screen == Screen::RestartConfirm && r.m.focus == 0 && !r.m.restartRequested, "workout: warning screen, Cancel highlighted");
      CHECK(r.m.inWorkout() && r.m.wk == WkState::Active, "workout untouched by the combination");
      r.press(L1); CHECK(Model::workoutPage(r.m.screen) && !r.m.restartRequested, "Cancel = back to the ride");
      r.hold(L1 | L2, 10300); r.press(R2); r.press(L1); CHECK(r.m.restartRequested && r.in.restartReady(r.m), "Restart chosen explicitly");
      CHECK(r.m.laps == 0 && r.m.pending == Cmd::None, "no lap / command came from the combination"); }
}

static void conflictsAndBounce() {
    // contact bounce shorter than 30 ms is invisible
    { Rig r; for (int i = 0; i < 20; i++) { r.level(L1, 10); r.level(0, 10); } r.wait(300);
      CHECK(r.m.screen == Screen::Face, "bounce: nothing (%s)", nm(r.m.screen)); }
    // a short press fires on release (the hold never also fires a short press)
    { Rig r; r.level(L1, 990); CHECK(r.m.screen == Screen::Face, "nothing while held"); r.level(0, 100); CHECK(r.m.screen == Screen::Menu, "0.99 s = short press on release"); }
    { Rig r; r.hold(L1, 1500); CHECK(r.m.screen == Screen::Quick, "1.5 s = hold only (Quick), no extra short press"); }
    // R2 during a ride never ends, pauses or laps
    { Rig r; r.startRide(); r.wait(500); for (int i = 0; i < 30; i++) r.press(R2); r.hold(R2, 1200); r.hold(R2, 1200);
      CHECK(r.m.wk == WkState::Active && r.m.laps == 0 && r.m.pending == Cmd::None && Model::workoutPage(r.m.screen), "R2 is harmless in a ride"); }
    // L1 + R2 together: both act independently, no restart
    { Rig r; r.hold(L1 | R2, 150); CHECK(!r.m.restartRequested, "L1 + R2: no restart"); }
}

/// Owner checklist of 12 Nov 16:37 ("Protect workout controls"), each item as its own test.
static void ownerProtections() {
    // 1. a restart combination cancels a pending lap and pending navigation
    { Rig r; r.startRide(); r.wait(500); int laps = r.m.laps;
      r.press(L2); CHECK(r.m.key2Armed, "lap armed by one L2 press");
      r.level(L2, 100); r.level(L1 | L2, 3000); r.level(0, 300);           // 2nd L2 press turns into the combination
      r.wait(3000); CHECK(r.m.laps == laps && !r.m.key2Armed && r.m.pending == Cmd::None, "combination cancels the armed lap (no lap)");
      CHECK(Model::workoutPage(r.m.screen), "combination left no navigation behind (%s)", nm(r.m.screen)); }
    { Rig r; r.level(L1, 400); r.level(L1 | L2, 2500); r.level(0, 300);
      CHECK(r.m.screen == Screen::Face, "L1 already down 0.4 s, then L2: no Menu, no Back, no Quick Settings"); }
    // 2. holding a button never also fires a short press (all three buttons, in and out of a ride)
    for (int b : {int(L1), int(L2), int(R2)}) {
        Rig x; x.hold(b, 1500); x.wait(500);
        CHECK(x.in.events == 1 && x.in.last[0].ev != KeyEv::Short, "button %d held 1.5 s: exactly one event (the hold), %u events", b, x.in.events);
    }
    { Rig r; r.startRide(); r.wait(500); uint32_t e0 = r.in.events; r.hold(L1, 2300);
      CHECK(r.m.screen == Screen::EndConfirm && r.in.events - e0 == 2, "ride: L1 held 2.3 s = hold + End request only, no Controls");
      CHECK(r.m.pending == Cmd::None && r.m.wk == WkState::Active, "…and nothing paused"); }
    // 3. double presses are debounced: contact chatter on press and release counts as one press
    { Rig r; r.startRide(); r.wait(500); int laps = r.m.laps;
      auto chatterPress = [&] { for (int k = 0; k < 3; k++) { r.level(L2, 10); r.level(0, 10); } r.level(L2, 120); for (int k = 0; k < 3; k++) { r.level(0, 10); r.level(L2, 10); } r.level(0, 200); };
      chatterPress(); CHECK(r.m.laps == laps && r.m.key2Armed, "one chattering L2 press = armed, NOT a lap");
      r.wait(2700); chatterPress(); r.wait(400); chatterPress(); r.wait(800);
      CHECK(r.m.laps == laps + 1, "two chattering presses = exactly one lap (%d)", r.m.laps - laps); }
    // 4. ending a ride always needs the explicit confirmation: no single press or hold of any button ends it
    for (int b : {int(L1), int(L2), int(R2), L1 | L2, L1 | R2, L2 | R2})
        for (uint32_t ms : {80u, 1200u, 2200u, 11000u}) {
            Rig r; r.startRide(); r.wait(500); r.hold(b, ms); r.wait(800);
            CHECK(r.m.inWorkout() && r.m.pending != Cmd::End, "buttons %d held %u ms: ride still running", b, ms);
        }
    // 5. touch lock never blocks pause, lap, page change or the End request
    { Rig r; r.startRide(); r.wait(500); r.hold(R2, 1200); CHECK(r.m.locked, "locked");
      r.press(L1); r.press(L1); r.wait(800); bool paused = r.m.wk == WkState::Paused; r.press(L1); r.press(L1); r.wait(800);
      int laps = r.m.laps; r.press(L2); r.press(L2); r.wait(800); r.wait(2000); r.press(R2); Screen pg = r.m.screen; r.hold(L1, 2100);
      CHECK(paused && r.m.laps == laps + 1 && pg == Screen::RidePower && r.m.screen == Screen::EndConfirm, "locked: pause, lap, page, End request all work"); }
    // 6. restart during a ride: warning first, Cancel highlighted, warning text says the watch's ride ends
    { Rig r; r.startRide(); r.wait(500); r.hold(L1 | L2, 10300);
      CHECK(r.m.screen == Screen::RestartConfirm && r.m.focus == 0 && !r.m.restartRequested, "ride: warning, Cancel highlighted");
      CHECK(std::string(tr(S::RestartWarn, Lang::En)) == "The ride on the watch ends", "warning text (EN): %s", tr(S::RestartWarn, Lang::En));
      r.press(L2); CHECK(Model::workoutPage(r.m.screen) && !r.m.restartRequested && r.m.inWorkout(), "L2 = Cancel, ride continues"); }
}

static void soak() {
    // random raw levels (incl. bounce) through the real path; invariants:
    //  • the ride ends only from the End confirmation; • a restart happens only after a 10 s combination or the explicit
    //    workout warning; • history stays bounded; • deterministic (same input → same result)
    auto run = [](uint32_t seed, std::string* trace) {
        Rig r; uint32_t rng = seed; int ends = 0, restarts = 0, bad = 0; size_t maxStack = 0;
        for (int step = 0; step < 60000; step++) {
            rng = rng * 1664525u + 1013904223u;
            int mask = int((rng >> 16) % 8); if ((rng >> 24) % 4) mask = 0;
            uint32_t len = 10 + (rng >> 8) % ((rng >> 28) ? 400 : 12000);
            if ((rng >> 12) % 50 == 0) { if (!r.m.inWorkout()) r.startRide(); }
            for (uint32_t e = 0; e < len; e += 10) {
                Screen before = r.m.screen; Cmd pendBefore = r.m.pending; bool wasIn = r.m.inWorkout(); bool wasReq = r.m.restartRequested;
                r.t += 10; r.in.sample(r.m, mask & L1, mask & L2, mask & R2, r.t); r.m.tick(r.t);
                bool endSent = r.m.pending == Cmd::End && pendBefore != Cmd::End;
                if (endSent && before != Screen::EndConfirm) { bad++; if (bad < 4) std::printf("  End sent from %s\n", nm(before)); }
                if (wasIn && !r.m.inWorkout()) ends++;
                if (!wasReq && r.m.restartRequested) {
                    restarts++;
                    bool viaChord = false; for (int k = 0; k < r.in.lastN; k++) if (r.in.last[k].ev == KeyEv::ChordFire) viaChord = true;
                    if (!(viaChord && !wasIn) && before != Screen::RestartConfirm) { bad++; if (bad < 4) std::printf("  restart from %s chord %d\n", nm(before), viaChord); }
                    r.m.restartRequested = false;                    // "restarted"
                }
                maxStack = std::max(maxStack, r.m.stack.size());
            }
        }
        if (trace) *trace = std::to_string(int(r.m.screen)) + "/" + std::to_string(r.m.laps) + "/" + std::to_string(r.in.events) + "/" + std::to_string(r.t);
        CHECK(bad == 0, "soak seed %u: %d invariant violations", seed, bad);
        CHECK(maxStack <= size_t(Model::MAX_STACK), "soak: history bounded (%zu)", maxStack);
        std::printf("button soak seed %u: %u events, %d rides ended, %d restarts, max history %zu\n", seed, r.in.events, ends, restarts, maxStack);
    };
    std::string a, b; run(7, &a); run(7, &b); CHECK(a == b, "deterministic: %s vs %s", a.c_str(), b.c_str());
    run(99, nullptr);
}

int main() {
    selectBackNext(); rideControls(false); rideControls(true); endFlow(); touchLock(); restart(); conflictsAndBounce(); ownerProtections(); soak();
    std::printf("button tests: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
