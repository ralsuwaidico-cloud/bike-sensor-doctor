#pragma once
// Cyclift Watch v3 — Stage 1 proof-of-concept state model (no LVGL, no Arduino: compiled and unit-tested on a computer).
// Owns navigation, the simulated ride and the simulated iPhone. The LVGL layer (cyv3_ui) only draws this state and turns
// touches into Actions. Nothing here talks to Bluetooth: the "iPhone" is simulated with the same pending → confirmed /
// refused / no-answer outcomes as the approved prototype, so the screens can be checked before Stage 4.
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#include "cyv3_strings.hpp"
#include "cyv3_tokens.hpp"

namespace cyw::v3 {

// Stage 1.3 adds the face neighbourhood of the approved prototype (screens1.js): Today, Week strip, Quick Settings, the
// three glance widgets, and an explicit "not in this release" page for menu destinations that are not built yet.
// Stage 1.4 (button system, owner decisions G1–G11, 12 Nov): workout Controls, End and Restart confirmations, and the
// three approved chart pages of a ride (prototype chartPage: power, heart rate, cadence).
enum class Screen : uint8_t { Face, Menu, Cockpit, Today, Week, Quick, WHealth, WCoach, WActivity, NotYet,
                              Controls, EndConfirm, RestartConfirm, RidePower, RideHr, RideCad };
enum class Mode : uint8_t { Wrist, Bike, Gym };
enum class Density : uint8_t { Standard, Focused };
enum class TextSize : uint8_t { Default, Large };
enum class Swipe : uint8_t { Left, Right, Up, Down };
enum class WkState : uint8_t { None, Active, Paused };
enum class Cmd : uint8_t { None, Pause, Resume, Lap, End };
enum class Reply : uint8_t { Accept, Refuse, NoAnswer };   // what the simulated iPhone does with the next command

/// Actions the UI layer can raise from a touch (each maps to one hit area on screen).
enum class Action : uint8_t { None, MenuItem, MenuMore, Pause, Resume, DismissToast, QsRow, QsMore, Go, StartPlan, Choice };
/// Rows of the workout Controls overlay in button order (G7: Pause / Resume first and highlighted on opening).
enum class Ctl : uint8_t { PauseResume, Lap, End, Why, Menu };

/// Menu entries in prototype order. Stage 1 implements WatchFace, Activities (starts the simulated ride) and
/// ReturnToWorkout; the others are drawn as approved but are not wired yet (their screens arrive in Stage 3).
enum class MenuId : uint8_t { ReturnToWorkout, WatchFace, Today, Activities, Health, Coach, History, Utilities, Settings };

struct Settings {
    ThemeId theme = ThemeId::Obsidian; Density density = Density::Standard; TextSize text = TextSize::Default; Lang lang = Lang::En;
    int brightness = 70; bool dnd = false; Mode mode = Mode::Wrist;   // Quick Settings (RAM only; nothing is saved to flash)
};
/// Quick Settings rows in prototype order.
enum class QsRow : uint8_t { Brightness, Theme, Dnd, Mode, Lock };

/// Sensor presence as the iPhone reports it (Stage 1: simulated). A missing value is -1 everywhere.
struct Sensors { bool power = true, hr = true, cadence = true; };
struct Metrics { int power = -1, hr = -1, cadence = -1; };

struct Toast {
    enum Kind : uint8_t { None, Ok, Crit, Info } kind = None;
    S text = S::ToastPaused; bool hasSub = false; S sub = S::NoAnswer; uint32_t untilMs = 0;
};

struct Clock { bool valid = true; int hh = 10, mm = 9, weekday = 0, day = 8, month = 11; };   // Sun 8 Nov 10:09 (prototype QA time)

class Model {
public:
    // ------------------------------------------------------------------ fixed plan values (from the iPhone in Stage 4)
    static constexpr int TARGET_LO = 235, TARGET_HI = 255, GAUGE_MAX = 400, INTERVALS = 3, INTERVAL_S = 12 * 60;
    static constexpr uint32_t REPLY_MS = 450, NO_ANSWER_MS = 5000, KEY2_WINDOW_MS = 2500, TOAST_MS = 1600, BANNER_MS = 2600;

