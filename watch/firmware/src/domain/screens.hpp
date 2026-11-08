#pragma once
// Cyclift Watch OS — the primary screens as layout-engine scenes (owner §4 list). The LVGL layer draws exactly these
// scenes; the host renders them to SVG and runs the round-display checks. Content comes in as `Content` (short / long /
// extreme / German variants in the tests) so long activity and exercise names, coaching text and translated strings are
// exercised. Critical controls are marked and placed where the chord is wide enough (two 72-pt buttons fit at
// y = 160…204; the usable chord is 154 px there).
#include "round_layout.hpp"
#include "ride_screens.hpp"
#include <memory>

namespace cyw::ui {

struct Content {
    std::string time = "09:41", date = "SUN 8 NOV";
    std::string nextSession = "Ride · 60 min · 17:30";
    std::string sleep = "7 h 42", sleepSrc = "PHONE 06:10";
    std::string steps = "4 312", battery = "72 %";
    std::string coachShort = "Keep this effort.", coachLong = "Sleep was shorter than usual — keep today easy";
    std::string activity = "Outdoor cycling", exercise = "Bench press";
    std::string target = "180–216 W", value = "214", unit = "W", hr = "148";
    std::string restS = "01:12";
    std::vector<std::string> activities = {"Outdoor cycling", "Indoor cycling", "Strength training", "Functional strength", "Hybrid workout", "Walking"};
    std::string recovery = "Good", hrv = "64", hrvUnit = "ms", sleepStages = "Deep 1 h 20 · REM 1 h 55";
    std::string notification = "Rashed, your Tempo ride is planned for 17:30 today";
    std::string gpsAge = "GPS 2 s";
};

constexpr float CTRL_Y = 160.f;
/// The live cue obeys the coach protocol's wrist contract (CoachMessage::WRIST_CHARS = 44, word boundary).
inline std::string wristCue(const std::string& t) { if (t.size() <= 44) return t; size_t cut = t.rfind(' ', 43); if (cut == std::string::npos || cut < 22) cut = 43; std::string o = t.substr(0, cut); while (!o.empty() && (o.back() == ' ' || o.back() == ',')) o.pop_back(); return o + "…"; }   // control row: y 160–204, chord 154 px → two 72-pt buttons + 6 px gap

// ---------------------------------------------------------------- faces
inline Scene faceOrbit(const TextMeasurer& m, const Content& c) {
    Scene s{"face:orbit"}; Builder b(s, m);
    b.arc(0, 235, 8, "accent", RADIUS - EDGE_INSET - 4, "loadArc"); b.arc(0, 300, 5, "grade.green", RADIUS - EDGE_INSET - 15, "recoveryArc");
    Rect sl = b.text(c.sleep, 30, {14, 12, 1, false}, Role::Comp, true, "text", 22); b.text(c.sleepSrc, sl.bottom(), {11, 11, 1, false}, Role::Label, true, "mut", 22);
    Rect t = b.text(c.time, 66, {50, 40, 1, false}, Role::Value, true, "text", 24);
    b.text(c.date, t.bottom() + 1, {12, 11, 1, false}, Role::Label, true, "mut", 24);
    b.text(c.nextSession, t.bottom() + 20, {13, 13, 2, false}, Role::Body, true, "text", 22);
    Rect st = b.textFirstFit({"on target · " + c.battery + " · " + c.steps, "on target · " + c.battery, "on target"}, 184, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    b.dot(st.x - 8, st.cy(), 3, "grade.blue");
    return s;
}
inline Scene faceChrono(const TextMeasurer& m, const Content& c) {
    Scene s{"face:chrono"}; Builder b(s, m);
    b.arc(0, 360, 2, "line", RADIUS - EDGE_INSET - 1, "tickRing");
    std::string nextShort = c.nextSession.substr(c.nextSession.rfind(' ') + 1);   // the time: the name lives on the Today panel
    for (auto [cx, cy, lab, val] : std::vector<std::tuple<float, float, std::string, std::string>>{{CX, 62, "NEXT", nextShort}, {66, CY + 26, "LOAD", "65 %"}, {174, CY + 26, "RECOV", c.recovery}}) {
        b.dot(cx, cy, 30, "card", Role::Decor);
        b.textIn(lab, {cx - 26, cy - 16, 52, 14}, {11, 11, 1, false}, Role::Label, true, "mut");
        b.textIn(val, {cx - 26, cy, 52, 15}, {12, 12, 1, true}, Role::Comp, true, "text");
    }
    Rect t = b.text(c.time, CY + 62, {16, 12, 1, false}, Role::Comp, true, "text", 30);
    b.text(c.date, t.bottom(), {11, 11, 1, false}, Role::Label, true, "mut", 14);
    return s;
}
inline Scene facePulse(const TextMeasurer& m, const Content& c) {
    Scene s{"face:pulse"}; Builder b(s, m);
    b.text(c.time, 56, {52, 40, 1, false}, Role::Value, true, "text", 10);
    Rect card = bandAt(126, 46, 12); b.panel(card, "card");
    b.dot(card.x + 14, card.y + 23, 4, "grade.yellow");
    b.textIn(c.coachLong, {card.x + 26, card.y + 6, card.w - 34, 34}, {13, 13, 2, true}, Role::Body, false, "text", false, "coachLine");
    b.button("More", CX, 176, 64, "card2", "text", false, "more");
    b.textFirstFit({c.date + " · " + c.battery + " · " + c.steps, c.date + " · " + c.battery, c.date}, 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    return s;
}

// ---------------------------------------------------------------- menus
inline Scene activities(const TextMeasurer& m, const Content& c, int page = 0) {
    Scene s{"menu:activities"}; Builder b(s, m);
    b.text("ACTIVITIES", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    float y = 46; int shown = 0;
    for (size_t i = page * 3; i < c.activities.size() && shown < 3; i++, shown++) { b.row(c.activities[i], "", y, 44, "act" + std::to_string(i)); y += 48; }
    if (c.activities.size() > 3) b.text("page " + std::to_string(page + 1) + " / " + std::to_string((c.activities.size() + 2) / 3) + " · swipe", y + 4, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    return s;
}
inline Scene settings(const TextMeasurer& m, const Content& c) {
    Scene s{"menu:settings"}; Builder b(s, m);
    b.text("SETTINGS", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.row("Brightness", "60 %", 46, 44, "s1"); b.row("Display", "Night", 94, 44, "s2"); b.row("Appearance", "Cyclift", 142, 44, "s3");
    b.text(c.battery + " · iPhone linked", 192, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    return s;
}

// ---------------------------------------------------------------- live: cycling (ride_screens.hpp, driven by telemetry fixtures)
/// Telemetry scenarios for the gallery and the checks: full sensors with FTP · heart rate only · power without FTP ·
/// phone lost mid-ride · no sensors at all. Each is an honest state the instrument must render well.
struct RideFixture {
    std::string name; ride::Live live; ride::Series power{300}, hr{300}, cad{300}; ride::ZoneTime zt; ride::GpsMirror gps; std::string cue, nextTurn; uint32_t lapAvg = 0; bool lapKnown = false; uint32_t windowS = 60;
    RideFrame frame() const { RideFrame f; f.live = live; f.power = &power; f.hr = &hr; f.cadence = &cad; f.zoneTime = &zt; f.gps = &gps; f.nowMs = 2000000; f.coachCue = cue; f.windowS = windowS; f.lapAvgW = lapAvg; f.lapAvgKnown = lapKnown; f.nextTurn = nextTurn; return f; }
};
inline std::vector<std::shared_ptr<RideFixture>> rideFixtures(const Content& c) {
    std::vector<std::shared_ptr<RideFixture>> out;
    auto zones = std::vector<std::pair<int, std::optional<int>>>{{0, 120}, {121, 140}, {141, 152}, {153, 165}, {166, std::nullopt}};
    auto mk = [&](const std::string& name) { auto f = std::make_shared<RideFixture>(); f->name = name; f->live.recording = true; f->live.elapsedS = 1458; f->live.distanceM = 11600; f->live.hrZones = zones; f->live.stepName = "Interval 2"; f->live.stepTotalS = 600; f->live.stepRemainingS = 200; f->cue = wristCue(c.coachShort); return f; };
    auto feed = [](RideFixture& f, int n, bool power, bool hr, int gapFrom = -1, int gapTo = -1) {
        for (int t = 1; t <= n; t++) { bool gap = t >= gapFrom && t <= gapTo; std::optional<float> p = power && !gap ? std::optional<float>(200 + 30 * std::sin(t / 9.f) + (t % 7)) : std::nullopt; std::optional<float> h = hr && !gap ? std::optional<float>(142 + 6 * std::sin(t / 23.f)) : std::nullopt; f.power.push(t, p); f.hr.push(t, h); f.cad.push(t, power && !gap ? std::optional<float>(88 + (t % 5)) : std::nullopt); f.zt.add(h, f.live.hrZones); }
    };
    auto fixes = [](RideFixture& f, int n, bool lost) { for (int i = 0; i < n; i++) f.gps.onFix({25.1972 + i * 0.00009, 55.2744 + i * 0.00004 * std::sin(i / 5.0), 29.8f, 35.f + 20.f * std::sin(i / 7.f), 1762600000u + i, 2000000u - (n - i) * 1000u}); if (lost) f.gps.onPhoneLink(false, 1990000); };
    { auto f = mk("full"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.cadence = {89.f, 800}; f->live.speedKmh = {29.8f, 1500}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.hrBand = std::make_pair(141, 152); feed(*f, 300, true, true, 120, 135); fixes(*f, 60, false); f->nextTurn = "Al Reem St"; f->gps.setRoute({{{25.1972, 55.2744}, {25.2000, 55.2755}, {25.2030, 55.2760}}, {1}}); f->lapAvg = 201; f->lapKnown = true; out.push_back(f); }
    { auto f = mk("hr-only"); f->live.hr = {148.f, 900}; f->live.speedKmh = {27.2f, 1800}; f->live.hrBand = std::make_pair(141, 152); feed(*f, 300, false, true); fixes(*f, 60, false); out.push_back(f); }
    { auto f = mk("power-no-ftp"); f->live.power = {214.f, 800}; f->live.cadence = {91.f, 800}; f->live.speedKmh = {31.4f, 1500}; f->live.ftpKnown = false; f->live.stepTotalS = 0; feed(*f, 300, true, false); fixes(*f, 60, false); out.push_back(f); }
    { auto f = mk("phone-lost"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.phoneLinked = false; f->live.speedKmh = {29.8f, 60000}; feed(*f, 300, true, true); fixes(*f, 60, true); f->cue = "iPhone lost — recording continues"; out.push_back(f); }
    { auto f = mk("no-sensors"); f->live.stepTotalS = 0; f->cue = ""; feed(*f, 0, false, false); out.push_back(f); }
    { auto f = mk("paused"); f->live.paused = true; f->live.power = {0.f, 900000}; f->live.hr = {131.f, 1000}; f->live.ftpKnown = true; f->live.ftp = 240; feed(*f, 300, true, true); fixes(*f, 60, false); out.push_back(f); }
    return out;
}

// ---------------------------------------------------------------- live: strength
inline Scene liftExercise(const TextMeasurer& m, const Content& c) {
    Scene s{"live:lift-exercise"}; Builder b(s, m);
    b.moreText(c.exercise, 22, {15, 13, 2, false}, Role::Body, true, "text", 16, "exercise");
    b.text("Set 2/3 · 8 reps · 60 kg", 60, {11, 11, 1, false}, Role::Label, true, "mut", 12);
    b.metric("REPS", "6", "", 76, 60, "text", "reps");
    b.button("Log set", CX - 39, CTRL_Y, 72, "accent", "onAccent", true, "logSet"); b.button("Undo", CX + 39, CTRL_Y, 72, "card2", "text", false, "undo");
    return s;
}
inline Scene repCounter(const TextMeasurer& m, const Content& c) {
    Scene s{"live:rep-counter"}; Builder b(s, m);
    b.moreText(c.exercise, 22, {14, 13, 2, false}, Role::Body, true, "text", 16, "exercise");
    b.metric("AUTO · CONFIDENCE 0.9", "7", "", 62, 68, "text", "autoReps");
    b.button("Confirm", CX - 39, CTRL_Y, 72, "grade.green", "onAccent", true, "confirm"); b.button("Correct", CX + 39, CTRL_Y, 72, "card2", "text", true, "correct");
    return s;
}
inline Scene restTimer(const TextMeasurer& m, const Content& c) {
    Scene s{"live:rest-timer"}; Builder b(s, m);
    b.arc(0, 250, 6, "accent", RADIUS - EDGE_INSET - 3, "restArc");
    b.metric("REST", c.restS, "", 36, 52, "text", "rest");
    b.moreText("Next · " + c.exercise + " set 3", 118, {13, 13, 2, false}, Role::Body, true, "text", 16, "next");
    b.button("Skip rest", CX - 39, CTRL_Y, 72, "card2", "text", true, "skipRest"); b.button("Pause", CX + 39, CTRL_Y, 72, "accent", "onAccent", true, "pause");
    return s;
}

// ---------------------------------------------------------------- panels
inline Scene recovery(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:recovery"}; Builder b(s, m);
    b.text("RECOVERY", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.metric("STATUS · PHONE 06:10", c.recovery, "", 46, 32, "grade.green", "recovery");
    b.row("Sleep", c.sleep, 104, 44, "r1"); b.row("HRV", c.hrv + " " + c.hrvUnit, 152, 44, "r2");
    b.text("measured → advice", 200, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    return s;
}
inline Scene sleep(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:sleep"}; Builder b(s, m);
    b.text("SLEEP", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.metric("HEALTH 06:10", c.sleep, "", 46, 44, "text", "sleep");
    b.text(c.sleepStages, 118, {13, 13, 2, false}, Role::Body, false, "text", 16);
    b.text("6 of 7 nights within 45 min", 160, {13, 13, 2, false}, Role::Body, false, "mut", 16);
    return s;
}
inline Scene hrv(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:hrv"}; Builder b(s, m);
    b.text("HRV · SDNN", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.metric("WATCH 06:05", c.hrv, c.hrvUnit, 46, 52, "text", "hrv");
    b.text("7-day range 52–71 ms", 124, {13, 13, 1, false}, Role::Body, false, "text", 16);
    b.text("no reading today → shown as —", 150, {13, 13, 2, false}, Role::Body, false, "mut", 16);
    return s;
}
inline Scene coach(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:coach"}; Builder b(s, m);
    b.text("COACH · RULE", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.dot(CX, 50, 5, "grade.yellow");
    b.moreText(c.coachLong, 60, {15, 13, 4, false}, Role::Body, true, "text", 14, "instruction");
    b.button("Why?", CX - 39, CTRL_Y, 72, "card2", "text", false, "why"); b.button("Done", CX + 39, CTRL_Y, 72, "accent", "onAccent", true, "done");
    return s;
}
inline Scene notifications(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:notifications"}; Builder b(s, m);
    b.text("ALERTS · 1", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    Rect card = bandAt(46, 106, 12); b.panel(card, "card");
    b.textIn("Cyclift · 09:12", {card.x + 12, card.y + 8, card.w - 24, 14}, {11, 11, 1, false}, Role::Label, true, "mut");
    b.textIn(c.notification, {card.x + 12, card.y + 26, card.w - 24, 74}, {13, 13, 4, true}, Role::Body, false, "text", false, "notif");
    b.button("More", CX - 39, CTRL_Y, 72, "card2", "text", false, "more"); b.button("Dismiss", CX + 39, CTRL_Y, 72, "accent", "onAccent", false, "dismiss");
    return s;
}

/// Every primary screen (owner §4 list) for one content set.
inline std::vector<Scene> allScreens(const TextMeasurer& m, const Content& c) {
    std::vector<Scene> v = {faceOrbit(m, c), faceChrono(m, c), facePulse(m, c), activities(m, c)};
    for (auto& fx : rideFixtures(c)) { RideFrame f = fx->frame(); Scene a = rideCockpit(m, f); a.name += ":" + fx->name; v.push_back(a); Scene b2 = ridePerformance(m, f); b2.name += ":" + fx->name; v.push_back(b2); Scene n = rideNavigation(m, f); n.name += ":" + fx->name; v.push_back(n); }
    for (auto& x : {liftExercise(m, c), repCounter(m, c), restTimer(m, c), recovery(m, c), sleep(m, c), hrv(m, c), coach(m, c), notifications(m, c), settings(m, c)}) v.push_back(x);
    return v;
}

/// Text-length variants (owner §1/§4: long activity and exercise names, long coaching text, translated strings).
inline std::vector<std::pair<std::string, Content>> contentVariants() {
    Content shortC; Content longC = shortC, extreme = shortC, de = shortC;
    longC.exercise = "Single-arm dumbbell row"; longC.activity = "Functional strength training"; longC.coachShort = "Reduce power — above today's endurance target"; longC.coachLong = "Your sleep was shorter than usual and yesterday's load was high. Consider an easier session today."; longC.nextSession = "Endurance ride · 90 min · 17:30"; longC.value = "1024"; longC.notification = "Your coach moved tomorrow's strength session to Thursday because of the ride planned on Wednesday evening";
    longC.activities = {"Outdoor cycling", "Indoor cycling (trainer)", "Strength training", "Functional strength training", "Hybrid workout", "Walking", "Running", "Hiking", "Mobility and stretching", "Recovery session", "Custom activity"};
    extreme.exercise = "Bulgarian split squat with dumbbells, rear foot elevated"; extreme.coachShort = "Your heart-rate sensor disconnected — recording continues"; extreme.coachLong = "Reduce power now. You have been above today's endurance target for more than two minutes and the session goal is steady aerobic work, not intensity."; extreme.time = "23:59"; extreme.value = "2048"; extreme.steps = "28 412"; extreme.sleep = "10 h 05"; extreme.restS = "12:00"; extreme.recovery = "Limited";
    de.exercise = "Kreuzheben mit Kurzhanteln"; de.coachShort = "Leistung reduzieren — über dem Ziel"; de.coachLong = "Dein Schlaf war kürzer als üblich — halte die heutige Einheit locker."; de.nextSession = "Ausdauerfahrt · 60 Min · 17:30"; de.date = "SO 8 NOV"; de.activities = {"Radfahren draußen", "Radfahren drinnen", "Krafttraining", "Funktionelles Krafttraining", "Hybrid-Training", "Gehen"}; de.recovery = "Gut";
    return {{"short", shortC}, {"long", longC}, {"extreme", extreme}, {"german", de}};
}

} // namespace cyw::ui
