#pragma once
// Cyclift Watch OS — the application model (owner 8 Nov 16:44, priorities 3–4): ONE pure state machine that owns
// every screen's real state, consumes touch / key / BLE / clock inputs and produces the current Scene plus outgoing
// frames, haptics and persistence requests. The firmware shell (Arduino + LVGL) is a thin adapter around it; the host
// tests drive it directly. Nothing here is a demonstration number: every value comes from the phone link, the sensors
// or the athlete, and is shown as missing / stale / disconnected otherwise.
#include <cstdint>
#include <string>
#include <vector>
#include <optional>
#include <algorithm>
#include "activity.hpp"
#include "navigation.hpp"
#include "buttons.hpp"
#include "coach.hpp"
#include "sync.hpp"
#include "payloads.hpp"
#include "strength.hpp"
#include "rep_detector.hpp"
#include "ride_telemetry.hpp"
#include "screens.hpp"
#include "theme_tokens.hpp"
#include "../hal/hal.hpp"

namespace cyw::app {

enum class Overlay : uint8_t { None, RideControls, LiftControls, ConfirmEnd, FacePicker, RepConfirm };

struct Persist {                                   // what the shell writes to LittleFS when `dirty` flags are set
    uint8_t face = 0, appearance = 0; uint32_t eventSeq = 0, eventAcked = 0; bool dirty = false;
};

class AppModel {
public:
    AppModel() { live_.recording = false; }

