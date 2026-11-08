#pragma once
// Cyclift Watch OS — experimental wrist-motion repetition detector for the BMA423 (owner directive §6).
//
// Honest scope: the detector finds REPEATED MOVEMENT CYCLES in the wrist's acceleration. It works where the wrist
// travels through a clear cycle (curls, shoulder press, lateral raises, some rows) and cannot work where the wrist is
// still or the cycle is tiny (squats, leg press, static holds, many machines). It reports a confidence with every
// estimate, counting is optional, and manual logging always stays available (§6: "must never prevent manual logging").
//
// Pipeline (50 Hz target — the BMA423 runs 50/100 Hz here):
//   1. gravity removal   — one-pole high-pass per axis (removes the static 1 g and slow wrist tilt)
//   2. dominant axis     — the dynamic acceleration is projected onto its running principal direction, so the detector
//                          sees ONE signed movement signal whatever way the watch sits (a magnitude would double the
//                          frequency and never return to zero while a second axis still moves)
//   3. smoothing         — one-pole low-pass (~3 Hz) removes jitter and bar rattle
//   4. cycle detection   — a rep is one full cycle: the signal rises above +T, falls below −T, and rises above +T again;
//                          T adapts to the recent peak amplitude (never below a floor), each half must last a minimum
//                          time (a knock's filter ringing is far faster than any lift), and consecutive reps are at
//                          least `minPeriodMs` apart (tempo floor)
//   5. plausibility      — reps count only while the cadence is steady (period within a band of the running median);
//                          isolated spikes (bumping the rack, adjusting the watch) do not
//   6. confidence        — from cadence regularity, amplitude consistency and the share of rejected cycles
//
// Learning from corrected sessions (§6.9) is NOT in this version: a correction adjusts nothing automatically; the
// per-exercise thresholds live in `RepParams` and may be tuned from the validation dataset explicitly.
#include <cstdint>
#include <cmath>
#include <vector>
#include <algorithm>

namespace cyw {

struct Accel { float x, y, z; };   // m/s², BMA423 converted by the HAL

struct RepParams {
    float sampleHz = 50.f;
    float highPassHz = 0.3f;        // gravity / slow tilt removal
    float lowPassHz = 3.0f;         // smoothing
    float thresholdFloor = 0.9f;    // m/s² — the smallest half-swing that can be a rep
    float thresholdShare = 0.35f;   // adaptive threshold = share of the recent peak amplitude
    uint32_t minHalfMs = 150;       // each half of the cycle must last at least this (knocks ring in < 100 ms)
    uint32_t minPeriodMs = 700;     // faster than this is not a rep (tempo floor ~0.7 s)
    uint32_t maxPeriodMs = 6000;    // slower than this breaks the set (long pause)
    float periodBand = 0.5f;        // a cycle counts only within ±50 % of the running median period
    uint8_t warmupCycles = 2;       // the first cycles establish the tempo but are counted too once confirmed
};

struct RepEvent { uint32_t tMs; float amplitude; float confidence; };

class RepDetector {
public:
    explicit RepDetector(RepParams p = {}) : p_(p) { reset(); }

    void reset() {
        hp_ = {0, 0, 0}; prevIn_ = {0, 0, 0}; primed_ = false; dir_ = {1, 0, 0}; lp_ = 0.f; peak_ = 0.f;
        state_ = 0; halfStartMs_ = 0; cycleStartMs_ = 0; cycleMax_ = 0; lastRepMs_ = 0;
        periods_.clear(); amplitudes_.clear(); events_.clear(); rejected_ = 0; count_ = 0;
    }

    /// Feed one sample; returns true when a repetition was just confirmed.
    bool feed(const Accel& a, uint32_t tMs) {
        const float dt = 1.f / p_.sampleHz;
        // 1. high-pass per axis (y[n] = α (y[n-1] + x[n] - x[n-1]))
        const float rcH = 1.f / (2.f * float(M_PI) * p_.highPassHz), aH = rcH / (rcH + dt);
        if (!primed_) { prevIn_ = a; primed_ = true; }
        hp_.x = aH * (hp_.x + a.x - prevIn_.x); hp_.y = aH * (hp_.y + a.y - prevIn_.y); hp_.z = aH * (hp_.z + a.z - prevIn_.z);
        prevIn_ = a;
        // 2. running principal direction (sign-aligned EWMA of the dynamic vector), then the signed projection
        const float mag = std::sqrt(hp_.x * hp_.x + hp_.y * hp_.y + hp_.z * hp_.z);
        if (mag > 0.3f) {
            float sgn = (hp_.x * dir_.x + hp_.y * dir_.y + hp_.z * dir_.z) >= 0 ? 1.f : -1.f;
            const float k = 0.02f;
            dir_.x += k * (sgn * hp_.x / mag - dir_.x); dir_.y += k * (sgn * hp_.y / mag - dir_.y); dir_.z += k * (sgn * hp_.z / mag - dir_.z);
            float n = std::sqrt(dir_.x * dir_.x + dir_.y * dir_.y + dir_.z * dir_.z); if (n > 1e-3f) { dir_.x /= n; dir_.y /= n; dir_.z /= n; }
        }
        const float proj = hp_.x * dir_.x + hp_.y * dir_.y + hp_.z * dir_.z;
        // 3. low-pass
        const float rcL = 1.f / (2.f * float(M_PI) * p_.lowPassHz), aL = dt / (rcL + dt);
        lp_ += aL * (proj - lp_);
        // adaptive threshold from the recent peak (decays slowly so a lighter exercise is still seen)
        peak_ = std::max(std::fabs(lp_), peak_ * 0.999f);
        const float T = std::max(p_.thresholdFloor, p_.thresholdShare * peak_);
        // a half-cycle that never completes (the athlete stopped mid-movement, racked the bar) is abandoned
        if (state_ != 0 && tMs - halfStartMs_ > p_.maxPeriodMs) { state_ = 0; }
        // 4. one full cycle: above +T → below −T → above +T, each half ≥ minHalfMs
        switch (state_) {
            case 0: if (lp_ > T) { state_ = 1; halfStartMs_ = tMs; cycleStartMs_ = tMs; cycleMax_ = lp_; } break;
            case 1: cycleMax_ = std::max(cycleMax_, lp_);
                    if (lp_ < -T) { if (tMs - halfStartMs_ < p_.minHalfMs) { state_ = 0; rejected_++; } else { state_ = 2; halfStartMs_ = tMs; } } break;
            case 2: cycleMax_ = std::max(cycleMax_, -lp_);
                    if (lp_ > T) { bool ok = tMs - halfStartMs_ >= p_.minHalfMs; state_ = 1; halfStartMs_ = tMs; uint32_t start = cycleStartMs_; cycleStartMs_ = tMs;
                                   if (!ok) { rejected_++; return false; } return completeCycle(tMs, start); } break;
        }
        return false;
    }

