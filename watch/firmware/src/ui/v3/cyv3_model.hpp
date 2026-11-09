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

enum class Screen : uint8_t { Face, Menu, Cockpit };
enum class Density : uint8_t { Standard, Focused };
enum class TextSize : uint8_t { Default, Large };
enum class Swipe : uint8_t { Left, Right, Up, Down };
enum class WkState : uint8_t { None, Active, Paused };
enum class Cmd : uint8_t { None, Pause, Resume, Lap };
enum class Reply : uint8_t { Accept, Refuse, NoAnswer };   // what the simulated iPhone does with the next command

/// Actions the UI layer can raise from a touch (each maps to one hit area on screen).
enum class Action : uint8_t { None, MenuItem, MenuMore, Pause, Resume, DismissToast };

/// Menu entries in prototype order. Stage 1 implements WatchFace, Activities (starts the simulated ride) and
/// ReturnToWorkout; the others are drawn as approved but are not wired yet (their screens arrive in Stage 3).
enum class MenuId : uint8_t { ReturnToWorkout, WatchFace, Today, Activities, Health, Coach, History, Utilities, Settings };

struct Settings { ThemeId theme = ThemeId::Obsidian; Density density = Density::Standard; TextSize text = TextSize::Default; Lang lang = Lang::En; };

/// Sensor presence as the iPhone reports it (Stage 1: simulated). A missing value is -1 everywhere.
struct Sensors { bool power = true, hr = true, cadence = true; };
struct Metrics { int power = -1, hr = -1, cadence = -1; };

struct Toast {
    enum Kind : uint8_t { None, Ok, Crit } kind = None;
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
    int menuScroll = 0;
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
    static bool menuImplemented(MenuId id) { return id == MenuId::ReturnToWorkout || id == MenuId::WatchFace || id == MenuId::Activities; }

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
    void key1(uint32_t now) {                   // approved: face → menu; menu → face (or back to the workout)
        (void)now;
        if (screen == Screen::Face) go(Screen::Menu);
        else if (screen == Screen::Menu) go(inWorkout() ? Screen::Cockpit : Screen::Face);
        else go(Screen::Menu);                  // cockpit: the controls page is Stage 3; Stage 1 opens the menu (Return to workout first)
        note("key1");
    }
    void key2(uint32_t now) {                   // approved: two presses within 2.5 s = Lap during a ride; otherwise Back
        if (screen == Screen::Cockpit && inWorkout()) {
            if (key2Armed && now <= key2UntilMs) { key2Armed = false; send(Cmd::Lap, now); note("key2 second press: lap"); return; }
            key2Armed = true; key2UntilMs = now + KEY2_WINDOW_MS; note("key2 first press: lap armed"); return;
        }
        back(); note("key2: back");
    }
    void swipe(Swipe d) {
        Swipe backward = rtl() ? Swipe::Left : Swipe::Right;
        if (screen == Screen::Menu) {
            if (d == Swipe::Up) scroll(+1); else if (d == Swipe::Down) scroll(-1); else if (d == backward) back();
        } else if (screen == Screen::Cockpit) {
            // ride pages (power, heart rate, cadence, pacing, climb, navigation, coach) and the controls page are Stage 3
        }
        note(std::string("swipe ") + "LRUD"[int(d)]);
    }
    void act(Action a, int arg, uint32_t now) {
        switch (a) {
            case Action::MenuItem: selectMenu(MenuId(arg), now); break;
            case Action::MenuMore: scroll(+1); break;
            case Action::Pause: if (wk == WkState::Active && pending == Cmd::None) send(Cmd::Pause, now); break;
            case Action::Resume: if (wk == WkState::Paused && pending == Cmd::None) send(Cmd::Resume, now); break;
            case Action::DismissToast: toast.kind = Toast::None; break;
            case Action::None: break;
        }
    }
    void home() { go(Screen::Face); }
    void back() { if (screen == Screen::Menu) go(inWorkout() ? Screen::Cockpit : Screen::Face); else if (screen == Screen::Cockpit) go(Screen::Menu); }

    void startRide(uint32_t now) {
        wk = WkState::Active; interval = 2; remainS = 492; laps = 0; lastSecMs_ = now; go(Screen::Cockpit); note("ride started (simulated)");
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
    void go(Screen s) { if (s == Screen::Menu && screen != Screen::Menu) menuScroll = 0; screen = s; }
    void scroll(int d) { menuScroll = std::max(0, std::min(menuMaxScroll(), menuScroll + d)); }
    void selectMenu(MenuId id, uint32_t now) {
        switch (id) {
            case MenuId::ReturnToWorkout: go(Screen::Cockpit); break;
            case MenuId::WatchFace: go(Screen::Face); break;
            case MenuId::Activities: if (!inWorkout()) startRide(now); else go(Screen::Cockpit); break;
            default: note("menu item not in Stage 1"); break;
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