    Settings settings;
    Screen screen = Screen::Face;
    Clock clock;
    int battery = 64; bool charging = false;
    bool phoneLinked = true, synced = true;
    int movePct = 72, loadPct = 58;
    Sensors sensors;
    Metrics m;
    WkState wk = WkState::None;
    int interval = 2, remainS = 492;            // interval 2 of 3, 8:12 left (prototype QA state)
    int laps = 0;
    int menuScroll = 0, qsScroll = 0;
    bool locked = false;                        // touch lock (G4): touches and swipes ignored; the buttons keep working
    int ctlScroll = 0;                          // Controls shown as a list (Large Text / long Arabic labels): first row shown
    int focus = 0;                              // highlighted row on Menu, Quick Settings, Controls and the confirmations (G9)
    uint32_t endHoldMs = 0;                     // L1 held on a workout screen: 0–2000 ms ring before the End request (G8)
    uint32_t restartMs = 0;                     // L1 + L2 held: 0–10 000 ms restart countdown (G5/G6); 0 = not shown
    bool restartRequested = false;              // the firmware restarts when this becomes true (after the buttons are up)
    static constexpr int HIST = 90;             // chart pages: the last 90 s (prototype chartPage slice(-90))
    std::vector<int> histP, histHr, histCad;
    long powSum = 0; int powN = 0;              // ride average power (seconds with a power value)
    int elapsedS() const { return t_; }
    /// Mean of the last n seconds of a history (-1 = no values); n = 0 → the whole ride (power only).
    int recent(const std::vector<int>& h, int n) const {
        if (n == 0) return powN ? int((powSum + powN / 2) / powN) : -1;
        long s = 0; int c = 0; for (int i = int(h.size()) - 1; i >= 0 && i >= int(h.size()) - n; i--) if (h[i] >= 0) { s += h[i]; c++; }
        return c ? int((s + c / 2) / c) : -1;
    }
    MenuId notYet = MenuId::Health;             // which destination the "not in this release" page stands for
    bool simRideNotice = false;                 // show "Simulated ride" once when a ride starts without an iPhone
    static constexpr int MAX_STACK = 8;
    std::vector<Screen> stack;                  // back history (prototype ST.stack), bounded
    Cmd pending = Cmd::None; uint32_t pendingSinceMs = 0;
    Reply nextReply = Reply::Accept;
    bool key2Armed = false; uint32_t key2UntilMs = 0;
    Toast toast;
    bool simulate = true;                       // false: tests set metrics directly
    std::vector<std::string> log;               // what happened, for the serial console and the tests

    // ------------------------------------------------------------------ queries used by the UI
    bool inWorkout() const { return wk == WkState::Active || wk == WkState::Paused; }
    bool focused() const { return settings.density == Density::Focused || settings.text == TextSize::Large; }   // Large Text uses the focused cockpit
    bool large() const { return settings.text == TextSize::Large; }
    bool rtl() const { return settings.lang == Lang::Ar; }

    static bool workoutPage(Screen s) { return s == Screen::Cockpit || s == Screen::RidePower || s == Screen::RideHr || s == Screen::RideCad; }
    /// Pages R2 steps through during a ride (prototype PAGES.ride; Bike mode keeps cockpit + power). Pacing, climb, navigation
    /// and coach pages are designed but not built yet.
    std::vector<Screen> ridePages() const {
        if (bike()) return {Screen::Cockpit, Screen::RidePower};
        return {Screen::Cockpit, Screen::RidePower, Screen::RideHr, Screen::RideCad};
    }
    int pageIndex() const { auto p = ridePages(); for (int i = 0; i < int(p.size()); i++) if (p[i] == screen) return i; return -1; }
    /// Rows of the screen that has a highlight (0 = none).
    int focusCount() const {
        switch (screen) {
            case Screen::Menu: return int(menuItems().size());
            case Screen::Quick: return QS_ROWS;
            case Screen::Controls: return 5;
            case Screen::EndConfirm: case Screen::RestartConfirm: return 2;
            default: return 0;
        }
    }
    std::vector<MenuId> menuItems() const {
        std::vector<MenuId> v;
        if (inWorkout()) v.push_back(MenuId::ReturnToWorkout);
        for (MenuId id : {MenuId::WatchFace, MenuId::Today, MenuId::Activities, MenuId::Health, MenuId::Coach, MenuId::History, MenuId::Utilities, MenuId::Settings}) v.push_back(id);
        return v;
    }
    int menuMaxScroll() const { return std::max(0, int(menuItems().size()) - 2); }
    static bool menuImplemented(MenuId id) { return id == MenuId::ReturnToWorkout || id == MenuId::WatchFace || id == MenuId::Activities || id == MenuId::Today; }
    static constexpr int QS_ROWS = 5;
    int qsMaxScroll() const { return QS_ROWS - 2; }
    bool bike() const { return settings.mode == Mode::Bike; }
    /// Screens reached sideways from the face (no back history: the prototype resets the stack for these).
    static bool faceLevel(Screen s) { return s == Screen::Face || s == Screen::WHealth || s == Screen::WCoach || s == Screen::WActivity; }

