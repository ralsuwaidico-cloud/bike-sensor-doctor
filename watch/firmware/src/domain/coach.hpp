#pragma once
// Cyclift Watch OS — coaching message protocol and selection (owner directive §10).
// The iPhone (rule-based coach today, no paid AI provider) sends structured messages; the watch shows ONE primary
// actionable instruction at a time, chosen by priority, then safety, then recency, and drops expired ones. Offline, a
// small set of validated local rules (`LocalRules`) produces the same message shape — never presented as "AI".
#include <cstdint>
#include <string>
#include <vector>
#include <algorithm>

namespace cyw {

enum class Priority : uint8_t { Info = 0, Advice = 1, Action = 2, Urgent = 3 };
enum class Context : uint8_t { Any, Cycling, Strength, Recovery, Daily };
enum class Confidence : uint8_t { Low, Medium, High };

struct CoachMessage {
    uint32_t id = 0;                // stable id from the sender (idempotent: the same id replaces, never duplicates)
    std::string instruction;        // "Reduce power. You're above today's endurance target."
    std::string reason;             // shown behind "Why?"
    Priority priority = Priority::Info;
    Context context = Context::Any;
    std::string target;             // "180–216 W", "rest 30 s"
    uint32_t expiresAtMs = 0;       // 0 = until replaced
    bool requiresAction = false;    // the athlete must do something (confirm, rest, slow down)
    Confidence confidence = Confidence::Medium;
    bool safety = false;            // sensor lost, pain reported, stop advice
    bool local = false;             // produced by the watch's offline rules (shown as "watch rule", never "AI")
    uint32_t receivedMs = 0;

    /// Wrist contract (round-screen rule): the live cue is at most WRIST_CHARS characters so it always fits two lines at
    /// 13 px inside the circle; anything longer belongs in `reason` (behind Why?). The sender is expected to comply; the
    /// watch enforces it at a word boundary and never cuts a word in half.
    static constexpr size_t WRIST_CHARS = 44;
    std::string wristInstruction() const {
        if (instruction.size() <= WRIST_CHARS) return instruction;
        size_t cut = instruction.rfind(' ', WRIST_CHARS - 1);
        if (cut == std::string::npos || cut < WRIST_CHARS / 2) cut = WRIST_CHARS - 1;
        std::string t = instruction.substr(0, cut); while (!t.empty() && (t.back() == ' ' || t.back() == ',' || t.back() == '-')) t.pop_back();
        return t + "…";
    }
};

class CoachInbox {
public:
    /// Insert or replace by id. Returns true when the primary message changed.
    bool receive(CoachMessage m, uint32_t nowMs) {
        m.receivedMs = nowMs;
        auto before = primary(nowMs, m.context == Context::Any ? Context::Any : m.context);
        uint32_t beforeId = before ? before->id : 0;
        auto it = std::find_if(msgs_.begin(), msgs_.end(), [&](const CoachMessage& x) { return x.id == m.id; });
        if (it != msgs_.end()) *it = m; else msgs_.push_back(m);
        auto after = primary(nowMs, m.context == Context::Any ? Context::Any : m.context);
        return (after ? after->id : 0) != beforeId;
    }
    void dismiss(uint32_t id) { msgs_.erase(std::remove_if(msgs_.begin(), msgs_.end(), [&](const CoachMessage& x) { return x.id == id; }), msgs_.end()); }
    void purgeExpired(uint32_t nowMs) { msgs_.erase(std::remove_if(msgs_.begin(), msgs_.end(), [&](const CoachMessage& x) { return x.expiresAtMs && nowMs >= x.expiresAtMs; }), msgs_.end()); }

    /// The one message to show for the current context (Any matches everything): highest priority, then safety first,
    /// then the most recent. Expired messages are never returned.
    const CoachMessage* primary(uint32_t nowMs, Context ctx) const {
        const CoachMessage* best = nullptr;
        for (auto& m : msgs_) {
            if (m.expiresAtMs && nowMs >= m.expiresAtMs) continue;
            if (ctx != Context::Any && m.context != Context::Any && m.context != ctx) continue;
            if (!best || rank(m) > rank(*best) || (rank(m) == rank(*best) && m.receivedMs > best->receivedMs)) best = &m;
        }
        return best;
    }
    /// Urgent cues vibrate (§10 haptics); the pattern is decided by the HAL from this.
    static bool wantsHaptic(const CoachMessage& m) { return m.priority == Priority::Urgent || m.safety; }
    size_t size() const { return msgs_.size(); }

private:
    static int rank(const CoachMessage& m) { return int(m.priority) * 2 + (m.safety ? 1 : 0); }
    std::vector<CoachMessage> msgs_;
};

/// Offline rules — a deliberately small, validated set. Each rule is a plain statement of measured fact + an action.
struct LocalRules {
    /// Heart-rate or power source lost during an activity.
    static CoachMessage sensorLost(const char* sensor, uint32_t nowMs) {
        CoachMessage m; m.id = 0xF0000001; m.local = true; m.safety = true; m.priority = Priority::Urgent; m.requiresAction = false;
        m.instruction = std::string("Your ") + sensor + " sensor disconnected."; m.reason = "No readings for 10 seconds. Recording continues without it."; m.receivedMs = nowMs; return m;
    }
    /// Phone link lost: recording continues locally (§8, §12).
    static CoachMessage phoneLost(uint32_t nowMs) {
        CoachMessage m; m.id = 0xF0000002; m.local = true; m.safety = false; m.priority = Priority::Action; m.context = Context::Any;
        m.instruction = "iPhone disconnected — the watch keeps recording."; m.reason = "GPS, routes and new coaching need the phone; your sets and times are kept here and synced later."; m.receivedMs = nowMs; return m;
    }
    /// Rest timer rule for strength (§7): fixed target rest, no inference.
    static CoachMessage restRemaining(uint32_t remainingS, uint32_t nowMs) {
        CoachMessage m; m.id = 0xF0000003; m.local = true; m.priority = Priority::Advice; m.context = Context::Strength;
        m.instruction = "Rest another " + std::to_string(remainingS) + " seconds before the next set."; m.reason = "Planned rest for this exercise."; m.expiresAtMs = nowMs + remainingS * 1000; m.receivedMs = nowMs; return m;
    }
    /// Next interval countdown for cycling (§10 example).
    static CoachMessage intervalStartsIn(uint32_t seconds, uint32_t nowMs) {
        CoachMessage m; m.id = 0xF0000004; m.local = true; m.priority = Priority::Action; m.context = Context::Cycling;
        m.instruction = "Your next interval starts in " + std::to_string(seconds) + " seconds."; m.reason = "From the planned ride steps cached on the watch."; m.expiresAtMs = nowMs + seconds * 1000; m.receivedMs = nowMs; return m;
    }
};

} // namespace cyw