    uint32_t count() const { return count_; }
    const std::vector<RepEvent>& events() const { return events_; }
    uint32_t rejectedCycles() const { return rejected_; }

    /// Confidence of the current count, 0…1: regular tempo, consistent amplitude, few rejected cycles.
    float confidence() const {
        if (count_ == 0) return 0.f;
        float tempo = regularity(periods_), amp = regularity(amplitudes_);
        float rej = float(rejected_) / float(rejected_ + count_);
        float c = 0.5f * tempo + 0.3f * amp + 0.2f * (1.f - rej);
        if (count_ < 3) c *= 0.6f;                        // too little evidence yet
        return std::clamp(c, 0.f, 1.f);
    }

    // Manual corrections (§6.8): the athlete's word is final and is recorded as such.
    void setCountManually(uint32_t n) { count_ = n; manualCorrections_++; }
    void undoLastRep() { if (count_ > 0) { count_--; if (!events_.empty()) events_.pop_back(); } manualCorrections_++; }
    uint32_t manualCorrections() const { return manualCorrections_; }

private:
    bool completeCycle(uint32_t tMs, uint32_t startMs) {
        const uint32_t duration = tMs - startMs;                       // the full cycle this rep took
        uint32_t period = lastRepMs_ ? tMs - lastRepMs_ : duration;
        if (duration < p_.minPeriodMs) { rejected_++; return false; }                 // too fast to be a lift
        if (lastRepMs_ && period > p_.maxPeriodMs) { periods_.clear(); amplitudes_.clear(); period = duration; }   // long pause: a new set starts with its own tempo
        if (period > p_.maxPeriodMs) { rejected_++; lastRepMs_ = tMs; return false; }   // a cycle that spanned a pause is not a rep
        // 5. plausibility against the running median period (once a tempo exists)
        if (periods_.size() >= p_.warmupCycles) {
            float med = median(periods_);
            if (std::fabs(float(period) - med) > p_.periodBand * med) { rejected_++; lastRepMs_ = tMs; return false; }
        }
        periods_.push_back(float(period)); amplitudes_.push_back(cycleMax_);
        if (periods_.size() > 12) periods_.erase(periods_.begin());
        if (amplitudes_.size() > 12) amplitudes_.erase(amplitudes_.begin());
        lastRepMs_ = tMs; count_++;
        events_.push_back({tMs, cycleMax_, confidence()});
        return true;
    }
    static float median(std::vector<float> v) { std::sort(v.begin(), v.end()); return v.empty() ? 0.f : v[v.size() / 2]; }
    static float regularity(const std::vector<float>& v) {
        if (v.size() < 2) return 0.6f;
        float mean = 0; for (float x : v) mean += x; mean /= v.size();
        float var = 0; for (float x : v) var += (x - mean) * (x - mean); var /= v.size();
        float cv = mean > 0 ? std::sqrt(var) / mean : 1.f;          // coefficient of variation
        return std::clamp(1.f - cv * 2.f, 0.f, 1.f);                 // cv 0 → 1.0, cv 0.25 → 0.5, cv ≥ 0.5 → 0
    }

    RepParams p_;
    Accel hp_{}, prevIn_{}, dir_{1, 0, 0}; float lp_ = 0, peak_ = 0; bool primed_ = false;
    int state_ = 0; uint32_t halfStartMs_ = 0, cycleStartMs_ = 0; float cycleMax_ = 0; uint32_t lastRepMs_ = 0;
    std::vector<float> periods_, amplitudes_; std::vector<RepEvent> events_;
    uint32_t rejected_ = 0, count_ = 0, manualCorrections_ = 0;
};

} // namespace cyw