    /// Grade of a power value against the target band (prototype gradeOf): on, adjust or far.
    enum class Grade : uint8_t { None, On, Adjust, Far };
    static Grade gradeOf(int p) {
        if (p < 0) return Grade::None;
        if (p >= TARGET_LO && p <= TARGET_HI) return Grade::On;
        if (p < TARGET_LO - 25 || p > TARGET_HI + 40) return Grade::Far;
        return Grade::Adjust;
    }
    /// The one command line under the lead metric (prototype commandLine).
    struct Command { std::string text; enum Color : uint8_t { Ink2, On, Adjust, Far, Crit } color; };
    Command command() const {
        Lang l = settings.lang;
        if (!phoneLinked) return {tr(S::PhoneLost, l), Command::Crit};
        if (m.power < 0) return m.hr < 0 ? Command{tr(S::WaitingHr, l), Command::Ink2} : Command{trf(S::HrBand, l, 140, 155), Command::Ink2};
        int mid = (TARGET_LO + TARGET_HI) / 2;
        auto c = [](Grade g) { return g == Grade::On ? Command::On : g == Grade::Far ? Command::Far : Command::Adjust; };
        if (m.power > TARGET_HI) return {tr(S::EaseOff, l), c(gradeOf(m.power))};
        if (m.power < TARGET_LO) return {trf(S::PushTo, l, mid), c(gradeOf(m.power))};
        return {trf(S::Hold, l, mid), Command::On};
    }

