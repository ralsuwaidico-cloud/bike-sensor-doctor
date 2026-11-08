#pragma once
// Cyclift Watch OS — activity registry and the shared activity lifecycle (owner directive §5):
//   Select → Prepare → Start → Active ⇄ Pause → End → Review → Save
// Pure C++17, no hardware: compiled on the host for tests and on the watch unchanged.
#include <cstdint>
#include <string>
#include <vector>
#include <array>

namespace cyw {

enum class Metric : uint8_t { Time, Distance, Speed, Power, HeartRate, Cadence, Reps, Sets, Weight, RestTimer, Steps, Elevation };
enum class Control : uint8_t { Lap, Pause, Resume, End, LogSet, Undo, SkipRest, AdjustWeight };

/// One entry of the configurable activity registry (§5: new activities are rows here, never new systems).
struct ActivityType {
    const char* id;                 // stable id, also used in the BLE protocol and the iPhone
    const char* title;
    bool outdoor;                   // GPS (from the phone) is meaningful
    bool strength;                  // uses the strength logger / rep detector
    std::vector<Metric> metrics;    // what MAY be shown — a metric is drawn only with a live or valid cached source
    std::vector<Control> controls;
};

inline const std::vector<ActivityType>& activityRegistry() {
    using M = Metric; using C = Control;
    static const std::vector<ActivityType> r = {
        {"cycling_outdoor", "Outdoor cycling", true,  false, {M::Time, M::Distance, M::Speed, M::Power, M::HeartRate, M::Cadence, M::Elevation}, {C::Lap, C::Pause, C::Resume, C::End}},
        {"cycling_indoor",  "Indoor cycling",  false, false, {M::Time, M::Power, M::HeartRate, M::Cadence},                                    {C::Lap, C::Pause, C::Resume, C::End}},
        {"strength",        "Strength training", false, true, {M::Time, M::Reps, M::Sets, M::Weight, M::RestTimer, M::HeartRate},             {C::LogSet, C::Undo, C::SkipRest, C::AdjustWeight, C::Pause, C::Resume, C::End}},
        {"functional",      "Functional strength", false, true, {M::Time, M::Reps, M::Sets, M::RestTimer, M::HeartRate},                      {C::LogSet, C::Undo, C::SkipRest, C::Pause, C::Resume, C::End}},
        {"hybrid",          "Hybrid workout",  true,  true,  {M::Time, M::Distance, M::Power, M::HeartRate, M::Reps, M::Sets, M::RestTimer},    {C::Lap, C::LogSet, C::Undo, C::Pause, C::Resume, C::End}},
        {"walking",         "Walking",         true,  false, {M::Time, M::Distance, M::Steps, M::HeartRate},                                   {C::Pause, C::Resume, C::End}},
        {"running",         "Running",         true,  false, {M::Time, M::Distance, M::Speed, M::HeartRate, M::Cadence},                       {C::Lap, C::Pause, C::Resume, C::End}},
        {"hiking",          "Hiking",          true,  false, {M::Time, M::Distance, M::Elevation, M::Steps, M::HeartRate},                     {C::Pause, C::Resume, C::End}},
        {"mobility",        "Mobility & stretching", false, false, {M::Time, M::RestTimer},                                                   {C::Pause, C::Resume, C::End}},
        {"recovery",        "Recovery session", false, false, {M::Time, M::HeartRate},                                                        {C::Pause, C::Resume, C::End}},
        {"custom",          "Custom activity", false, false, {M::Time, M::HeartRate},                                                         {C::Lap, C::Pause, C::Resume, C::End}},
    };
    return r;
}

inline const ActivityType* findActivity(const std::string& id) {
    for (auto& a : activityRegistry()) if (id == a.id) return &a;
    return nullptr;
}

enum class Phase : uint8_t { Select, Prepare, Active, Paused, Ended, Review, Saved, Discarded };

/// Which data sources are live right now — the lifecycle never claims a metric without one (§5, §9).
struct Sources {
    bool phoneGps = false;     // timestamped positions mirrored from the iPhone
    bool power = false;        // BikeComputer / power meter via the phone or a direct BLE sensor
    bool heartRate = false;    // Apple Watch / Polar / other BLE strap — the watch has no optical sensor
    bool cadence = false;
    bool stepCounter = true;   // BMA423 on the wrist (confirmed hardware)
};

/// The activity lifecycle with honest timers: elapsed (wall clock since start), active (not paused), rest (strength
/// rest timers, counted inside active time), paused.
class ActivitySession {
public:
    explicit ActivitySession(const ActivityType& type) : type_(type) {}

