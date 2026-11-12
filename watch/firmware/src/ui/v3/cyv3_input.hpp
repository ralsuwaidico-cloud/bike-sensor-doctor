#pragma once
// Cyclift Watch v3 — physical buttons → model (owner decisions G1–G11, 12 Nov 2026).
// The firmware loop and the computer tests both use this one function, so the tests exercise the exact watch path.
// No Arduino, no LVGL.
//
//   L1 short  = Select (screen's primary action; in a workout: Controls, then a 2nd L1 confirms Pause / Resume)  G2 G7
//   L1 hold 1 s = Quick Settings (outside a workout)            L1 hold 2 s = End request → confirmation        G8
//   L2 short  = Back (on a ride page: two presses within 2.5 s = Lap)   L2 hold 1 s = Home / back to the ride
//   R2 short  = Next (page / row / widget)                      R2 hold 1 s = touch lock on / off               G3 G4
//   L1 + L2 held 10 s = software restart, visible countdown, cancel on early release; in a workout an explicit
//                       warning screen asks first                                                            G5 G6
// The touch lock never blocks these buttons (G4). R2 (GPIO0 / Boot) only gets non-critical actions.
#include "cyv3_keys.hpp"
#include "cyv3_model.hpp"

namespace cyw::v3 {

struct ButtonInput {
    KeyDecoder dec;
    uint32_t events = 0;            // total decoded events (diagnostics)
    KeyEvent last[8]; int lastN = 0;

    /// One loop pass: raw pressed levels in, model updated. Returns true when the model changed in a way the UI must redraw.
    bool sample(Model& m, bool l1, bool l2, bool r2, uint32_t now) {
        lastN = dec.feed(l1, l2, r2, now, last);
        bool changed = false;
        for (int i = 0; i < lastN; i++) { events++; changed |= dispatch(m, last[i], now); }
        uint32_t ring = dec.heldMs(Btn::L1, now);
        uint32_t before = m.endHoldMs;
        m.setEndHold(ring);
        if (m.endHoldMs / 100 != before / 100) changed = true;        // the ring advances in 0.1 s steps
        return changed;
    }
    /// The restart is executed only when no button is held any more (a held R2 = GPIO0 at reset would enter download mode).
    bool restartReady(const Model& m) const { return m.restartRequested && !dec.down(Btn::L1) && !dec.down(Btn::L2) && !dec.down(Btn::R2); }

    static bool dispatch(Model& m, const KeyEvent& e, uint32_t now) {
        switch (e.ev) {
            case KeyEv::Short:
                if (e.btn == Btn::L1) m.pressL1(now); else if (e.btn == Btn::L2) m.pressL2(now); else m.pressR2(now);
                return true;
            case KeyEv::Hold:
                if (e.btn == Btn::L1) m.holdL1(now); else if (e.btn == Btn::L2) m.holdL2(now); else m.holdR2(now);
                return true;
            case KeyEv::Hold2: if (e.btn == Btn::L1) m.holdL1Long(now); return true;
            case KeyEv::ChordStart: m.chordTick(e.heldMs); return true;
            case KeyEv::ChordTick: { uint32_t b = m.restartMs; m.chordTick(e.heldMs); return m.restartMs / 1000 != b / 1000 || (b == 0) != (m.restartMs == 0); }
            case KeyEv::ChordCancel: m.chordCancel(); return true;
            case KeyEv::ChordFire: m.chordFire(now); return true;
            default: return false;
        }
    }
};

}  // namespace cyw::v3