    // ------------------------------------------------------------------ inputs: physical buttons (decoded by cyv3_keys.hpp)
    // Do / Back / Next (owner G2): L1 = the screen's primary action (Menu where there is none), L2 = Back, R2 = Next.
    // The touch lock (G4) never blocks the buttons.
    void pressL1(uint32_t now) {
        endHoldMs = 0;
        if (focusCount() > 0) { activate(now); note("L1: select"); return; }
        if (workoutPage(screen) && inWorkout()) { go(Screen::Controls); focus = int(Ctl::PauseResume); note("L1: controls"); return; }   // G7
        switch (screen) {
            case Screen::WHealth: notYet = MenuId::Health; go(Screen::NotYet); break;      // widget → its app (not built yet)
            case Screen::WCoach: notYet = MenuId::Coach; go(Screen::NotYet); break;
            case Screen::WActivity: notYet = MenuId::History; go(Screen::NotYet); break;
            case Screen::Today: if (inWorkout()) toWorkout(); else if (synced) startRide(now); else go(Screen::Menu); break;
            default: go(Screen::Menu); break;
        }
        note("L1");
    }
    void pressL2(uint32_t now) {
        if (workoutPage(screen) && inWorkout()) {                                      // approved V8: two presses within 2.5 s = Lap
            if (key2Armed && now <= key2UntilMs) { key2Armed = false; send(Cmd::Lap, now); note("L2 second press: lap"); return; }
            key2Armed = true; key2UntilMs = now + KEY2_WINDOW_MS; note("L2 first press: lap armed"); return;
        }
        back(); note("L2: back");
    }
    void pressR2(uint32_t now) {
        (void)now;
        int n = focusCount();
        if (n > 0) { focus = (focus + 1) % n; keepFocusVisible(); note("R2: next row"); return; }
        if (workoutPage(screen) && inWorkout()) { auto p = ridePages(); int i = pageIndex(); set(p[(i + 1) % int(p.size())]); key2Armed = false; note("R2: next page"); return; }
        switch (screen) {
            case Screen::Face: stack.clear(); set(Screen::WHealth); break;
            case Screen::WHealth: set(Screen::WCoach); break;
            case Screen::WCoach: set(Screen::WActivity); break;
            case Screen::WActivity: set(Screen::Face); break;
            case Screen::Today: go(Screen::Week); break;
            default: note("R2: nothing next"); return;
        }
        note("R2: next");
    }
    /// L1 held 1 s: Quick Settings outside a workout; in a workout the hold continues toward End (hold2).
    void holdL1(uint32_t now) {
        (void)now;
        if (inWorkout() && (workoutPage(screen) || screen == Screen::Controls)) return;
        if (screen == Screen::EndConfirm || screen == Screen::RestartConfirm) return;   // a confirmation is answered, not left
        if (screen != Screen::Quick) { go(Screen::Quick); note("L1 hold: quick settings"); }
    }
    /// L1 held 2 s on a workout screen: the End request → explicit confirmation, Cancel highlighted (G8).
    void holdL1Long(uint32_t now) {
        (void)now; endHoldMs = 0;
        if (inWorkout() && (workoutPage(screen) || screen == Screen::Controls)) { if (screen == Screen::Controls) set(Screen::EndConfirm); else go(Screen::EndConfirm); focus = 0; note("L1 hold 2 s: end request"); }
    }
    /// While L1 is down on a workout screen the UI draws a ring (0–2 s); released early = nothing happens.
    void setEndHold(uint32_t ms) { endHoldMs = (inWorkout() && (workoutPage(screen) || screen == Screen::Controls) && ms >= 300) ? std::min<uint32_t>(ms, 2000) : 0; }
    void holdL2(uint32_t now) { (void)now; key2Armed = false; if (inWorkout()) toWorkout(); else home(); note("L2 hold: home"); }
    void holdR2(uint32_t now) { (void)now; locked = !locked; note(locked ? "touch locked" : "touch unlocked"); }
    /// L1 + L2 chord (G5/G6): countdown shown from 2 s; 10 s → restart (with an explicit warning during a workout).
    void chordTick(uint32_t ms) { key2Armed = false; endHoldMs = 0; restartMs = ms >= 2000 ? std::min<uint32_t>(ms, 10000) : 0; }
    void chordCancel() { restartMs = 0; note("restart cancelled"); }
    void chordFire(uint32_t now) {
        (void)now; restartMs = 0;
        if (inWorkout()) { go(Screen::RestartConfirm); focus = 0; note("restart: workout running, asking"); return; }
        restartRequested = true; note("restart requested (buttons)");
    }
    // legacy names used by the serial console and older tests: Key 1 = L1, Key 2 = L2
    void key1(uint32_t now) { pressL1(now); }
    void key2(uint32_t now) { pressL2(now); }