    const ActivityType& type() const { return type_; }
    Phase phase() const { return phase_; }

    bool prepare(uint32_t nowMs) { if (phase_ != Phase::Select) return false; phase_ = Phase::Prepare; preparedMs_ = nowMs; return true; }
    bool start(uint32_t nowMs) {
        if (phase_ != Phase::Prepare && phase_ != Phase::Select) return false;
        phase_ = Phase::Active; startMs_ = nowMs; lastActiveMs_ = nowMs; return true;
    }
    bool pause(uint32_t nowMs) { if (phase_ != Phase::Active) return false; accrue(nowMs); phase_ = Phase::Paused; pausedAtMs_ = nowMs; return true; }
    bool resume(uint32_t nowMs) { if (phase_ != Phase::Paused) return false; pausedMs_ += nowMs - pausedAtMs_; phase_ = Phase::Active; lastActiveMs_ = nowMs; return true; }
    /// End is ALWAYS allowed from Active or Paused — a lost phone or sensor never traps the athlete (owner rule, iPhone RA-20).
    bool end(uint32_t nowMs) {
        if (phase_ == Phase::Active) accrue(nowMs);
        else if (phase_ == Phase::Paused) pausedMs_ += nowMs - pausedAtMs_;
        else return false;
        phase_ = Phase::Ended; endMs_ = nowMs; return true;
    }
    bool review() { if (phase_ != Phase::Ended) return false; phase_ = Phase::Review; return true; }
    bool save() { if (phase_ != Phase::Review && phase_ != Phase::Ended) return false; phase_ = Phase::Saved; return true; }
    bool discard() { if (phase_ != Phase::Review && phase_ != Phase::Ended) return false; phase_ = Phase::Discarded; return true; }

    /// Rest time is counted while a rest timer runs (strength); it is part of active time, shown separately (§7).
    void restTick(uint32_t ms) { restMs_ += ms; }

    uint32_t elapsedMs(uint32_t nowMs) const {
        if (phase_ == Phase::Select || phase_ == Phase::Prepare) return 0;
        uint32_t endRef = (phase_ == Phase::Active || phase_ == Phase::Paused) ? nowMs : endMs_;
        return endRef - startMs_;
    }
    uint32_t activeMs(uint32_t nowMs) const {
        uint32_t a = activeMs_;
        if (phase_ == Phase::Active) a += nowMs - lastActiveMs_;
        return a;
    }
    uint32_t pausedMs(uint32_t nowMs) const { return pausedMs_ + (phase_ == Phase::Paused ? nowMs - pausedAtMs_ : 0); }
    uint32_t restMs() const { return restMs_; }

    /// A metric is offered only if the activity lists it AND a source is live (or, for Time/Reps/Sets/Weight/RestTimer, no
    /// external source is needed). Distance and speed need the phone's GPS; power/HR/cadence need their sensor.
    bool canShow(Metric m, const Sources& s) const {
        bool listed = false; for (auto x : type_.metrics) if (x == m) listed = true;
        if (!listed) return false;
        switch (m) {
            case Metric::Distance: case Metric::Speed: case Metric::Elevation: return s.phoneGps;
            case Metric::Power: return s.power;
            case Metric::HeartRate: return s.heartRate;
            case Metric::Cadence: return s.cadence || s.power;      // a power meter reports cadence too
            case Metric::Steps: return s.stepCounter;
            default: return true;
        }
    }

private:
    void accrue(uint32_t nowMs) { activeMs_ += nowMs - lastActiveMs_; lastActiveMs_ = nowMs; }
    const ActivityType& type_;
    Phase phase_ = Phase::Select;
    uint32_t preparedMs_ = 0, startMs_ = 0, endMs_ = 0, lastActiveMs_ = 0, pausedAtMs_ = 0;
    uint32_t activeMs_ = 0, pausedMs_ = 0, restMs_ = 0;
};

} // namespace cyw
