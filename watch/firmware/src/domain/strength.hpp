#pragma once
// Cyclift Watch OS — strength session on the wrist (owner directive §7): exercise order, sets, targets, actual reps,
// weight, rest timer, supersets, completed/remaining, manual logging first, optional auto-count. Changes become
// WatchEvents (sync.hpp) so the iPhone's approved plan is updated through the same event path, never overwritten.
#include <cstdint>
#include <string>
#include <vector>
#include <optional>

namespace cyw {

struct PlannedSet { uint8_t targetReps; float weightKg; bool bodyweight; };
struct PlannedExercise {
    std::string id, name;          // the iPhone's exercise ids / names (plan identity, §12)
    std::vector<PlannedSet> sets;
    uint16_t restS = 90;
    char superset = 0;             // 'A', 'B' … groups alternate; 0 = straight sets
};
struct LoggedSet { uint8_t exercise, set; uint8_t reps; float weightKg; bool autoCounted; bool corrected; uint32_t tMs; };

class StrengthSession {
public:
    explicit StrengthSession(std::vector<PlannedExercise> plan) : plan_(std::move(plan)) {}

    const PlannedExercise* current() const { return cur_ < plan_.size() ? &plan_[cur_] : nullptr; }
    uint8_t currentExercise() const { return uint8_t(cur_); }
    uint8_t currentSet() const { return uint8_t(set_); }           // 0-based
    std::optional<PlannedSet> currentTarget() const { auto e = current(); if (!e || set_ >= e->sets.size()) return std::nullopt; return e->sets[set_]; }

    /// Superset order (§7): A1 set1 → B1 set1 → A1 set2 → … ; straight sets run all sets of one exercise first.
    const PlannedExercise* next() const {
        if (cur_ >= plan_.size()) return nullptr;
        auto n = nextIndex(); return n < plan_.size() ? &plan_[n] : nullptr;
    }

    /// Log the current set (manual or from the rep counter). Returns the logged set; the caller emits the WatchEvent.
    LoggedSet logSet(uint8_t reps, std::optional<float> weightKg, bool autoCounted, uint32_t nowMs) {
        auto t = currentTarget();
        LoggedSet s{uint8_t(cur_), uint8_t(set_), reps, weightKg.value_or(t ? t->weightKg : 0.f), autoCounted, false, nowMs};
        log_.push_back(s);
        restEndsMs_ = nowMs + (current() ? current()->restS : 60) * 1000u;
        advance();
        return s;
    }
    /// Correct the last logged set (§6.8 / §7): the athlete's correction replaces the value and is marked.
    bool correctLast(uint8_t reps, std::optional<float> weightKg) {
        if (log_.empty()) return false;
        log_.back().reps = reps; if (weightKg) log_.back().weightKg = *weightKg; log_.back().corrected = true; return true;
    }
    /// Undo the last set entirely and step back to it.
    bool undoLast() {
        if (log_.empty()) return false;
        auto s = log_.back(); log_.pop_back(); cur_ = s.exercise; set_ = s.set; restEndsMs_ = 0; return true;
    }
    void adjustWeight(float kg) { if (auto e = current(); e && set_ < e->sets.size()) plan_[cur_].sets[set_].weightKg = kg; }
    void skipRest() { restEndsMs_ = 0; }
    uint32_t restRemainingS(uint32_t nowMs) const { return restEndsMs_ > nowMs ? (restEndsMs_ - nowMs + 999) / 1000 : 0; }
    bool resting(uint32_t nowMs) const { return restEndsMs_ > nowMs; }

    size_t completedSets() const { return log_.size(); }
    size_t totalSets() const { size_t n = 0; for (auto& e : plan_) n += e.sets.size(); return n; }
    bool finished() const { return cur_ >= plan_.size(); }
    const std::vector<LoggedSet>& log() const { return log_; }

private:
    size_t nextIndex() const {
        auto& e = plan_[cur_];
        if (e.superset) { for (size_t i = cur_ + 1; i < plan_.size(); i++) if (plan_[i].superset == e.superset && loggedSets(i) < plan_[i].sets.size()) return i;
                          for (size_t i = 0; i < cur_; i++) if (plan_[i].superset == e.superset && loggedSets(i) < plan_[i].sets.size()) return i; }
        if (set_ + 1 < e.sets.size()) return cur_;
        for (size_t i = cur_ + 1; i < plan_.size(); i++) if (loggedSets(i) < plan_[i].sets.size()) return i;
        return plan_.size();
    }
    size_t loggedSets(size_t ex) const { size_t n = 0; for (auto& s : log_) if (s.exercise == ex) n++; return n; }
    void advance() {
        size_t n = nextIndex();
        if (n >= plan_.size()) { cur_ = plan_.size(); return; }
        cur_ = n; set_ = loggedSets(n);
    }
    std::vector<PlannedExercise> plan_; std::vector<LoggedSet> log_;
    size_t cur_ = 0, set_ = 0; uint32_t restEndsMs_ = 0;
};

} // namespace cyw