    /// Swipe map of the approved prototype (app.js swipe + each screen's swipe table). Face and widgets keep the same
    /// physical directions in Arabic (prototype rule); other screens mirror left/right in right-to-left.
    void swipe(Swipe d) {
        if (locked) { note("swipe ignored: locked"); return; }
        Swipe backward = rtl() ? Swipe::Left : Swipe::Right;
        Screen to = screen; bool has = true;
        switch (screen) {
            case Screen::Face: to = d == Swipe::Up ? Screen::Today : d == Swipe::Down ? Screen::Quick : d == Swipe::Left ? Screen::WHealth : Screen::WActivity; break;
            case Screen::WHealth: if (d == Swipe::Right) to = Screen::Face; else if (d == Swipe::Left) to = Screen::WCoach; else has = false; break;
            case Screen::WCoach: if (d == Swipe::Right) to = Screen::WHealth; else if (d == Swipe::Left) to = Screen::WActivity; else has = false; break;
            case Screen::WActivity: if (d == Swipe::Right) to = Screen::WCoach; else if (d == Swipe::Left) to = Screen::Face; else has = false; break;
            case Screen::Today: if (d == Swipe::Down) to = Screen::Face; else if (d == Swipe::Up) to = Screen::Week; else has = false; break;
            case Screen::Week: if (d == Swipe::Down) to = Screen::Today; else has = false; break;
            case Screen::Quick: if (d == Swipe::Up) to = Screen::Face; else has = false; break;
            default: has = false; break;
        }
        if (has) {
            if (faceLevel(screen) || faceLevel(to)) { stack.clear(); set(to); }   // prototype: face-level targets reset history
            else go(to);
        } else if (screen == Screen::Menu || screen == Screen::Quick) {
            if (d == Swipe::Up) scroll(+1); else if (d == Swipe::Down) scroll(-1); else if (d == backward) back();
        } else if (workoutPage(screen) && inWorkout()) {                                // prototype: sideways swipes change page
            auto p = ridePages(); int i = std::max(0, pageIndex()), n = int(p.size());
            Swipe fwd = rtl() ? Swipe::Right : Swipe::Left;
            if (d == fwd) set(p[(i + 1) % n]); else if (d == backward) set(p[(i + n - 1) % n]); else if (d == Swipe::Up) { go(Screen::Controls); focus = 0; }
        } else if (screen == Screen::Controls && (d == Swipe::Up || (d == Swipe::Down && ctlScroll > 0))) {
            ctlScroll = std::max(0, std::min(CTL_MAX_SCROLL, ctlScroll + (d == Swipe::Up ? 1 : -1)));
        } else if (screen == Screen::Controls || screen == Screen::EndConfirm || screen == Screen::RestartConfirm) {
            if (d == backward || d == Swipe::Down) back();
        } else if (d == backward) back();
        note(std::string("swipe ") + "LRUD"[int(d)]);
    }
    void act(Action a, int arg, uint32_t now) {
        if (locked) { note("tap ignored: locked"); return; }
        switch (a) {
            case Action::MenuItem: selectMenu(MenuId(arg), now); break;
            case Action::MenuMore: scroll(+1); break;
            case Action::QsMore: scroll(+1); break;
            case Action::QsRow: quick(QsRow(arg)); break;
            case Action::Go: go(Screen(arg)); break;
            case Action::StartPlan: if (!inWorkout()) startRide(now); else toWorkout(); break;
            case Action::Pause: if (wk == WkState::Active && pending == Cmd::None) send(Cmd::Pause, now); break;
            case Action::Resume: if (wk == WkState::Paused && pending == Cmd::None) send(Cmd::Resume, now); break;
            case Action::DismissToast: toast.kind = Toast::None; break;
            case Action::Choice: focus = arg; activate(now); break;
            case Action::None: break;
        }
    }
    void home() { stack.clear(); set(Screen::Face); }
    void toWorkout() { stack.clear(); set(Screen::Cockpit); }
    bool workoutScreen() const { return workoutPage(screen) || screen == Screen::Controls || screen == Screen::EndConfirm || screen == Screen::RestartConfirm; }
    /// Back (prototype back()): previous screen, else the workout, else the face. The cockpit's back is the menu (Stage 1).
    void back() {
        if (workoutPage(screen)) { go(Screen::Menu); return; }
        if (!stack.empty()) { Screen s = stack.back(); stack.pop_back(); set(s); return; }
        if (inWorkout()) toWorkout(); else home();
    }
    /// Demo data (serial 'E'): the simulated iPhone's synced values; off = honest "not synced" states everywhere.
    void setDemo(bool on) { synced = on; movePct = on ? 72 : 0; loadPct = on ? 58 : 0; note(on ? "demo data on" : "demo data off"); }
    /// Hook for the Bluetooth TimeSync payload (Stage 4) and the temporary serial command: the clock's local time.
    void setClock(const Clock& c) { clock = c; }

    void startRide(uint32_t now) {
        wk = WkState::Active; interval = 2; remainS = 492; laps = 0; lastSecMs_ = now; histP.clear(); histHr.clear(); histCad.clear(); powSum = 0; powN = 0; t_ = 0;
        toWorkout(); note("ride started (simulated)");
        if (simRideNotice) toast = {Toast::Info, S::SimRide, true, S::SimRideSub, now + BANNER_MS};   // values never mistaken for sensors
    }

    /// Advances time: simulated sensors (1 Hz), the interval clock, command replies, toasts, the Key 2 window.
    void tick(uint32_t now) {
        if (key2Armed && now > key2UntilMs) key2Armed = false;
        if (toast.kind != Toast::None && now > toast.untilMs) toast.kind = Toast::None;
        if (pending != Cmd::None) {
            uint32_t waited = now - pendingSinceMs;
            if (nextReply == Reply::NoAnswer ? waited >= NO_ANSWER_MS : waited >= REPLY_MS) resolve(now);
        }
        if (now - lastSecMs_ >= 1000) {
            uint32_t steps = (now - lastSecMs_) / 1000; lastSecMs_ += steps * 1000;
            for (uint32_t i = 0; i < steps; i++) second();
        }
    }