    // ------------------------------------------------------------ inputs: link + frames
    void onConnected(bool linked, uint32_t nowMs) {
        if (phoneLinked_ == linked) return;
        phoneLinked_ = linked; live_.phoneLinked = linked; gps_.onPhoneLink(linked, nowMs); dirty_ = true;
        if (!linked) { coach_.receive(LocalRules::phoneLost(nowMs), nowMs); haptic_ = std::max<uint16_t>(haptic_, 40); }
        else { for (auto& e : events_.pending()) outbox_.push_back({PROTOCOL_VERSION, MsgType::Event, uint16_t(e.seq), wire::encodeEvent(e, deviceId_)}); coach_.dismiss(0xF0000002); }
    }
    void onFrame(const Frame& f, uint32_t nowMs) {
        lastFrameMs_ = nowMs; dirty_ = true;
        switch (f.type) {
            case MsgType::TimeSync: if (auto t = wire::TimeSync::decode(f.payload)) { clock_.apply(t->unixS, t->ms, nowMs, rtcUnixS_); tzOffsetMin_ = t->tzOffsetMin; timeKnown_ = true; } break;
            case MsgType::Live: if (auto l = wire::Live::decode(f.payload)) applyLive(*l, nowMs); break;
            case MsgType::Gps: if (auto g = wire::Gps::decode(f.payload)) { ride::Fix fx{g->latE7 / 1e7, g->lonE7 / 1e7, g->speedKmh10 / 10.f, float(g->headingDeg), g->phoneUnixS, nowMs - g->ageMs}; gps_.onFix(fx); live_.speedKmh = {g->speedKmh10 / 10.f, g->ageMs}; } break;
            case MsgType::Coach: if (auto c = wire::Coach::decode(f.payload)) { CoachMessage m; m.id = c->id; m.instruction = c->instruction; m.reason = c->reason; m.target = c->target; m.priority = Priority(std::min<uint8_t>(c->priority, 3)); m.context = Context(std::min<uint8_t>(c->context, 4)); m.requiresAction = c->requiresAction; m.safety = c->safety; m.expiresAtMs = c->expiresInS ? nowMs + c->expiresInS * 1000u : 0; if (coach_.receive(m, nowMs) && CoachInbox::wantsHaptic(m)) haptic_ = std::max<uint16_t>(haptic_, 60); } break;
            case MsgType::PlanToday: if (auto p = wire::PlanToday::decode(f.payload)) { plan_ = *p; planKnown_ = true; } break;
            case MsgType::Cached: if (auto c = wire::Cached::decode(f.payload)) { cached_ = *c; cachedKnown_ = true; } break;
            case MsgType::Ack: if (auto a = wire::decodeAck(f.payload)) { events_.ack(*a); persist_.eventAcked = events_.ackedUpTo(); persist_.dirty = true; } break;
            default: break;
        }
    }
    void setRtc(uint32_t unixS) { rtcUnixS_ = unixS; if (!timeKnown_ && unixS > 1'600'000'000u) { rtcValid_ = true; } }
    void setBattery(uint8_t pct, bool charging, bool known) { batteryPct_ = pct; charging_ = charging; batteryKnown_ = known; }
    void onAccel(const Accel& a, uint32_t nowMs) { if (lift_ && overlay_ == Overlay::None && nav_.current() == Screen::LiftExercise && !lift_->resting(nowMs) && session_ && session_->phase() == Phase::Active) { if (rep_.feed(a, nowMs)) { dirty_ = true; haptic_ = std::max<uint16_t>(haptic_, 10); } } }

    // ------------------------------------------------------------ inputs: touch + keys
    /// Touch: taps are hit-tested against the LAST rendered scene's buttons (ids), swipes go to the navigator.
    bool onTouch(const hal::TouchEvent& t, uint32_t nowMs) {
        screenOn(nowMs);
        switch (t.kind) {
            case hal::TouchEvent::Tap: { std::string id = hitTest(t.x, t.y); if (!id.empty()) { button(id, nowMs); return true; } if (overlay_ == Overlay::None && !nav_.activityRunning() && nav_.current() == Screen::Face) { nav_.handle(Gesture::Tap); dirty_ = true; return true; } return false; }
            case hal::TouchEvent::LongPress: if (overlay_ == Overlay::None && nav_.current() == Screen::Face) { overlay_ = Overlay::FacePicker; dirty_ = true; return true; } return false;
            case hal::TouchEvent::SwipeUp: if (overlay_ == Overlay::None && nav_.activityRunning()) { overlay_ = cycling_ ? Overlay::RideControls : Overlay::LiftControls; dirty_ = true; return true; } return gesture(Gesture::SwipeUp);
            case hal::TouchEvent::SwipeDown: if (overlay_ != Overlay::None && overlay_ != Overlay::ConfirmEnd && overlay_ != Overlay::RepConfirm) { overlay_ = Overlay::None; dirty_ = true; return true; } return gesture(Gesture::SwipeDown);
            case hal::TouchEvent::SwipeLeft: if (overlay_ != Overlay::None) return false; if (nav_.current() == Screen::RidePerformance) { perfPage_ = ui::PerfPage((int(perfPage_) + 1) % 4); dirty_ = true; return true; } return gesture(Gesture::SwipeLeft);
            case hal::TouchEvent::SwipeRight: if (overlay_ != Overlay::None) return false; if (nav_.current() == Screen::RidePerformance && int(perfPage_) > 0) { perfPage_ = ui::PerfPage(int(perfPage_) - 1); dirty_ = true; return true; } return gesture(Gesture::SwipeRight);
            default: return false;
        }
    }
    /// Physical keys: raw level per key → debounce → two-press preview / confirm → action.
    void onKey(Key k, bool pressed, uint32_t nowMs) {
        auto ev = keys_[int(k)].feed(pressed, nowMs); if (!ev.fired) return;
        if (!screenOn_) { screenOn(nowMs); return; }                                   // any key wakes; the press is consumed
        auto r = twoPress_.press(k, ev.press, mode(), false, phoneLinked_, nowMs);
        if (r.preview) { keyPreview_ = r.label; keyPreviewUntil_ = nowMs + 2500; haptic_ = std::max<uint16_t>(haptic_, r.hapticMs); dirty_ = true; }
        else if (r.execute) { keyPreview_.clear(); haptic_ = std::max<uint16_t>(haptic_, r.hapticMs); act(r.action, nowMs); }
    }

    // ------------------------------------------------------------ time
    void tick(uint32_t nowMs) {
        if (nowMs - lastTickMs_ < 1000) return; lastTickMs_ = nowMs;
        coach_.purgeExpired(nowMs);
        if (twoPress_.tick(nowMs)) { keyPreview_.clear(); dirty_ = true; }
        if (!keyPreview_.empty() && nowMs >= keyPreviewUntil_) { keyPreview_.clear(); dirty_ = true; }
        if (session_ && session_->phase() == Phase::Active && cycling_) { uint32_t t = session_->activeMs(nowMs) / 1000; power_.push(t, live_.power.fresh(3000) ? live_.power.value : std::nullopt); hr_.push(t, live_.hr.fresh(5000) ? live_.hr.value : std::nullopt); cad_.push(t, live_.cadence.fresh(3000) ? live_.cadence.value : std::nullopt); zt_.add(live_.hr.fresh(5000) ? live_.hr.value : std::nullopt, live_.hrZones); }
        // ages grow when the phone stops sending (the Live frame carries ages at send time)
        if (phoneLinked_ && lastLiveMs_ && nowMs - lastLiveMs_ > 1000) { uint32_t d = nowMs - lastLiveMs_; auto age = [&](ride::Reading& r) { if (r.value) r.ageMs = std::min<uint32_t>(r.ageMs + 1000, UINT32_MAX - 1); }; (void)d; age(live_.power); age(live_.hr); age(live_.cadence); age(live_.speedKmh); }
        if (lift_ && nav_.current() == Screen::LiftRest && !lift_->resting(nowMs)) { nav_.handle(Gesture::SwipeRight); haptic_ = std::max<uint16_t>(haptic_, 40); }
        if (nav_.activityRunning() || nav_.current() == Screen::Face) dirty_ = true;   // clocks and timers move
        if (phoneLinked_ && nowMs - lastStatusMs_ > 30000) { lastStatusMs_ = nowMs; wire::Status s; s.batteryPct = batteryPct_; s.charging = charging_; s.phase = session_ ? uint8_t(session_->phase()) : 0; s.pendingEvents = uint32_t(events_.pending().size()); outbox_.push_back({PROTOCOL_VERSION, MsgType::Status, uint16_t(++txSeq_), s.encode()}); }
        if (screenOn_ && !nav_.activityRunning() && nowMs - lastInteractionMs_ > 15000) { screenOn_ = false; dirty_ = true; }
    }

    // ------------------------------------------------------------ outputs
    bool takeDirty() { bool d = dirty_; dirty_ = false; return d; }
    uint16_t takeHaptic() { uint16_t h = haptic_; haptic_ = 0; return h; }
    std::vector<Frame> takeOutbox() { auto v = std::move(outbox_); outbox_.clear(); return v; }
    Persist& persist() { return persist_; }
    bool screenIsOn() const { return screenOn_; }
    const ui::Appearance& appearance() const { return ui::appearances()[persist_.appearance % ui::appearances().size()]; }
    void restore(const Persist& p, std::vector<WatchEvent> pending) { persist_ = p; persist_.dirty = false; events_.restore(p.eventSeq, p.eventAcked, std::move(pending)); }
    void setDeviceId(const std::string& id) { deviceId_ = id; }

    /// The current screen. Also remembered for touch hit-testing.
    ui::Scene render(const ui::TextMeasurer& m, uint32_t nowMs) {
        ui::Scene s = renderInner(m, nowMs);
        if (!keyPreview_.empty()) s = ui::withKeyPreview(s, m, keyPreview_, "", keyPreviewY(), keyPreviewHides());
        last_ = s; return s;
    }

    // ------------------------------------------------------------ read-only accessors for tests / status
    const Navigator& nav() const { return nav_; }
    Overlay overlay() const { return overlay_; }
    const std::optional<ActivitySession>& session() const { return session_; }
    const std::optional<StrengthSession>& lift() const { return lift_; }
    const EventQueue& events() const { return events_; }
    const ride::Live& live() const { return live_; }
    bool phoneLinked() const { return phoneLinked_; }
    ui::PerfPage perfPage() const { return perfPage_; }
    const std::string& keyPreview() const { return keyPreview_; }

private:
    // ------------------------------------------------------------ actions
    Mode mode() const {
        if (overlay_ != Overlay::None && overlay_ != Overlay::RideControls && overlay_ != Overlay::LiftControls) return Mode::Menu;
        if (nav_.activityRunning()) { if (!cycling_) return nav_.current() == Screen::LiftRest ? Mode::Live_Rest : Mode::Live_Lift; return Mode::Live_Ride; }
        switch (nav_.current()) { case Screen::Face: return Mode::Face; case Screen::RideReview: case Screen::LiftReview: case Screen::Review: return Mode::Review; case Screen::Activities: case Screen::QuickSettings: return Mode::Menu; default: return Mode::Panel; }
    }
    bool gesture(Gesture g) { if (nav_.handle(g)) { dirty_ = true; return true; } return false; }
    void screenOn(uint32_t nowMs) { lastInteractionMs_ = nowMs; if (!screenOn_) { screenOn_ = true; dirty_ = true; } }
    std::string hitTest(int16_t x, int16_t y) const {
        for (auto it = last_.els.rbegin(); it != last_.els.rend(); ++it) if (it->kind == ui::Kind::Rect && it->role == ui::Role::Button && !it->id.empty() && x >= it->r.x && x <= it->r.right() && y >= it->r.y && y <= it->r.bottom()) return it->id;
        return "";
    }
    void act(Action a, uint32_t nowMs) {
        dirty_ = true;
        switch (a) {
            case Action::OpenActivities: overlay_ = Overlay::None; nav_.handle(Gesture::SwipeUp); break;
            case Action::OpenQuickSettings: overlay_ = Overlay::None; nav_.handle(Gesture::SwipeDown); break;
            case Action::Back: if (overlay_ != Overlay::None) overlay_ = Overlay::None; else nav_.handle(Gesture::Button1); break;
            case Action::Home: overlay_ = Overlay::None; while (nav_.current() != Screen::Face && nav_.handle(Gesture::Button1)) {} break;
            case Action::TogglePause: togglePause(nowMs); break;
            case Action::Lap: lap(nowMs); break;
            case Action::EndRequest: if (session_ && (session_->phase() == Phase::Active || session_->phase() == Phase::Paused)) overlay_ = Overlay::ConfirmEnd; break;
            case Action::LogSet: logSet(false, nowMs); break;
            case Action::OpenCorrections: if (lift_) overlay_ = Overlay::RepConfirm; break;
            case Action::SkipRest: if (lift_) { lift_->skipRest(); nav_.handle(Gesture::SwipeRight); } break;
            case Action::Save: save(nowMs); break;
            case Action::Discard: discard(nowMs); break;
            case Action::Confirm: if (overlay_ == Overlay::RepConfirm) logSet(true, nowMs); break;
            default: break;
        }
    }
    void button(const std::string& id, uint32_t nowMs) {
        dirty_ = true;
        if (id == "pause" || id == "resume") { togglePause(nowMs); return; }
        if (id == "lap") { lap(nowMs); return; }
        if (id == "end") { overlay_ = Overlay::ConfirmEnd; return; }
        if (id == "keep") { overlay_ = Overlay::None; return; }
        if (id == "endConfirm") { endNow(nowMs); return; }
        if (id == "logSet") { logSet(false, nowMs); return; }
        if (id == "correct") { if (lift_) overlay_ = Overlay::RepConfirm; return; }
        if (id == "confirm") { logSet(true, nowMs); return; }
        if (id == "skipRest") { if (lift_) { lift_->skipRest(); nav_.handle(Gesture::SwipeRight); } return; }
        if (id == "save") { save(nowMs); return; }
        if (id == "discard") { discard(nowMs); return; }
        if (id == "start") { startFromPrepare(nowMs); return; }
        if (id == "why" || id == "more") { return; }
        if (id.rfind("act", 0) == 0) { size_t i = std::stoul(id.substr(3)); if (i < activityRegistry().size()) { pendingType_ = &activityRegistry()[i]; nav_.handle(Gesture::Button1); navTo(pendingType_->strength && !pendingType_->outdoor ? Screen::LiftPrepare : Screen::RidePrepare); } return; }
        if (id.rfind("face", 0) == 0 && id.size() == 5) { persist_.face = uint8_t(id[4] - '0') % 3; persist_.dirty = true; overlay_ = Overlay::None; return; }
        if (id == "s3") { persist_.appearance = uint8_t((persist_.appearance + 1) % ui::appearances().size()); persist_.dirty = true; return; }
    }
    void navTo(Screen s) { prepareScreen_ = s; }
    void startFromPrepare(uint32_t nowMs) {
        const ActivityType* t = pendingType_ ? pendingType_ : (planKnown_ && plan_.kind == 2 ? findActivity("strength") : findActivity("cycling_outdoor"));
        if (!t) return;
        cycling_ = !(t->strength && !t->outdoor);
        session_.emplace(*t); session_->prepare(nowMs); session_->start(nowMs);
        workoutId_ = planKnown_ ? plan_.workoutId : "watch-" + std::to_string(nowMs);
        power_ = ride::Series(300); hr_ = ride::Series(300); cad_ = ride::Series(300); zt_ = ride::ZoneTime{}; perfPage_ = ui::PerfPage::Power;
        if (!cycling_) { std::vector<PlannedExercise> plan; if (planKnown_ && plan_.kind == 2) for (auto& e : plan_.exercises) { PlannedExercise pe; pe.id = e.id; pe.name = e.name; pe.restS = e.restS; pe.superset = e.superset; for (int i = 0; i < e.sets; i++) pe.sets.push_back({e.reps, e.weightKg10 / 10.f, e.weightKg10 == 0}); plan.push_back(pe); } if (plan.empty()) { PlannedExercise pe; pe.id = "free"; pe.name = "Free set"; pe.sets = {{0, 0, true}, {0, 0, true}, {0, 0, true}}; plan.push_back(pe); } lift_.emplace(plan); rep_.reset(); }
        nav_.startActivity(cycling_, !cycling_); overlay_ = Overlay::None; prepareScreen_ = std::nullopt; pendingType_ = nullptr;
        emit(1, nowMs); haptic_ = std::max<uint16_t>(haptic_, 40);
    }
    void togglePause(uint32_t nowMs) {
        if (!session_) return;
        if (session_->phase() == Phase::Active) { session_->pause(nowMs); live_.paused = true; emit(2, nowMs); }
        else if (session_->phase() == Phase::Paused) { session_->resume(nowMs); live_.paused = false; emit(3, nowMs); }
        overlay_ = overlay_ == Overlay::RideControls || overlay_ == Overlay::LiftControls ? Overlay::None : overlay_;
    }
    void lap(uint32_t nowMs) { if (!session_ || session_->phase() != Phase::Active) return; laps_++; emit(5, nowMs, laps_); haptic_ = std::max<uint16_t>(haptic_, 40); overlay_ = Overlay::None; }
    void endNow(uint32_t nowMs) {
        if (!session_) return;
        if (session_->phase() == Phase::Active) session_->pause(nowMs);
        session_->end(nowMs); session_->review(); emit(4, nowMs); live_.recording = false; live_.paused = false;
        overlay_ = Overlay::None; nav_.endActivity(); haptic_ = std::max<uint16_t>(haptic_, 60);
    }
    void logSet(bool fromConfirm, uint32_t nowMs) {
        if (!lift_ || !session_) return;
        uint8_t reps = fromConfirm || overlay_ == Overlay::RepConfirm ? uint8_t(std::min<uint32_t>(rep_.count(), 255)) : uint8_t(std::min<uint32_t>(rep_.count() ? rep_.count() : (lift_->currentTarget() ? lift_->currentTarget()->targetReps : 0), 255));
        bool autoCounted = rep_.count() > 0;
        auto s = lift_->logSet(reps, std::nullopt, autoCounted, nowMs);
        emit(6, nowMs, s.exercise * 100 + s.set, s.reps, int32_t(s.weightKg * 10), !autoCounted);
        rep_.reset(); overlay_ = Overlay::None; haptic_ = std::max<uint16_t>(haptic_, 40);
        if (lift_->finished()) { endNow(nowMs); return; }
        if (lift_->resting(nowMs)) nav_.handle(Gesture::SwipeLeft);
    }
    void save(uint32_t nowMs) { if (!session_) return; session_->save(); emit(9, nowMs); session_.reset(); lift_.reset(); nav_.finishReview(); haptic_ = std::max<uint16_t>(haptic_, 40); }
    void discard(uint32_t nowMs) { if (!session_) return; session_->discard(); emit(8, nowMs); session_.reset(); lift_.reset(); nav_.finishReview(); }
    void emit(uint8_t kind, uint32_t nowMs, int32_t a = 0, int32_t b = 0, int32_t c = 0, bool manual = false) {
        WatchEvent e; e.watchUnixS = unixS(nowMs); e.kind = kind; e.workoutId = workoutId_; e.a = a; e.b = b; e.c = c; e.manual = manual;
        auto& stored = events_.push(e); persist_.eventSeq = events_.lastSeq(); persist_.dirty = true;
        if (phoneLinked_) outbox_.push_back({PROTOCOL_VERSION, MsgType::Event, uint16_t(stored.seq), wire::encodeEvent(stored, deviceId_)});
    }
    void applyLive(const wire::Live& l, uint32_t nowMs) {
        lastLiveMs_ = nowMs;
        auto rd = [](std::optional<uint16_t> v, uint16_t age, float scale = 1.f) { ride::Reading r; if (v) { r.value = *v * scale; r.ageMs = age; } return r; };
        live_.power = rd(l.powerW, l.powerAgeMs); live_.hr = rd(l.hrBpm, l.hrAgeMs); live_.cadence = rd(l.cadenceRpm, l.cadenceAgeMs); if (l.speedKmh10) live_.speedKmh = rd(l.speedKmh10, l.speedAgeMs, 0.1f);
        live_.ftpKnown = l.ftpKnown; live_.ftp = l.ftpW;
        live_.powerBand = l.powerBandW ? std::optional<std::pair<int, int>>(std::make_pair(int(l.powerBandW->first), int(l.powerBandW->second))) : std::nullopt;
        live_.hrBand = l.hrBandBpm ? std::optional<std::pair<int, int>>(std::make_pair(int(l.hrBandBpm->first), int(l.hrBandBpm->second))) : std::nullopt;
        live_.cadenceRange = l.cadenceRange ? std::optional<std::pair<int, int>>(std::make_pair(int(l.cadenceRange->first), int(l.cadenceRange->second))) : std::nullopt;
        live_.stepName = l.stepName; live_.stepRemainingS = l.stepRemainingS; live_.stepTotalS = l.stepTotalS;
        if (!live_.hrZones.empty() || !l.hrBandBpm) {} // zones come from the plan/profile frame; absent → no ladder (honest)
        if (l.distanceM) live_.distanceM = l.distanceM;
    }

    // ------------------------------------------------------------ rendering
    uint32_t unixS(uint32_t nowMs) const { if (timeKnown_) return uint32_t(clock_.nowMs(nowMs) / 1000); if (rtcValid_) return rtcUnixS_; return 0; }
    std::string hhmm(uint32_t nowMs) const { uint32_t u = unixS(nowMs); if (!u) return "--:--"; uint32_t l = u + uint32_t(int32_t(tzOffsetMin_) * 60); uint32_t m = (l / 60) % 1440; char b[8]; std::snprintf(b, sizeof b, "%02u:%02u", m / 60, m % 60); return b; }
    std::string dateLabel(uint32_t nowMs) const {
        uint32_t u = unixS(nowMs); if (!u) return "NOT SYNCED";
        int64_t days = (int64_t(u) + int32_t(tzOffsetMin_) * 60) / 86400; int dow = int((days + 4) % 7);      // 1970-01-01 was a Thursday
        // civil from days (Howard Hinnant)
        int64_t z = days + 719468; int64_t era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = unsigned(z - era * 146097); unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100); unsigned mp = (5 * doy + 2) / 153; unsigned d = doy - (153 * mp + 2) / 5 + 1; unsigned mo = mp < 10 ? mp + 3 : mp - 9;
        static const char* D[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"}; static const char* M[] = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};
        return std::string(D[dow]) + " " + std::to_string(d) + " " + M[mo - 1];
    }
    ui::Content content(uint32_t nowMs) const {
        ui::Content c; c.time = hhmm(nowMs); c.date = dateLabel(nowMs);
        c.battery = batteryKnown_ ? std::to_string(batteryPct_) + " %" : "—";
        c.steps = "—";                                                                 // BMA423 step counter: W1 device work
        if (planKnown_ && plan_.kind) { c.nextSession = plan_.title + " · " + std::to_string(plan_.durationMin) + " min · " + minToHHMM(plan_.startMin); } else c.nextSession = planKnown_ ? "No session today" : (phoneLinked_ ? "Plan not synced yet" : "No iPhone · plan unknown");
        if (cachedKnown_ && cached_.sleepMin) { c.sleep = std::to_string(*cached_.sleepMin / 60) + " h " + (*cached_.sleepMin % 60 < 10 ? "0" : "") + std::to_string(*cached_.sleepMin % 60); c.sleepSrc = (cached_.sleepSource.empty() ? "PHONE" : cached_.sleepSource) + " " + ageLabel(cached_.sleepUnixS, nowMs); } else { c.sleep = "—"; c.sleepSrc = "NO SLEEP DATA"; }
        if (cachedKnown_ && cached_.hrvMs) { c.hrv = std::to_string(*cached_.hrvMs); } else c.hrv = "—";
        c.recovery = cachedKnown_ && cached_.recoveryPct ? cached_.recoveryWord : "—"; c.recoveryWord = cachedKnown_ && cached_.recoveryPct ? cached_.recoveryWord : "—"; c.recoveryFrac = cachedKnown_ && cached_.recoveryPct ? *cached_.recoveryPct / 100.f : 0.f;
        c.loadPct = cachedKnown_ ? cached_.loadPct : 0; c.insight = cachedKnown_ && !cached_.insight.empty() ? cached_.insight : (phoneLinked_ ? "NO INSIGHT YET" : "NO IPHONE · NO INSIGHT");
        const CoachMessage* cm = coach_.primary(nowMs, Context::Any); c.coachLong = cm ? cm->instruction : "No coaching message"; c.coachShort = cm ? cm->wristInstruction() : "";
        c.exercise = lift_ && lift_->current() ? lift_->current()->name : "—";
        uint32_t u = unixS(nowMs); if (u) { uint32_t l = u + uint32_t(int32_t(tzOffsetMin_) * 60); c.hourHand = int((l / 3600) % 24); c.minuteHand = int((l / 60) % 60); }
        c.activities.clear(); for (auto& a : activityRegistry()) c.activities.push_back(a.title);
        return c;
    }
    static std::string minToHHMM(uint16_t m) { char b[8]; std::snprintf(b, sizeof b, "%02u:%02u", m / 60, m % 60); return b; }
    std::string ageLabel(uint32_t when, uint32_t nowMs) const { uint32_t now = unixS(nowMs); if (!now || !when || now < when) return ""; uint32_t a = now - when; if (a < 3600) return std::to_string(a / 60) + " min ago"; if (a < 86400) return std::to_string(a / 3600) + " h ago"; return "> 1 day"; }
    ui::LiftState liftState(uint32_t nowMs) const {
        ui::LiftState l; if (!lift_) return l;
        auto cur = lift_->current(); l.exercise = cur ? cur->name : "Workout complete"; l.nextExercise = cur ? cur->name : "Workout complete";   // after a logged set the session already points at what comes next
        l.setIndex = lift_->currentSet() + 1; l.setTotal = cur ? int(cur->sets.size()) : 0; auto t = lift_->currentTarget(); l.targetReps = t ? t->targetReps : 0; l.weightKg = t && !t->bodyweight ? std::optional<float>(t->weightKg) : std::nullopt;
        l.superset = cur ? cur->superset : 0; l.supersetOrdinal = 1;
        l.reps = int(rep_.count()); l.autoCount = rep_.count() > 0; l.confidence = rep_.count() ? std::optional<float>(rep_.confidence()) : std::nullopt;
        l.restRemainingS = lift_->restRemainingS(nowMs); l.restTotalS = cur ? cur->restS : 60; l.setsLogged = int(lift_->completedSets()); l.elapsedS = session_ ? session_->elapsedMs(nowMs) / 1000 : 0; l.paused = session_ && session_->phase() == Phase::Paused;
        return l;
    }
    ui::RideFrame frame(uint32_t nowMs) {
        ui::RideFrame f; f.live = live_; f.live.recording = session_ && (session_->phase() == Phase::Active || session_->phase() == Phase::Paused); f.live.paused = session_ && session_->phase() == Phase::Paused; f.live.elapsedS = session_ ? session_->activeMs(nowMs) / 1000 : 0; f.live.phoneLinked = phoneLinked_;
        f.power = &power_; f.hr = &hr_; f.cadence = &cad_; f.zoneTime = &zt_; f.gps = &gps_; f.nowMs = nowMs; const CoachMessage* cm = coach_.primary(nowMs, Context::Cycling); f.coachCue = cm ? cm->wristInstruction() : ""; f.windowS = 60; f.northUp = northUp_; return f;
    }
    float keyPreviewY() const { return nav_.activityRunning() && cycling_ ? 148.f : 34.f; }
    std::vector<std::string> keyPreviewHides() const { return nav_.activityRunning() && cycling_ ? std::vector<std::string>{"command", "sec0", "sec1"} : std::vector<std::string>{"exercise", "more"}; }
    ui::Scene renderInner(const ui::TextMeasurer& m, uint32_t nowMs) {
        ui::Content c = content(nowMs);
        if (!screenOn_) { ui::Scene s{"off"}; return s; }
        switch (overlay_) {
            case Overlay::RideControls: return ui::rideControls(m, frame(nowMs));
            case Overlay::LiftControls: return ui::liftControls(m, liftState(nowMs));
            case Overlay::ConfirmEnd: return ui::confirmEnd(m, cycling_, session_ ? session_->elapsedMs(nowMs) / 1000 : 0, live_.distanceM);
            case Overlay::FacePicker: return ui::facePicker(m, persist_.face);
            case Overlay::RepConfirm: return ui::repCounter(m, liftState(nowMs));
            default: break;
        }
        if (prepareScreen_) { const ActivityType* t = pendingType_; ui::PrepareState p; p.title = t ? t->title : "Activity"; p.cycling = !(t && t->strength && !t->outdoor); p.plan = planKnown_ && plan_.kind ? plan_.title + " · " + std::to_string(plan_.durationMin) + " min" : "Free session — no plan synced"; p.phoneLinked = phoneLinked_; p.sensors = phoneLinked_ ? (p.cycling ? "iPhone linked · GPS via phone" : "iPhone linked") : "No iPhone — recording on the watch only"; return ui::prepare(m, p); }
        switch (nav_.current()) {
            case Screen::Face: return persist_.face == 1 ? ui::faceChrono(m, c) : persist_.face == 2 ? ui::facePulse(m, c) : ui::faceOrbit(m, c);
            case Screen::Today: { ui::TodayState t; t.none = !(planKnown_ && plan_.kind); t.title = plan_.title; t.when = minToHHMM(plan_.startMin) + " · " + std::to_string(plan_.durationMin) + " min"; t.detail = plan_.kind == 2 ? std::to_string(plan_.exercises.size()) + " exercises" : "from the iPhone plan"; t.syncAge = planKnown_ ? "synced" : (phoneLinked_ ? "not synced yet" : "no iPhone"); return ui::today(m, t); }
            case Screen::Recovery: return ui::recovery(m, c);
            case Screen::Progress: return ui::sleep(m, c);
            case Screen::Notifications: return ui::coach(m, c);
            case Screen::Activities: return ui::activities(m, c, 0);
            case Screen::QuickSettings: return ui::settings(m, c);
            case Screen::FaceDetail: return ui::hrv(m, c);
            case Screen::FaceActions: return ui::facePicker(m, persist_.face);
            case Screen::RideCockpit: return ui::rideCockpit(m, frame(nowMs));
            case Screen::RideNavigation: return ui::rideNavigation(m, frame(nowMs));
            case Screen::RidePerformance: return ui::ridePerformance(m, frame(nowMs), perfPage_);
            case Screen::LiftExercise: return ui::liftExercise(m, liftState(nowMs));
            case Screen::LiftRest: return ui::restTimer(m, liftState(nowMs));
            case Screen::RideReview: case Screen::LiftReview: case Screen::Review: { ui::ReviewState r; r.cycling = cycling_; r.elapsedS = session_ ? session_->activeMs(nowMs) / 1000 : 0; r.distanceM = live_.distanceM; r.avgPower = power_.average(3600).has_value() ? std::optional<int>(int(std::lround(*power_.average(3600)))) : std::nullopt; r.avgHr = hr_.average(3600).has_value() ? std::optional<int>(int(std::lround(*hr_.average(3600)))) : std::nullopt; r.setsLogged = lift_ ? int(lift_->completedSets()) : 0; r.exercises = lift_ ? int(lift_->totalSets()) : 0; r.phoneLinked = phoneLinked_; return ui::review(m, r); }
            default: return ui::faceOrbit(m, c);
        }
    }

    // ------------------------------------------------------------ state
    Navigator nav_; Overlay overlay_ = Overlay::None; std::optional<Screen> prepareScreen_; const ActivityType* pendingType_ = nullptr;
    bool cycling_ = true; std::optional<ActivitySession> session_; std::optional<StrengthSession> lift_; RepDetector rep_; std::string workoutId_; uint32_t laps_ = 0;
    ride::Live live_; ride::Series power_{300}, hr_{300}, cad_{300}; ride::ZoneTime zt_; ride::GpsMirror gps_; ui::PerfPage perfPage_ = ui::PerfPage::Power; bool northUp_ = false;
    CoachInbox coach_; EventQueue events_; std::string deviceId_ = "watch";
    wire::PlanToday plan_; bool planKnown_ = false; wire::Cached cached_; bool cachedKnown_ = false;
    bool phoneLinked_ = false; uint32_t lastFrameMs_ = 0, lastLiveMs_ = 0, lastStatusMs_ = 0, lastTickMs_ = 0, lastInteractionMs_ = 0; uint16_t txSeq_ = 0;
    ClockSync clock_; bool timeKnown_ = false, rtcValid_ = false; uint32_t rtcUnixS_ = 0; int16_t tzOffsetMin_ = 0;
    uint8_t batteryPct_ = 0; bool charging_ = false, batteryKnown_ = false;
    KeyDecoder keys_[3]; TwoPress twoPress_; std::string keyPreview_; uint32_t keyPreviewUntil_ = 0;
    bool screenOn_ = true, dirty_ = true; uint16_t haptic_ = 0; std::vector<Frame> outbox_; Persist persist_; ui::Scene last_;
};

} // namespace cyw::app
