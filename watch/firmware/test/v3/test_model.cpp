// Cyclift Watch v3 — Stage 1 model tests on a computer (no LVGL, no hardware): navigation, simulated buttons,
// simulated iPhone replies, connection and sensor states, missing data, numeric grading, strings.
#include "../../src/ui/v3/cyv3_model.hpp"
#include <cstdio>
#include <cstring>
#include <set>

using namespace cyw::v3;
static int g_checks = 0, g_fail = 0;
#define CHECK(c) do { g_checks++; if (!(c)) { g_fail++; std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); } } while (0)

static void navigation() {
    Model m; uint32_t t = 1000;
    CHECK(m.screen == Screen::Face);
    m.key1(t); CHECK(m.screen == Screen::Menu);                      // Key 1 opens the menu
    m.key1(t); CHECK(m.screen == Screen::Face);                      // and closes it again
    m.key1(t); m.swipe(Swipe::Right); CHECK(m.screen == Screen::Face); // swipe back
    m.key1(t);
    auto items = m.menuItems(); CHECK(items.size() == 8); CHECK(items[0] == MenuId::WatchFace);
    m.act(Action::MenuItem, int(MenuId::Today), t); CHECK(m.screen == Screen::Menu);   // not in Stage 1: stays
    m.act(Action::MenuItem, int(MenuId::Activities), t); CHECK(m.screen == Screen::Cockpit); CHECK(m.wk == WkState::Active);
    m.key1(t); CHECK(m.screen == Screen::Menu);
    items = m.menuItems(); CHECK(items.size() == 9); CHECK(items[0] == MenuId::ReturnToWorkout);
    m.act(Action::MenuItem, int(MenuId::ReturnToWorkout), t); CHECK(m.screen == Screen::Cockpit);
    m.key1(t); m.swipe(Swipe::Right); CHECK(m.screen == Screen::Cockpit);   // back from the menu returns to the ride
    m.key1(t); m.act(Action::MenuItem, int(MenuId::WatchFace), t); CHECK(m.screen == Screen::Face); CHECK(m.inWorkout());
    m.key1(t); m.key1(t); CHECK(m.screen == Screen::Cockpit);        // Key 1 from the menu goes back to the running ride
}

static void menuScroll() {
    Model m; m.key1(0);
    m.swipe(Swipe::Up); CHECK(m.menuScroll == 1);
    for (int i = 0; i < 20; i++) m.swipe(Swipe::Up);
    CHECK(m.menuScroll == m.menuMaxScroll()); CHECK(m.menuMaxScroll() == 6);
    m.swipe(Swipe::Down); CHECK(m.menuScroll == 5);
    m.act(Action::MenuMore, 0, 0); CHECK(m.menuScroll == 6);
    m.key1(0); m.key1(0); CHECK(m.menuScroll == 0);                 // reopening the menu starts at the top
    m.settings.lang = Lang::Ar;                                       // right-to-left: back is a swipe to the left
    m.swipe(Swipe::Right); CHECK(m.screen == Screen::Menu);
    m.swipe(Swipe::Left); CHECK(m.screen == Screen::Face);
}

static void buttonsAndCommands() {
    Model m; uint32_t t = 0; m.startRide(t); m.setMetrics(246, 152, 92);
    // Key 2: two presses within 2.5 s = Lap
    m.key2(t); CHECK(m.key2Armed); CHECK(m.pending == Cmd::None);
    t += 1000; m.key2(t); CHECK(!m.key2Armed); CHECK(m.pending == Cmd::Lap);
    t += 500; m.tick(t); CHECK(m.pending == Cmd::None); CHECK(m.laps == 1); CHECK(m.toast.kind == Toast::Ok); CHECK(m.toast.text == S::ToastLapSaved);
    t += 3000; m.tick(t); CHECK(m.toast.kind == Toast::None);
    m.key2(t); t += 2600; m.tick(t); CHECK(!m.key2Armed);           // the window closes after 2.5 s
    m.key2(t); CHECK(m.key2Armed); CHECK(m.pending == Cmd::None);    // so this is a new first press
    t += 3000; m.tick(t);
    // Pause → pending → confirmed
    m.act(Action::Pause, 0, t); CHECK(m.pending == Cmd::Pause); CHECK(m.wk == WkState::Active);
    m.act(Action::Pause, 0, t); CHECK(m.pending == Cmd::Pause);     // no double send while pending
    t += 450; m.tick(t); CHECK(m.wk == WkState::Paused); CHECK(m.toast.text == S::ToastPaused);
    // Resume refused by the iPhone → banner with the reason, state unchanged
    m.nextReply = Reply::Refuse; m.act(Action::Resume, 0, t); t += 450; m.tick(t);
    CHECK(m.wk == WkState::Paused); CHECK(m.toast.kind == Toast::Crit); CHECK(m.toast.hasSub); CHECK(m.toast.sub == S::WorkoutChanged); CHECK(m.toast.text == S::UnableResume);
    m.act(Action::DismissToast, 0, t); CHECK(m.toast.kind == Toast::None);
    // no answer: still pending after 4.9 s, failure at 5 s
    m.nextReply = Reply::NoAnswer; m.act(Action::Resume, 0, t);
    t += 4900; m.tick(t); CHECK(m.pending == Cmd::Resume);
    t += 100; m.tick(t); CHECK(m.pending == Cmd::None); CHECK(m.toast.sub == S::NoAnswer); CHECK(m.wk == WkState::Paused);
    CHECK(m.nextReply == Reply::Accept);
    // phone lost: refused at once, never pending
    m.phoneLinked = false; m.act(Action::Resume, 0, t); CHECK(m.pending == Cmd::None); CHECK(m.toast.text == S::UnableResume); CHECK(m.toast.hasSub); CHECK(m.toast.sub == S::PhoneLostUseIphone);
    m.phoneLinked = true; m.act(Action::Resume, 0, t); t += 450; m.tick(t); CHECK(m.wk == WkState::Active);
    // Key 2 outside a ride = Back
    Model f; f.key1(0); f.key2(0); CHECK(f.screen == Screen::Face);
}