    /// Fixes the simulated sensor values (tests and the comparison states use exact prototype values).
    void setMetrics(int power, int hr, int cadence) {
        simulate = false; sensors = {power >= 0, hr >= 0, cadence >= 0}; m = {power, hr, cadence};
    }

private:
    uint32_t lastSecMs_ = 0, rng_ = 0x2026110Bu; int t_ = 0;
    void note(const std::string& s) { log.push_back(s); if (log.size() > 64) log.erase(log.begin()); }
    /// Opens `s`, remembering the current screen for Back. Going to the screen that Back would return to pops instead,
    /// so repeated gestures (Today ↔ Week, Menu ↔ page) never pile up duplicate history (owner test requirement, 11 Nov).
    void go(Screen s) {
        if (s == screen) return;
        if (!stack.empty() && stack.back() == s) { stack.pop_back(); set(s); return; }
        stack.push_back(screen); if (int(stack.size()) > MAX_STACK) stack.erase(stack.begin());
        set(s);
    }
    void set(Screen s) {
        if (s == Screen::Menu && screen != Screen::Menu) menuScroll = 0;
        if (s == Screen::Quick && screen != Screen::Quick) qsScroll = 0;
        if (s == Screen::Controls && screen != Screen::Controls) ctlScroll = 0;
        if (s != screen) focus = 0;
        if (!workoutPage(s)) key2Armed = false;
        screen = s;
    }
    void keepFocusVisible() {
        if (screen == Screen::Menu) menuScroll = std::max(0, std::min(menuMaxScroll(), focus - 1));
        if (screen == Screen::Quick) qsScroll = std::max(0, std::min(qsMaxScroll(), focus - 1));
        if (screen == Screen::Controls) ctlScroll = std::max(0, std::min(CTL_MAX_SCROLL, focus - 1));
    }
    static constexpr int CTL_MAX_SCROLL = 3;
    /// L1 (or a tap) on the highlighted row.
    void activate(uint32_t now) {
        switch (screen) {
            case Screen::Menu: { auto it = menuItems(); if (focus < int(it.size())) selectMenu(it[focus], now); break; }
            case Screen::Quick: quick(QsRow(focus)); break;
            case Screen::Controls:
                switch (Ctl(focus)) {
                    case Ctl::PauseResume: if (pending == Cmd::None) send(wk == WkState::Paused ? Cmd::Resume : Cmd::Pause, now); back(); break;
                    case Ctl::Lap: if (pending == Cmd::None) send(Cmd::Lap, now); back(); break;
                    case Ctl::End: set(Screen::EndConfirm); focus = 0; break;   // replaces Controls: Cancel returns to the ride
                    case Ctl::Why: notYet = MenuId::Coach; go(Screen::NotYet); break;
                    case Ctl::Menu: go(Screen::Menu); break;
                }
                break;
            case Screen::EndConfirm: if (focus == 1 && pending == Cmd::None) send(Cmd::End, now); else if (focus == 0) back(); break;
            case Screen::RestartConfirm: if (focus == 1) { restartRequested = true; note("restart confirmed during a workout"); } else back(); break;
            default: break;
        }
    }
    void scroll(int d) {
        if (screen == Screen::Quick) qsScroll = std::max(0, std::min(qsMaxScroll(), qsScroll + d));
        else menuScroll = std::max(0, std::min(menuMaxScroll(), menuScroll + d));
    }
    void quick(QsRow r) {
        switch (r) {
            case QsRow::Brightness: { static const int L[] = {30, 50, 70, 100}; int i = 0; while (i < 3 && L[i] != settings.brightness) i++;
                settings.brightness = L[(i + 1) % 4]; break; }
            case QsRow::Theme: settings.theme = ThemeId((int(settings.theme) + 1) % 6); break;
            case QsRow::Dnd: settings.dnd = !settings.dnd; break;
            case QsRow::Mode: settings.mode = Mode((int(settings.mode) + 1) % 3); break;
            case QsRow::Lock: locked = !locked; if (locked) home(); break;
        }
        note("quick settings");
    }
    void selectMenu(MenuId id, uint32_t now) {
        switch (id) {
            case MenuId::ReturnToWorkout: toWorkout(); break;
            case MenuId::WatchFace: home(); break;
            case MenuId::Activities: if (!inWorkout()) startRide(now); else toWorkout(); break;
            case MenuId::Today: go(Screen::Today); break;
            default: notYet = id; go(Screen::NotYet); note("destination not in this release"); break;
        }
    }
    void send(Cmd c, uint32_t now) {
        if (!phoneLinked) {                     // approved: workout commands are refused at once while the phone is lost
            // shown as a banner (result + reason): the one-line pill does not fit the round screen at its approved position
            S fail = c == Cmd::Pause ? S::UnablePause : c == Cmd::Resume ? S::UnableResume : c == Cmd::End ? S::UnableEnd : S::UnableLap;
            toast = {Toast::Crit, fail, true, S::PhoneLostUseIphone, now + BANNER_MS}; note("command refused: phone lost"); return;
        }
        pending = c; pendingSinceMs = now; toast.kind = Toast::None; note("command sent (simulated iPhone)");
    }
    void resolve(uint32_t now) {
        Cmd c = pending; pending = Cmd::None;
        S fail = c == Cmd::Pause ? S::UnablePause : c == Cmd::Resume ? S::UnableResume : c == Cmd::End ? S::UnableEnd : S::UnableLap;
        if (nextReply == Reply::Accept) {
            if (c == Cmd::End) { wk = WkState::None; key2Armed = false; home(); toast = {Toast::Ok, S::ToastEnded, true, S::IphoneKeepsRecord, now + BANNER_MS}; }
            if (c == Cmd::Pause) { wk = WkState::Paused; toast = {Toast::Ok, S::ToastPaused, false, S::NoAnswer, now + TOAST_MS}; }
            if (c == Cmd::Resume) { wk = WkState::Active; toast = {Toast::Ok, S::ToastResumed, false, S::NoAnswer, now + TOAST_MS}; }
            if (c == Cmd::Lap) { laps++; toast = {Toast::Ok, S::ToastLapSaved, false, S::NoAnswer, now + TOAST_MS}; }
            note("command confirmed");
        } else {
            toast = {Toast::Crit, fail, true, nextReply == Reply::Refuse ? S::WorkoutChanged : S::NoAnswer, now + BANNER_MS};
            note(nextReply == Reply::Refuse ? "command refused by iPhone" : "no answer from iPhone");
            nextReply = Reply::Accept;
        }
    }
    uint32_t rand_() { rng_ = rng_ * 1664525u + 1013904223u; return rng_ >> 8; }
    int noise(int amp) { return int(rand_() % uint32_t(2 * amp + 1)) - amp; }
    void second() {
        if (wk == WkState::Active) {
            t_++;
            if (--remainS <= 0) { interval = interval % INTERVALS + 1; remainS = INTERVAL_S; }
        }
        if (simulate && wk == WkState::Active) {
            // a rider holding the 235–255 W band with drift and the odd surge; heart rate and cadence follow slowly
            int surge = (t_ % 47 < 4) ? 60 : (t_ % 61 < 3 ? -45 : 0);
            m.power = sensors.power ? std::max(0, 246 + noise(9) + surge) : -1;
            m.hr = sensors.hr ? 150 + (t_ / 20) % 5 + noise(1) : -1;
            m.cadence = sensors.cadence ? 91 + noise(3) : -1;
        } else if (simulate && wk == WkState::Paused) {   // paused: the last ride values stay on screen; heart rate settles slowly
            if (!sensors.power) m.power = -1;
            if (!sensors.cadence) m.cadence = -1;
            m.hr = sensors.hr ? std::max(100, (m.hr < 0 ? 150 : m.hr) - 1) : -1;
        }
        if (wk == WkState::Active) {                        // chart pages: one sample per second while riding (-1 = no sensor)
            for (auto* h : {&histP, &histHr, &histCad}) if (int(h->size()) >= HIST) h->erase(h->begin());
            histP.push_back(m.power); histHr.push_back(m.hr); histCad.push_back(m.cadence);
            if (m.power >= 0) { powSum += m.power; powN++; }
        }
    }
};

} // namespace cyw::v3
