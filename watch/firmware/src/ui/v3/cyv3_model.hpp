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
enum class Screen : uint8_t { Face, Menu, Cockpit, Today, Week, Quick, WHealth, WCoach, WActivity, NotYet };
enum class Mode : uint8_t { Wrist, Bike, Gym };
enum class Density : uint8_t { Standard, Focused };
enum class TextSize : uint8_t { Default, Large };
enum class Swipe : uint8_t { Left, Right, Up, Down };
enum class WkState : uint8_t { None, Active, Paused };
enum class Cmd : uint8_t { None, Pause, Resume, Lap };
enum class Reply : uint8_t { Accept, Refuse, NoAnswer };   // what the simulated iPhone does with the next command

/// Actions the UI layer can raise from a touch (each maps to one hit area on screen).
enum class Action : uint8_t { None, MenuItem, MenuMore, Pause, Resume, DismissToast, QsRow, QsMore, Go, StartPlan };

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
    bool locked = false;                        // Quick Settings → Screen lock; hold Key 1 to unlock
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

    // ------------------------------------------------------------------ inputs
    void key1(uint32_t now) {                   // approved (app.js key1): menu from anywhere; on the menu → face (or the workout)
        (void)now;
        if (locked) { note("key1 ignored: locked"); return; }
        if (screen == Screen::Menu) { if (inWorkout()) toWorkout(); else home(); }
        else go(Screen::Menu);                  // cockpit: the controls page is Stage 3; Stage 1 opens the menu (Return to workout first)
        note("key1");
    }
    /// Key 1 held (≥ 1 s): unlocks the screen (approved key1Hold). End-workout confirmation is Stage 3.
    void key1Hold(uint32_t now) { (void)now; if (locked) { locked = false; note("unlocked"); } }
    void key2(uint32_t now) {                   // approved: two presses within 2.5 s = Lap during a ride; otherwise Back
        if (locked) { note("key2 ignored: locked"); return; }
        if (screen == Screen::Cockpit && inWorkout()) {
            if (key2Armed && now <= key2UntilMs) { key2Armed = false; send(Cmd::Lap, now); note("key2 second press: lap"); return; }
            key2Armed = true; key2UntilMs = now + KEY2_WINDOW_MS; note("key2 first press: lap armed"); return;
        }
        back(); note("key2: back");
    }
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
        } else if (screen == Screen::Cockpit) {
            // ride pages (power, heart rate, cadence, pacing, climb, navigation, coach) and the controls page are Stage 3
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
            case Action::None: break;
        }
    }
    void home() { stack.clear(); set(Screen::Face); }
    void toWorkout() { stack.clear(); set(Screen::Cockpit); }
    /// Back (prototype back()): previous screen, else the workout, else the face. The cockpit's back is the menu (Stage 1).
    void back() {
        if (screen == Screen::Cockpit) { go(Screen::Menu); return; }
        if (!stack.empty()) { Screen s = stack.back(); stack.pop_back(); set(s); return; }
        if (inWorkout()) toWorkout(); else home();
    }
    /// Demo data (serial 'E'): the simulated iPhone's synced values; off = honest "not synced" states everywhere.
    void setDemo(bool on) { synced = on; movePct = on ? 72 : 0; loadPct = on ? 58 : 0; note(on ? "demo data on" : "demo data off"); }
    /// Hook for the Bluetooth TimeSync payload (Stage 4) and the temporary serial command: the clock's local time.
    void setClock(const Clock& c) { clock = c; }

    void startRide(uint32_t now) {
        wk = WkState::Active; interval = 2; remainS = 492; laps = 0; lastSecMs_ = now; toWorkout(); note("ride started (simulated)");
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
        screen = s;
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
            case QsRow::Lock: locked = true; home(); break;
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
            S fail = c == Cmd::Pause ? S::UnablePause : c == Cmd::Resume ? S::UnableResume : S::UnableLap;
            toast = {Toast::Crit, fail, true, S::PhoneLostUseIphone, now + BANNER_MS}; note("command refused: phone lost"); return;
        }
        pending = c; pendingSinceMs = now; toast.kind = Toast::None; note("command sent (simulated iPhone)");
    }
    void resolve(uint32_t now) {
        Cmd c = pending; pending = Cmd::None;
        S fail = c == Cmd::Pause ? S::UnablePause : c == Cmd::Resume ? S::UnableResume : S::UnableLap;
        if (nextReply == Reply::Accept) {
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
        if (!simulate) return;
        if (wk == WkState::Active) {
            // a rider holding the 235–255 W band with drift and the odd surge; heart rate and cadence follow slowly
            int surge = (t_ % 47 < 4) ? 60 : (t_ % 61 < 3 ? -45 : 0);
            m.power = sensors.power ? std::max(0, 246 + noise(9) + surge) : -1;
            m.hr = sensors.hr ? 150 + (t_ / 20) % 5 + noise(1) : -1;
            m.cadence = sensors.cadence ? 91 + noise(3) : -1;
        } else if (wk == WkState::Paused) {   // paused: the last ride values stay on screen; heart rate settles slowly
            if (!sensors.power) m.power = -1;
            if (!sensors.cadence) m.cadence = -1;
            m.hr = sensors.hr ? std::max(100, (m.hr < 0 ? 150 : m.hr) - 1) : -1;
        }
    }
};

} // namespace cyw::v3
