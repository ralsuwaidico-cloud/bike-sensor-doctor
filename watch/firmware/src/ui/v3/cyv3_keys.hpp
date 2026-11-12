#pragma once
// Cyclift Watch v3 — physical button decoder (owner decisions G1–G11, 12 Nov 2026). No Arduino, no LVGL: host-tested.
//
// Three readable buttons (BUTTON_HARDWARE_AUDIT.md):
//   L1 = left upper, GPIO35 · L2 = left lower, GPIO34 · R2 = right lower, GPIO0 (Boot: never used for workout actions).
//   R1 (right upper) is the chip's Reset line: firmware cannot see it.
// Feed the raw "pressed" level of each button every loop pass; events come out exactly once, in time order.
//
// Rules (deterministic, all tested in test/v3/test_keys.cpp):
//   • Debounce 30 ms: a level must hold 30 ms before it counts. Bounces shorter than that are invisible.
//   • Short press = released before 1 s; it fires ON RELEASE (so a hold or a combination never fires a short press).
//   • Hold = fires once at 1 s while still held (L1Hold, L2Hold, R2Hold). L1 also fires L1Hold2 at 2 s (End request).
//   • Combination L1 + L2 (software restart, G5/G6): both buttons down, the second within 1 s of the first, and neither
//     has fired a hold yet. Once both have been down together for 150 ms the chord takes over: every pending single-button
//     event of L1 and L2 is cancelled (ChordStart). ChordTick reports the held time for the countdown; releasing either
//     button before 10 s → ChordCancel; 10 s of continuous hold → ChordFire. After a chord ends, nothing fires until both
//     buttons are up again. R2 is independent of the chord.
#include <cstdint>

namespace cyw::v3 {

enum class Btn : uint8_t { L1, L2, R2 };
enum class KeyEv : uint8_t { None, Short, Hold, Hold2, ChordStart, ChordTick, ChordCancel, ChordFire };
struct KeyEvent { KeyEv ev = KeyEv::None; Btn btn = Btn::L1; uint32_t heldMs = 0; };

class KeyDecoder {
public:
    static constexpr uint32_t DEBOUNCE_MS = 30, HOLD_MS = 1000, HOLD2_MS = 2000, CHORD_PAIR_MS = 1000, CHORD_ARM_MS = 150,
                              CHORD_MS = 10000;

    /// Feeds one sample. `out` receives up to 8 events; returns how many. Call every loop pass (≈ 10 ms on the watch).
    int feed(bool l1, bool l2, bool r2, uint32_t now, KeyEvent* out) {
        int n = 0;
        bool raw[3] = {l1, l2, r2};
        bool was[3] = {k_[0].stable, k_[1].stable, k_[2].stable};
        for (int i = 0; i < 3; i++) debounce(k_[i], raw[i], now);
        // edges of the debounced levels
        for (int i = 0; i < 3; i++) {
            K& k = k_[i];
            if (k.stable && !was[i]) { k.downMs = now; k.holdFired = k.hold2Fired = false; k.consumed = chordLock_ && i < 2; }
        }
        // ---- the L1 + L2 chord
        bool both = k_[0].stable && k_[1].stable;
        if (!chord_ && !chordLock_ && both) {
            uint32_t first = k_[0].downMs < k_[1].downMs ? k_[0].downMs : k_[1].downMs, second = k_[0].downMs < k_[1].downMs ? k_[1].downMs : k_[0].downMs;
            bool pairable = second - first <= CHORD_PAIR_MS && !k_[0].holdFired && !k_[1].holdFired;
            if (pairable && now - second >= CHORD_ARM_MS) {
                chord_ = true; chordStart_ = second; k_[0].consumed = k_[1].consumed = true;
                out[n++] = {KeyEv::ChordStart, Btn::L1, now - second};
            }
        }
        if (chord_) {
            if (!both) { chord_ = false; chordLock_ = true; out[n++] = {KeyEv::ChordCancel, Btn::L1, now - chordStart_}; }
            else if (now - chordStart_ >= CHORD_MS) { chord_ = false; chordLock_ = true; out[n++] = {KeyEv::ChordFire, Btn::L1, now - chordStart_}; }
            else out[n++] = {KeyEv::ChordTick, Btn::L1, now - chordStart_};
        }
        if (chordLock_ && !k_[0].stable && !k_[1].stable) chordLock_ = false;
        // ---- single buttons
        for (int i = 0; i < 3; i++) {
            K& k = k_[i]; Btn b = Btn(i);
            if (k.consumed || (i < 2 && (chord_ || chordLock_))) {           // part of a chord: silent until released
                if (!k.stable) k.consumed = false;
                continue;
            }
            // a possible chord partner is down: hold back L1 / L2 holds until the pairing window has passed
            bool partnerWaiting = i < 2 && k_[1 - i].stable && !k_[1 - i].holdFired;
            if (k.stable) {
                uint32_t held = now - k.downMs;
                if (!k.holdFired && held >= HOLD_MS && !partnerWaiting) { k.holdFired = true; out[n++] = {KeyEv::Hold, b, held}; }
                if (b == Btn::L1 && k.holdFired && !k.hold2Fired && held >= HOLD2_MS) { k.hold2Fired = true; out[n++] = {KeyEv::Hold2, b, held}; }
            } else if (was[i]) {                                               // released (debounced)
                uint32_t held = now - k.downMs;
                if (!k.holdFired && held < HOLD_MS && !partnerHeldTogether(i)) out[n++] = {KeyEv::Short, b, held};
            }
        }
        for (int i = 0; i < 3; i++) if (!k_[i].stable) k_[i].pairedWith = false;
        if (k_[0].stable && k_[1].stable) k_[0].pairedWith = k_[1].pairedWith = true;
        return n;
    }
    /// Held time of a button right now (0 when up, or when it belongs to a chord). Used for the End-request ring.
    uint32_t heldMs(Btn b, uint32_t now) const { const K& k = k_[int(b)]; return (k.stable && !k.consumed && !chord_ && !chordLock_) ? now - k.downMs : 0; }
    bool chordActive() const { return chord_; }
    bool down(Btn b) const { return k_[int(b)].stable; }

private:
    struct K { bool stable = false, raw = false, holdFired = false, hold2Fired = false, consumed = false, pairedWith = false; uint32_t rawSince = 0, downMs = 0; };
    K k_[3];
    bool chord_ = false, chordLock_ = false; uint32_t chordStart_ = 0;
    static void debounce(K& k, bool raw, uint32_t now) {
        if (raw != k.raw) { k.raw = raw; k.rawSince = now; }
        if (raw != k.stable && now - k.rawSince >= DEBOUNCE_MS) k.stable = raw;
    }
    /// L1 and L2 were down together (but too briefly to become a chord): no short press for either — ambiguous input.
    bool partnerHeldTogether(int i) const { return i < 2 && k_[i].pairedWith; }
};

}  // namespace cyw::v3