static void statesAndMissingData() {
    Model m; m.startRide(0);
    m.setMetrics(246, 152, 92); CHECK(m.command().text == "HOLD 245 W"); CHECK(m.command().color == Model::Command::On);
    m.setMetrics(300, 152, 92); CHECK(m.command().text == "EASE OFF"); CHECK(m.command().color == Model::Command::Far);
    m.setMetrics(270, 152, 92); CHECK(m.command().text == "EASE OFF"); CHECK(m.command().color == Model::Command::Adjust);
    m.setMetrics(220, 152, 92); CHECK(m.command().text == "PUSH TO 245 W"); CHECK(m.command().color == Model::Command::Adjust);
    m.setMetrics(1999, 152, 92); CHECK(Model::gradeOf(1999) == Model::Grade::Far);
    m.setMetrics(-1, 152, -1); CHECK(m.command().text == "HR 140\xE2\x80\x93" "155");
    m.setMetrics(-1, -1, -1); CHECK(m.command().text == "WAITING HR");
    m.phoneLinked = false; CHECK(m.command().text == "PHONE LOST"); CHECK(m.command().color == Model::Command::Crit);
    m.settings.lang = Lang::Ar; CHECK(m.command().text == "فُقد الهاتف");
    m.phoneLinked = true; m.setMetrics(246, 152, 92); CHECK(m.command().text == "ثبّت 245 W");
    CHECK(Model::gradeOf(-1) == Model::Grade::None); CHECK(Model::gradeOf(235) == Model::Grade::On); CHECK(Model::gradeOf(255) == Model::Grade::On);
    CHECK(Model::gradeOf(210) == Model::Grade::Adjust); CHECK(Model::gradeOf(209) == Model::Grade::Far); CHECK(Model::gradeOf(295) == Model::Grade::Adjust); CHECK(Model::gradeOf(296) == Model::Grade::Far);
}

static void simulation() {
    Model m; uint32_t t = 0; m.startRide(t);
    int lo = 9999, hi = -1;
    for (int s = 0; s < 600; s++) { t += 1000; m.tick(t); lo = std::min(lo, m.m.power); hi = std::max(hi, m.m.power);
        CHECK(m.m.hr >= 100 && m.m.hr <= 200); CHECK(m.m.cadence >= 80 && m.m.cadence <= 100); }
    CHECK(lo >= 150 && hi <= 330 && hi - lo > 40);                    // varies around the band, with surges
    CHECK(m.remainS == 492 - 600 + 720);                              // interval rolled over once
    CHECK(m.interval == 3);
    m.sensors.power = false; t += 1000; m.tick(t); CHECK(m.m.power == -1); CHECK(m.m.hr > 0);
    m.sensors = Sensors{false, false, false}; t += 1000; m.tick(t); CHECK(m.m.power == -1 && m.m.hr == -1 && m.m.cadence == -1);
    m.sensors = Sensors{}; t += 1000; m.tick(t); int lastP = m.m.power;
    int before = m.remainS; m.wk = WkState::Paused; t += 5000; m.tick(t); CHECK(m.remainS == before);   // paused: the clock stops
    CHECK(m.m.power == lastP); CHECK(m.command().text != "PUSH TO 245 W" || lastP < Model::TARGET_LO);   // and power is not shown as 0 W
}

static void strings() {
    std::set<std::string> en;
    for (int i = 0; i < int(S::COUNT); i++) {
        const Pair& p = pair(S(i));
        CHECK(std::strlen(p.en) > 0); CHECK(std::strlen(p.ar) > 0); CHECK(std::strcmp(p.en, p.ar) != 0);
        CHECK(en.insert(p.en).second);                                 // no duplicate English strings
        bool hasArabic = false; for (const unsigned char* c = (const unsigned char*)p.ar; *c; c++) if (*c == 0xD8 || *c == 0xD9) hasArabic = true;
        CHECK(hasArabic);
    }
    CHECK(trf(S::Hold, Lang::En, 245) == "HOLD 245 W");               // abbreviations stay Latin in Arabic
    CHECK(trf(S::Hold, Lang::Ar, 245).find(" W") != std::string::npos);
    CHECK(std::string(weekday(0, Lang::En)) == "SUN"); CHECK(std::string(month(11, Lang::Ar)) == "نوفمبر");
}

int main() {
    navigation(); menuScroll(); buttonsAndCommands(); statesAndMissingData(); simulation(); strings();
    std::printf("v3 model: %d checks, %d failures\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
