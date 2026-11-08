#pragma once
// Cyclift Watch OS — the primary screens as layout-engine scenes (owner §4 list). The LVGL layer draws exactly these
// scenes; the host renders them to SVG and runs the round-display checks. Content comes in as `Content` (short / long /
// extreme / German variants in the tests) so long activity and exercise names, coaching text and translated strings are
// exercised. Critical controls are marked and placed where the chord is wide enough (two 72-pt buttons fit at
// y = 160…204; the usable chord is 154 px there).
#include "round_layout.hpp"
#include "ride_screens.hpp"
#include "buttons.hpp"
#include <memory>
#include <cstdio>

namespace cyw::ui {

struct Content {
    std::string time = "09:41", date = "SUN 8 NOV";
    std::string nextSession = "Ride · 60 min · 17:30";
    std::string sleep = "7 h 42", sleepSrc = "PHONE 06:10";
    std::string steps = "4 312", battery = "72 %";
    std::string coachShort = "Keep this effort.", coachLong = "Sleep was shorter than usual — keep today easy";
    std::string insight = "SLEEP SHORT · GO EASY";        // Pulse / Recovery: one short insight (≤ 22 chars), detail behind More
    std::string activity = "Outdoor cycling", exercise = "Bench press", nextExercise = "Incline press";
    std::string target = "180–216 W", value = "214", unit = "W", hr = "148";
    std::string restS = "01:12";
    std::vector<std::string> activities = {"Outdoor cycling", "Indoor cycling", "Strength training", "Functional strength", "Hybrid workout", "Walking"};
    std::string recovery = "Good", hrv = "64", hrvUnit = "ms", sleepStages = "Deep 1 h 20 · REM 1 h 55";
    std::string notification = "Rashed, your Tempo ride is planned for 17:30 today";
    std::string gpsAge = "GPS 2 s";
    int loadPct = 65; float recoveryFrac = 0.78f; std::string recoveryWord = "GOOD";
    int hourHand = 9, minuteHand = 41;
    // quick settings + timers (real state from the model; the gallery uses these defaults)
    std::string brightness = "60 %", appearanceName = "Cyclift · Midnight Blue", linkLine = "iPhone linked"; bool dnd = false;
    bool timerRunning = false, timerRinging = false; uint32_t timerRemainingS = 0, timerTotalS = 0;
};

constexpr float CTRL_Y = 160.f;
/// The live cue obeys the coach protocol's wrist contract (CoachMessage::WRIST_CHARS = 44, word boundary).
inline std::string wristCue(const std::string& t) { if (t.size() <= 44) return t; size_t cut = t.rfind(' ', 43); if (cut == std::string::npos || cut < 22) cut = 43; std::string o = t.substr(0, cut); while (!o.empty() && (o.back() == ' ' || o.back() == ',')) o.pop_back(); return o + "…"; }   // control row: y 160–204, chord 154 px → two 72-pt buttons + 6 px gap

// ---------------------------------------------------------------- faces ("What time is it, and what matters next?")
/// ORBIT — a strong central clock; two refined arcs with ONE legend line that names them; the next activity; nothing else.
///   outer arc (accent)  = this week's planned training load completed (0…100 %), source: iPhone plan + logged sessions
///   inner arc (graded)  = recovery (0…1, grade colour + word), source: iPhone recovery summary; hidden with no data
inline Scene faceOrbit(const TextMeasurer& m, const Content& c) {
    Scene s{"face:orbit"}; Builder b(s, m);
    const float A0 = -140.f, A1 = 140.f;                                                     // 280° sweep, open at the bottom
    b.arc(A0, A1, 6, "line", RADIUS - EDGE_INSET - 3, "loadTrack"); b.arc(A0, A0 + 280 * std::clamp(c.loadPct / 100.f, 0.f, 1.f), 6, "accent", RADIUS - EDGE_INSET - 3, "loadArc");
    std::string recTok = c.recoveryFrac >= 0.75f ? "grade.green" : c.recoveryFrac >= 0.5f ? "grade.blue" : c.recoveryFrac >= 0.3f ? "grade.yellow" : "grade.red";
    b.arc(A0, A1, 4, "line", RADIUS - EDGE_INSET - 11, "recoveryTrack"); b.arc(A0, A0 + 280 * std::clamp(c.recoveryFrac, 0.f, 1.f), 4, recTok, RADIUS - EDGE_INSET - 11, "recoveryArc");
    Rect sl = b.text(c.sleep + " · " + c.sleepSrc, 44, {11, 11, 1, false}, Role::Label, true, "mut", 18);
    Rect t = b.text(c.time, sl.bottom() + 4, {54, 40, 1, false}, Role::Value, true, "text", 14);
    b.text(c.date + " · " + c.battery, t.bottom(), {12, 11, 1, false}, Role::Label, true, "mut", 14);
    b.text(c.nextSession, t.bottom() + 18, {14, 13, 2, false}, Role::Body, true, "text", 22, false, "next");
    // legend: what the two arcs mean, with their colours — one line, no competing status labels
    Rect lg = b.textFirstFit({"LOAD " + std::to_string(c.loadPct) + " %  ·  RECOVERY " + c.recoveryWord, "LOAD " + std::to_string(c.loadPct) + " % · " + c.recoveryWord}, 186, {11, 11, 1, false}, Role::Label, true, "mut", 18);
    b.dot(lg.x - 8, lg.cy(), 3, "accent"); b.dot(lg.right() + 8, lg.cy(), 3, recTok);
    return s;
}
/// CHRONO — real hands (drawn in the scene so the render shows them) kept SHORT (minute 50 px, hour 34 px) inside a
/// 56 px hub circle; the three dials sit OUTSIDE the hand sweep at radius 86 and never get covered. Digital time + date
/// sit at the bottom between the lower dials so the time is instantly readable even at a glance.
inline Scene faceChrono(const TextMeasurer& m, const Content& c) {
    Scene s{"face:chrono"}; Builder b(s, m);
    b.arc(0, 360, 2, "line", RADIUS - EDGE_INSET - 1, "tickRing");
    for (int i = 0; i < 12; i++) { float a = i * 30.f; float t = (a - 90) * 3.14159265f / 180; float r0 = RADIUS - EDGE_INSET - 3, r1 = r0 - (i % 3 == 0 ? 8 : 4); b.polyline({std::make_pair(CX + r0 * std::cos(t), CY + r0 * std::sin(t)), std::make_pair(CX + r1 * std::cos(t), CY + r1 * std::sin(t))}, i % 3 == 0 ? "mut" : "line", 2, "tick" + std::to_string(i)); }
    b.dot(CX, CY, 54, "card", Role::Decor);                                                  // the hand sweep area
    std::string nextShort = c.nextSession.substr(c.nextSession.rfind(' ') + 1);              // the time: the name lives on the Today panel
    const float DR = 78.f, dr = 23.f;
    for (auto [ang, lab, val, col] : std::vector<std::tuple<float, std::string, std::string, std::string>>{{0.f, "NEXT", nextShort, "text"}, {230.f, "LOAD", std::to_string(c.loadPct) + " %", "text"}, {130.f, "RECOV", c.recoveryWord, "text"}}) {
        float t = (ang - 90) * 3.14159265f / 180; float cx = CX + DR * std::cos(t), cy = CY + DR * std::sin(t);
        b.dot(cx, cy, dr, "card2", Role::Decor);
        b.textIn(lab, {cx - 22, cy - 15, 44, 14}, {11, 11, 1, false}, Role::Label, true, "mut");
        b.textIn(val, {cx - 22, cy, 44, 15}, {12, 12, 1, false}, Role::Comp, true, lab == "RECOV" ? (c.recoveryFrac >= 0.75f ? "grade.green" : c.recoveryFrac >= 0.5f ? "grade.blue" : "grade.yellow") : col);
    }
    { float ha = (c.hourHand % 12 + c.minuteHand / 60.f) * 30.f, ma = c.minuteHand * 6.f; auto tip = [&](float a, float len) { float t = (a - 90) * 3.14159265f / 180; return std::make_pair(CX + len * std::cos(t), CY + len * std::sin(t)); };
      b.polyline({std::make_pair(CX, CY), tip(ha, 32)}, "text", 5, "hourHand"); b.polyline({std::make_pair(CX, CY), tip(ma, 46)}, "accent", 3, "minuteHand"); b.dot(CX, CY, 4, "text"); }
    Rect t = b.text(c.time, 176, {16, 14, 1, false}, Role::Comp, true, "text", 36);
    b.text(c.date, t.bottom(), {11, 11, 1, false}, Role::Label, true, "mut", 36);
    return s;
}
/// PULSE — minimal: status line, big time, ONE short insight (graded dot) and a clearly visible More.
inline Scene facePulse(const TextMeasurer& m, const Content& c) {
    Scene s{"face:pulse"}; Builder b(s, m);
    b.textFirstFit({c.date + " · " + c.battery, c.date}, 34, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    b.text(c.time, 54, {58, 40, 1, false}, Role::Value, true, "text", 10);
    Rect card = bandAt(126, 48, 14); b.panel(card, "card");
    b.dot(card.x + 16, card.y + 24, 5, "grade.yellow");
    b.textIn(c.insight, {card.x + 30, card.y + 6, card.w - 40, 36}, {14, 12, 2, false}, Role::Comp, true, "text", false, "insight");
    b.button("More", CX, 178, 76, "card2", "text", false, "more");
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
    b.row("Brightness", c.brightness, 46, 44, "s1"); b.row("Appearance", c.appearanceName, 94, 44, "s3"); b.row("Do not disturb", c.dnd ? "On" : "Off", 142, 44, "s4");
    b.text(c.battery + " · " + c.linkLine, 196, {11, 11, 1, false}, Role::Label, true, "mut", 6);
    return s;
}

/// Timers panel (Notifications band when no coach message is pending or a timer exists): presets, the countdown and Stop.
inline Scene timers(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:timers"}; Builder b(s, m);
    b.text("TIMER", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    if (c.timerRunning || c.timerRinging) {
        float frac = c.timerTotalS ? 1.f - float(c.timerRemainingS) / float(c.timerTotalS) : 1.f;
        b.arc(-135, 135, 8, "line", 84, "timerTrack"); b.arc(-135, -135 + 270 * std::clamp(frac, 0.f, 1.f), 8, c.timerRinging ? "grade.green" : "accent", 84, "timerArc");
        b.text(c.timerRinging ? "DONE" : mmss(c.timerRemainingS), 78, {44, 28, 1, false}, Role::Value, true, "text", 6, false, "timerValue");
        b.text(c.timerRinging ? "timer finished" : "of " + mmss(c.timerTotalS), 134, {12, 11, 1, false}, Role::Label, true, "mut", 14);
        b.button(c.timerRinging ? "OK" : "Stop", CX, CTRL_Y + 14, 96, "accent", "onAccent", false, "tstop");
    } else {
        b.text("Start a countdown", 60, {14, 12, 1, false}, Role::Body, true, "text", 14);
        b.button("1 min", CX - 66, 112, 60, "card2", "text", false, "t1"); b.button("3 min", CX, 112, 60, "card2", "text", false, "t3"); b.button("5 min", CX + 66, 112, 60, "card2", "text", false, "t5");
        b.text("Vibrates when it ends", 176, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    }
    return s;
}

// ---------------------------------------------------------------- live: cycling (ride_screens.hpp, driven by telemetry fixtures)
/// Telemetry scenarios for the gallery and the checks. ALL coordinates are SIMULATED (a 1.5 km synthetic path near
/// 25.197 N 55.274 E, waypoints in metres → degrees); the gallery labels them "SIM". Each fixture is an honest state the
/// instrument must render well: full sensors on a route · HR only (no route) · power without FTP · off route · GPS stale
/// · phone lost mid-ride · no sensors / no GPS · paused · north-up.
struct RideFixture {
    std::string name; ride::Live live; ride::Series power{300}, hr{300}, cad{300}; ride::ZoneTime zt; ride::GpsMirror gps; std::string cue, nextTurn; uint32_t lapAvg = 0; bool lapKnown = false; uint32_t windowS = 60; bool northUp = false; uint32_t nowMs = 2000000;
    std::vector<PerfPage> perfPages{PerfPage::Power}; bool controls = false;
    RideFrame frame() const { RideFrame f; f.live = live; f.power = &power; f.hr = &hr; f.cadence = &cad; f.zoneTime = &zt; f.gps = &gps; f.nowMs = nowMs; f.coachCue = cue; f.windowS = windowS; f.lapAvgW = lapAvg; f.lapAvgKnown = lapKnown; f.nextTurn = nextTurn; f.northUp = northUp; f.simulated = true; return f; }
};
/// Synthetic path: north 300 m, a right-hand bend, east 360 m, a left-hand bend, north-east 420 m. Returns (lat, lon)
/// every `stepM` metres plus the indices of the two turns.
inline std::pair<std::vector<std::pair<double, double>>, std::vector<size_t>> simPath(float stepM = 10.f) {
    const double lat0 = 25.1972, lon0 = 55.2744, mPerLat = 110540.0, mPerLon = 111320.0 * std::cos(lat0 * 3.14159265 / 180.0);
    std::vector<std::pair<float, float>> W = {{0, 0}, {0, 300}, {40, 340}, {400, 360}, {600, 500}, {900, 800}};
    std::vector<std::pair<double, double>> pts; std::vector<size_t> turns; std::vector<size_t> vertexIdx;
    for (size_t i = 0; i + 1 < W.size(); i++) { float dx = W[i + 1].first - W[i].first, dy = W[i + 1].second - W[i].second, len = std::sqrt(dx * dx + dy * dy); int n = std::max(1, int(len / stepM)); for (int k = 0; k < n; k++) { float t = float(k) / n; pts.emplace_back(lat0 + (W[i].second + dy * t) / mPerLat, lon0 + (W[i].first + dx * t) / mPerLon); } vertexIdx.push_back(pts.size()); }
    pts.emplace_back(lat0 + W.back().second / mPerLat, lon0 + W.back().first / mPerLon);
    turns = {vertexIdx[0], vertexIdx[2]};                      // the bend at the top of the first leg; the bend before the long diagonal
    return {pts, turns};
}
inline std::vector<std::shared_ptr<RideFixture>> rideFixtures(const Content& c) {
    std::vector<std::shared_ptr<RideFixture>> out;
    auto zones = std::vector<std::pair<int, std::optional<int>>>{{0, 120}, {121, 140}, {141, 152}, {153, 165}, {166, std::nullopt}};
    auto mk = [&](const std::string& name) { auto f = std::make_shared<RideFixture>(); f->name = name; f->live.recording = true; f->live.elapsedS = 1458; f->live.distanceM = 11600; f->live.hrZones = zones; f->live.stepName = "Interval 2"; f->live.stepTotalS = 600; f->live.stepRemainingS = 200; f->cue = wristCue(c.coachShort); return f; };
    // synthetic 1 Hz series; the LIVE readings are taken from the series' own 3 s averages so every screen shows the same numbers
    auto feed = [](RideFixture& f, int n, bool power, bool hr, int gapFrom = -1, int gapTo = -1, float pOff = 0.f, float hOff = 0.f, float cOff = 0.f) {
        for (int t = 1; t <= n; t++) { bool gap = t >= gapFrom && t <= gapTo; std::optional<float> p = power && !gap ? std::optional<float>(198 + pOff + 22 * std::sin(t / 11.f) + 3 * std::sin(t / 2.3f)) : std::nullopt; std::optional<float> h = hr && !gap ? std::optional<float>(146 + hOff + 5 * std::sin(t / 29.f)) : std::nullopt; f.power.push(t, p); f.hr.push(t, h); f.cad.push(t, power && !gap ? std::optional<float>(89 + cOff + 3 * std::sin(t / 13.f)) : std::nullopt); f.zt.add(h, f.live.hrZones); }
        if (n) { if (power) { f.live.power = {f.power.average(3), 800}; f.live.cadence = {f.cad.average(3), 800}; } if (hr) f.live.hr = {f.hr.average(3), 1200}; }
    };
    // fixes along the simulated path: `n` fixes 10 m apart ending `endIdx` points in; `lostAtMs` marks the phone link down
    auto fixes = [](RideFixture& f, int n, int endIdx, bool loadRoute, float offsetEastM = 0.f, uint32_t lastFixAgeMs = 1000) {
        auto [pts, turns] = simPath(10.f); if (loadRoute) f.gps.setRoute({pts, turns});
        int from = std::max(0, endIdx - n);
        for (int i = from; i < endIdx; i++) { double lat = pts[i].first, lon = pts[i].second; if (i == endIdx - 1 && offsetEastM != 0.f) lon += offsetEastM / (111320.0 * std::cos(lat * 3.14159265 / 180.0));
            double dlat = pts[i + 1].first - lat, dlon = (pts[i + 1].second - lon) * std::cos(lat * 3.14159265 / 180.0); float hd = float(std::atan2(dlon, dlat) * 180 / 3.14159265); if (hd < 0) hd += 360;
            f.gps.onFix({lat, lon, 29.8f, hd, 1762600000u + i, f.nowMs - lastFixAgeMs - (endIdx - 1 - i) * 1000u}); }
    };
    { auto f = mk("full"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.cadence = {89.f, 800}; f->live.speedKmh = {29.8f, 1500}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.hrBand = std::make_pair(141, 152); feed(*f, 300, true, true, 120, 135); fixes(*f, 60, 62, true); f->nextTurn = "Al Reem St"; f->lapAvg = 201; f->lapKnown = true; f->perfPages = {PerfPage::Power, PerfPage::HeartRate, PerfPage::Cadence, PerfPage::Target}; f->controls = true; out.push_back(f); }
    { auto f = mk("hr-only"); f->live.speedKmh = {27.2f, 1800}; f->live.hrBand = std::make_pair(141, 152); feed(*f, 300, false, true, -1, -1, 0, 12); fixes(*f, 60, 62, false); f->perfPages = {PerfPage::HeartRate}; out.push_back(f); }
    { auto f = mk("power-no-ftp"); f->live.power = {214.f, 800}; f->live.cadence = {91.f, 800}; f->live.speedKmh = {31.4f, 1500}; f->live.ftpKnown = false; f->live.stepTotalS = 0; f->live.cadenceRange = std::nullopt; feed(*f, 300, true, false); fixes(*f, 60, 62, false); out.push_back(f); }
    { auto f = mk("low-power"); f->live.power = {162.f, 800}; f->live.hr = {139.f, 1200}; f->live.cadence = {78.f, 800}; f->live.speedKmh = {24.1f, 1500}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.hrBand = std::make_pair(141, 152); feed(*f, 300, true, true, -1, -1, -38, -8, -11); fixes(*f, 60, 62, true); f->nextTurn = "Al Reem St"; out.push_back(f); }
    { auto f = mk("off-route"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.cadence = {89.f, 800}; f->live.speedKmh = {29.8f, 1500}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); feed(*f, 300, true, true); fixes(*f, 60, 62, true, 85.f); f->nextTurn = "Al Reem St"; out.push_back(f); }
    { auto f = mk("gps-stale"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.speedKmh = {29.8f, 14000}; feed(*f, 300, true, true); fixes(*f, 60, 62, true, 0.f, 14000); f->nextTurn = "Al Reem St"; out.push_back(f); }
    { auto f = mk("phone-lost"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); f->live.phoneLinked = false; f->live.speedKmh = {29.8f, 60000}; feed(*f, 300, true, true, 260, 300); fixes(*f, 60, 62, true, 0.f, 41000); f->gps.onPhoneLink(false, f->nowMs - 40000); f->live.power.ageMs = f->live.hr.ageMs = f->live.cadence.ageMs = 41000; /* sensors ride through the phone: stale since the link dropped */ f->cue = "iPhone lost — recording continues"; out.push_back(f); }
    { auto f = mk("no-sensors"); f->live.stepTotalS = 0; f->cue = ""; feed(*f, 0, false, false); out.push_back(f); }
    { auto f = mk("north-up"); f->live.power = {214.f, 800}; f->live.hr = {148.f, 1200}; f->live.cadence = {89.f, 800}; f->live.speedKmh = {29.8f, 1500}; f->live.ftpKnown = true; f->live.ftp = 240; f->live.powerBand = std::make_pair(180, 216); feed(*f, 300, true, true); fixes(*f, 60, 62, true); f->nextTurn = "Al Reem St"; f->northUp = true; out.push_back(f); }
    { auto f = mk("paused"); f->live.paused = true; f->live.ftpKnown = true; f->live.ftp = 240; feed(*f, 300, true, true, -1, -1, 0, -15); fixes(*f, 60, 62, true); f->live.power.ageMs = 900000; f->live.cadence.ageMs = 900000; /* stopped pedalling: power stale, HR still live */ f->controls = true; out.push_back(f); }
    return out;
}

// ---------------------------------------------------------------- live: strength ("Which exercise, how many reps, and what comes next?")
/// Real strength state for the screens (filled from StrengthSession + the rep detector on the device; from Content in
/// the gallery). Nothing here is a demonstration number once the app runs.
struct LiftState {
    std::string exercise = "Bench press", nextExercise = "Incline press";
    int setIndex = 2, setTotal = 3, targetReps = 8;                  // 1-based set index
    std::optional<float> weightKg = 60.f;                              // nullopt = bodyweight / unknown
    char superset = 'A'; int supersetOrdinal = 1;                      // "A1"; 0 superset = straight sets
    int reps = 6; std::optional<float> confidence = 0.9f; bool autoCount = true;   // detected count + its provenance
    uint32_t restRemainingS = 72, restTotalS = 120;
    int setsLogged = 3; uint32_t elapsedS = 2520; bool paused = false;
    std::string setLine() const { std::string w = weightKg ? std::to_string(int(std::lround(*weightKg))) + " kg" : "bodyweight"; std::string ss = superset ? std::string(" · ") + superset + std::to_string(supersetOrdinal) : ""; return "SET " + std::to_string(setIndex) + "/" + std::to_string(setTotal) + " · " + std::to_string(targetReps) + " REPS · " + w + ss; }
    std::string repsLabel() const { if (!autoCount) return "REPS · MANUAL"; char b[32]; std::snprintf(b, sizeof b, "REPS · AUTO %.1f", confidence.value_or(0.f)); return b; }
    std::string nextLabel() const { return superset ? std::string("NEXT · ") + superset + std::to_string(supersetOrdinal + 1) : "NEXT"; }
    static LiftState from(const Content& c) { LiftState l; l.exercise = c.exercise; l.nextExercise = c.nextExercise; if (!c.restS.empty()) { int m = 0, sec = 0; std::sscanf(c.restS.c_str(), "%d:%d", &m, &sec); l.restRemainingS = m * 60 + sec; } return l; }
};
inline Scene liftExercise(const TextMeasurer& m, const LiftState& l) {
    Scene s{"live:lift-exercise"}; Builder b(s, m);
    b.moreText(l.exercise, 30, {15, 13, 2, false}, Role::Body, true, "text", 14, "exercise");
    b.text(l.setLine(), 68, {11, 11, 1, false}, Role::Label, true, "mut", 10, false, "setline");
    b.metric(l.repsLabel(), std::to_string(l.reps), "", 84, 52, "text", "reps");
    b.button("Log set", CX - 39, CTRL_Y, 72, "accent", "onAccent", true, "logSet"); b.button("Correct", CX + 39, CTRL_Y, 72, "card2", "text", true, "correct");
    return s;
}
inline Scene liftExercise(const TextMeasurer& m, const Content& c) { return liftExercise(m, LiftState::from(c)); }
/// Set finished: the watch proposes the detected count and asks for a confirmation — the athlete, not the sensor, has the last word.
inline Scene repCounter(const TextMeasurer& m, const LiftState& l) {
    Scene s{"live:rep-counter"}; Builder b(s, m);
    b.moreText(l.exercise, 30, {15, 13, 2, false}, Role::Body, true, "text", 14, "exercise");
    b.text("SET " + std::to_string(l.setIndex) + " / " + std::to_string(l.setTotal) + " DONE · TARGET " + std::to_string(l.targetReps), 68, {11, 11, 1, false}, Role::Label, true, "mut", 10);
    { char lb[40]; std::snprintf(lb, sizeof lb, "DETECTED · CONFIDENCE %.1f", l.confidence.value_or(0.f)); b.metric(lb, std::to_string(l.reps), "", 84, 52, "text", "autoReps"); }
    b.button("Confirm", CX - 39, CTRL_Y, 72, "grade.green", "onAccent", true, "confirm"); b.button("Correct", CX + 39, CTRL_Y, 72, "card2", "text", true, "correct");
    return s;
}
inline Scene repCounter(const TextMeasurer& m, const Content& c) { LiftState l = LiftState::from(c); l.reps = 7; return repCounter(m, l); }
/// Rest: the countdown leads; the next exercise and the superset step are the only other things on the screen.
inline Scene restTimer(const TextMeasurer& m, const LiftState& l) {
    Scene s{"live:rest-timer"}; Builder b(s, m);
    float frac = l.restTotalS ? std::clamp(float(l.restRemainingS) / float(l.restTotalS), 0.f, 1.f) : 0.f;
    b.arc(-140, 140, 6, "line", RADIUS - EDGE_INSET - 3, "restTrack"); if (frac > 0.01f) b.arc(-140, -140 + 280 * frac, 6, "accent", RADIUS - EDGE_INSET - 3, "restArc");
    b.metric("REST · SET " + std::to_string(std::min(l.setIndex + 1, l.setTotal)) + " OF " + std::to_string(l.setTotal), mmss(l.restRemainingS), "", 36, 50, "text", "rest");
    b.text(l.nextLabel(), 118, {11, 11, 1, false}, Role::Label, true, "mut", 16);
    b.moreText(l.nextExercise, 132, {14, 13, 1, false}, Role::Body, true, "text", 18, "next");
    b.button("Skip rest", CX - 39, CTRL_Y, 72, "card2", "text", true, "skipRest"); b.button(l.paused ? "Resume" : "Pause", CX + 39, CTRL_Y, 72, "accent", "onAccent", true, l.paused ? "resume" : "pause");
    return s;
}
inline Scene restTimer(const TextMeasurer& m, const Content& c) { return restTimer(m, LiftState::from(c)); }
/// Workout controls overlay (Key 1 preview, swipe up): Pause / Resume · End workout (confirms) · Correct reps.
inline Scene liftControls(const TextMeasurer& m, const LiftState& l) {
    Scene s{"live:lift-controls"}; Builder b(s, m);
    b.text("WORKOUT CONTROLS", 36, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    b.button("Correct", CX - 39, 58, 72, "card2", "text", false, "correct"); b.button(l.paused ? "Resume" : "Pause", CX + 39, 58, 72, "accent", "onAccent", true, l.paused ? "resume" : "pause");
    b.button("End workout", CX, 108, 130, "grade.red", "onAccent", true, "end");
    b.text(std::to_string(l.setsLogged) + " sets logged · " + std::to_string(l.elapsedS / 60) + " min · swipe down to return", 166, {11, 11, 2, false}, Role::Label, true, "mut", 16);
    return s;
}
inline Scene liftControls(const TextMeasurer& m, const Content& c) { return liftControls(m, LiftState::from(c)); }

// ---------------------------------------------------------------- lifecycle screens (prepare · confirm end · review) and the face picker
struct PrepareState { std::string title = "Outdoor cycling"; std::string plan = "Endurance ride · 60 min"; std::string sensors = "iPhone linked · GPS via phone"; bool phoneLinked = true; bool cycling = true; };
inline Scene prepare(const TextMeasurer& m, const PrepareState& p) {
    Scene s{p.cycling ? "prepare:ride" : "prepare:lift"}; Builder b(s, m);
    b.text(p.cycling ? "READY TO RIDE" : "READY TO LIFT", 34, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    b.moreText(p.title, 50, {17, 14, 2, false}, Role::Body, true, "text", 16, "title");
    b.text(p.plan, 96, {13, 13, 2, false}, Role::Body, false, "mut", 18);
    b.text(p.sensors, 128, {11, 11, 1, false}, Role::Label, true, p.phoneLinked ? "mut" : "grade.yellow", 14);
    b.button("Start", CX, 160, 120, "grade.green", "onAccent", true, "start");
    b.text("Key 1 · back", 208, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    return s;
}
inline Scene confirmEnd(const TextMeasurer& m, bool cycling, uint32_t elapsedS, uint32_t distanceM) {
    Scene s{cycling ? "live:ride-confirm-end" : "live:lift-confirm-end"}; Builder b(s, m);
    b.text(cycling ? "END THIS RIDE?" : "END THIS WORKOUT?", 44, {11, 11, 1, false}, Role::Label, true, "grade.yellow", 14);
    b.text(mmss(elapsedS) + (cycling ? " · " + km(distanceM) : ""), 62, {22, 20, 1, false}, Role::Value, true, "text", 8);
    b.text("Recording continues until you confirm.", 100, {13, 13, 2, false}, Role::Body, false, "mut", 20);
    b.button("Keep", CX - 39, 150, 72, "accent", "onAccent", true, "keep"); b.button("End", CX + 39, 150, 72, "grade.red", "onAccent", true, "endConfirm");
    return s;
}
struct ReviewState { bool cycling = true; uint32_t elapsedS = 3600; uint32_t distanceM = 28400; std::optional<int> avgPower, avgHr; int setsLogged = 0; int exercises = 0; bool phoneLinked = true; };
inline Scene review(const TextMeasurer& m, const ReviewState& r) {
    Scene s{r.cycling ? "review:ride" : "review:lift"}; Builder b(s, m);
    b.text(r.cycling ? "RIDE DONE" : "WORKOUT DONE", 34, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    b.text(mmss(r.elapsedS), 50, {34, 24, 1, false}, Role::Value, true, "text", 20);
    std::string line = r.cycling ? km(r.distanceM) + (r.avgPower ? " · " + std::to_string(*r.avgPower) + " W" : "") + (r.avgHr ? " · " + std::to_string(*r.avgHr) + " bpm" : "") : std::to_string(r.setsLogged) + " sets · " + std::to_string(r.exercises) + " exercises";
    b.text(line, 96, {14, 13, 1, false}, Role::Comp, true, "text", 16);
    b.text(r.phoneLinked ? "Saves to the iPhone now" : "Saved on the watch · syncs when the iPhone is back", 118, {12, 11, 2, false}, Role::Label, true, r.phoneLinked ? "mut" : "grade.yellow", 16);
    b.button("Discard", CX - 39, 160, 72, "card2", "text", false, "discard"); b.button("Save", CX + 39, 160, 72, "grade.green", "onAccent", true, "save");
    return s;
}
inline Scene facePicker(const TextMeasurer& m, int current) {
    Scene s{"menu:faces"}; Builder b(s, m);
    b.text("WATCH FACE", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    const char* names[] = {"Orbit", "Chrono", "Pulse"}; float y = 46;
    for (int i = 0; i < 3; i++) { b.row(names[i], i == current ? "✓" : "", y, 44, "face" + std::to_string(i)); y += 48; }
    b.text("swipe down · back", 196, {11, 11, 1, false}, Role::Label, true, "mut", 6);
    return s;
}
struct TodayState { std::string title = "Endurance ride"; std::string when = "17:30 · 60 min"; std::string detail = "Zone 2 · 180–216 W"; bool none = false; std::string syncAge = "synced 06:10"; };
inline Scene today(const TextMeasurer& m, const TodayState& t) {
    Scene s{"panel:today"}; Builder b(s, m);
    b.textFirstFit({"TODAY · " + t.syncAge, "TODAY"}, 32, {11, 11, 1, false}, Role::Label, true, "mut", 6);
    if (t.none) { b.text("No session planned", 70, {16, 13, 2, false}, Role::Body, true, "text", 16); b.text("Rest day — recovery matters as much as the work", 108, {13, 13, 2, false}, Role::Body, false, "mut", 18); }
    else { b.moreText(t.title, 52, {18, 14, 2, false}, Role::Body, true, "text", 16, "title"); b.text(t.when, 100, {14, 13, 1, false}, Role::Comp, true, "text", 16); b.text(t.detail, 120, {13, 13, 2, false}, Role::Body, false, "mut", 18); }
    b.button("Start", CX, 160, 110, "grade.green", "onAccent", false, "start");
    return s;
}

// ---------------------------------------------------------------- panels
/// Recovery answers ONE question — "What should I do differently today?" — with one insight; the measurements that
/// produced it sit under it with their source and time.
inline Scene recovery(const TextMeasurer& m, const Content& c) {
    Scene s{"panel:recovery"}; Builder b(s, m);
    b.text("RECOVERY · 06:10", 30, {11, 11, 1, false}, Role::Label, true, "mut", 8);
    std::string tok = c.recoveryFrac >= 0.75f ? "grade.green" : c.recoveryFrac >= 0.5f ? "grade.blue" : c.recoveryFrac >= 0.3f ? "grade.yellow" : "grade.red";
    b.dot(CX, 52, 5, tok);
    b.text(c.insight, 60, {16, 13, 2, false}, Role::Body, true, "text", 16, false, "insight");
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


// ---------------------------------------------------------------- physical-key preview (two-press system, first press)
/// The chip that appears on a FIRST press: key name + the action it will perform + "press again". It sits in the top
/// band over the status line (the status returns when the preview expires after 2.5 s) and never covers a control.
inline Scene withKeyPreview(Scene base, const TextMeasurer& m, const std::string& label, const std::string& suffix, float y, const std::vector<std::string>& hideIds) {
    std::vector<Element> keep; for (auto& e : base.els) if (std::find(hideIds.begin(), hideIds.end(), e.id) == hideIds.end()) keep.push_back(e);
    base.els = keep; Builder b(base, m);
    Rect chip = bandAt(y, 32, 16); b.panel(chip, "accent");
    b.textIn(label, {chip.x + 8, chip.y + 2, chip.w - 16, 15}, {12, 12, 1, false}, Role::Comp, true, "onAccent", false, "keyPreview");
    b.textIn("press again", {chip.x + 8, chip.y + 17, chip.w - 16, 14}, {11, 11, 1, false}, Role::Label, false, "onAccent", false, "keyPreviewHint");
    base.name += suffix; return base;
}

/// Every primary screen (owner §4 list) for one content set.
inline std::vector<Scene> allScreens(const TextMeasurer& m, const Content& c) {
    std::vector<Scene> v = {faceOrbit(m, c), faceChrono(m, c), facePulse(m, c), activities(m, c)};
    for (auto& fx : rideFixtures(c)) { RideFrame f = fx->frame(); Scene a = rideCockpit(m, f); a.name += ":" + fx->name; v.push_back(a);
        for (auto pg : fx->perfPages) { Scene b2 = ridePerformance(m, f, pg); b2.name += ":" + fx->name; v.push_back(b2); }
        Scene n = rideNavigation(m, f); n.name += ":" + fx->name; v.push_back(n);
        if (fx->controls) { Scene ctl = rideControls(m, f); ctl.name += ":" + fx->name; v.push_back(ctl); }
        if (fx->controls && !fx->live.paused) {
            v.push_back(withKeyPreview(rideCockpit(m, f), m, cyw::TwoPress::labelFor(cyw::Key::Key2, cyw::Press::Short, cyw::Action::Lap), "-key2:" + fx->name, 148, {"command", "sec0", "sec1"}));
            v.push_back(withKeyPreview(rideCockpit(m, f), m, cyw::TwoPress::labelFor(cyw::Key::Key1, cyw::Press::Long, cyw::Action::EndRequest), "-key1hold:" + fx->name, 148, {"command", "sec0", "sec1"})); } }
    for (auto& x : {liftExercise(m, c), withKeyPreview(liftExercise(m, c), m, cyw::TwoPress::labelFor(cyw::Key::Key2, cyw::Press::Short, cyw::Action::LogSet), "-key2", 34, {"exercise", "more"}), repCounter(m, c), restTimer(m, c), liftControls(m, c), prepare(m, PrepareState{c.activity, c.nextSession, "iPhone linked · GPS via phone", true, true}), confirmEnd(m, true, 1458, 11600), review(m, ReviewState{}), facePicker(m, 0), today(m, TodayState{c.nextSession, "17:30 · 60 min", "Zone 2 · " + c.target, false, "synced 06:10"}), recovery(m, c), sleep(m, c), hrv(m, c), coach(m, c), notifications(m, c), settings(m, c), timers(m, c)}) v.push_back(x);
    { Content t = c; t.timerRunning = true; t.timerRemainingS = 137; t.timerTotalS = 180; Scene r = timers(m, t); r.name += ":running"; v.push_back(r); t.timerRunning = false; t.timerRinging = true; t.timerRemainingS = 0; Scene d = timers(m, t); d.name += ":done"; v.push_back(d); }
    { Content t = c; t.dnd = true; t.brightness = "100 %"; t.battery = "—"; t.linkLine = "not linked"; Scene q = settings(m, t); q.name += ":dnd"; v.push_back(q); }
    return v;
}

/// Text-length variants (owner §1/§4: long activity and exercise names, long coaching text, translated strings).
inline std::vector<std::pair<std::string, Content>> contentVariants() {
    Content shortC; Content longC = shortC, extreme = shortC, de = shortC;
    longC.exercise = "Single-arm dumbbell row"; longC.activity = "Functional strength training"; longC.coachShort = "Reduce power — above today's endurance target"; longC.coachLong = "Your sleep was shorter than usual and yesterday's load was high. Consider an easier session today."; longC.nextSession = "Endurance ride · 90 min · 17:30"; longC.value = "1024"; longC.insight = "HIGH LOAD · EASY DAY"; longC.nextExercise = "Seated cable row"; longC.notification = "Your coach moved tomorrow's strength session to Thursday because of the ride planned on Wednesday evening";
    longC.activities = {"Outdoor cycling", "Indoor cycling (trainer)", "Strength training", "Functional strength training", "Hybrid workout", "Walking", "Running", "Hiking", "Mobility and stretching", "Recovery session", "Custom activity"};
    extreme.exercise = "Bulgarian split squat with dumbbells, rear foot elevated"; extreme.coachShort = "Your heart-rate sensor disconnected — recording continues"; extreme.coachLong = "Reduce power now. You have been above today's endurance target for more than two minutes and the session goal is steady aerobic work, not intensity."; extreme.time = "23:59"; extreme.value = "2048"; extreme.steps = "28 412"; extreme.sleep = "10 h 05"; extreme.restS = "12:00"; extreme.recovery = "Limited"; extreme.insight = "REDUCE INTENSITY TODAY"; extreme.nextExercise = "Romanian deadlift with dumbbells"; extreme.recoveryFrac = 0.32f; extreme.recoveryWord = "LOW"; extreme.loadPct = 100; extreme.hourHand = 23; extreme.minuteHand = 59;
    de.exercise = "Kreuzheben mit Kurzhanteln"; de.coachShort = "Leistung reduzieren — über dem Ziel"; de.coachLong = "Dein Schlaf war kürzer als üblich — halte die heutige Einheit locker."; de.nextSession = "Ausdauerfahrt · 60 Min · 17:30"; de.date = "SO 8 NOV"; de.activities = {"Radfahren draußen", "Radfahren drinnen", "Krafttraining", "Funktionelles Krafttraining", "Hybrid-Training", "Gehen"}; de.recovery = "Gut"; de.insight = "WENIG SCHLAF · LOCKER"; de.nextExercise = "Schrägbankdrücken"; de.recoveryWord = "GUT";
    return {{"short", shortC}, {"long", longC}, {"extreme", extreme}, {"german", de}};
}

} // namespace cyw::ui
