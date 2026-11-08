#pragma once
// Cyclift Watch OS — physical buttons (owner requirement 8 Nov 15:14, §2–3).
//
// HARDWARE FACTS (manufacturer schematic + pin diagram, V1.1): four push-buttons exist —
//   • RESET  → EN pin of the module. NOT readable by firmware; it resets the chip. Preserved as is.
//   • BOOT   → GPIO0 (strapping pin). Held low during reset it enters the ROM bootloader (firmware recovery) — that
//              behaviour is preserved and must stay. After boot it is readable as an ordinary input, but it sits next to
//              Reset on the right side, so a fumbled press during a hard reset re-flashes nothing yet can hold the chip
//              in the bootloader: we use it only for a NON-CRITICAL shortcut (long press = quick settings) and never for
//              anything a workout depends on.
//   • KEY1   → GPIO35 (upper left)   • KEY2 → GPIO34 (lower left)  — input-only pins (no internal pull-up/down; the
//              board provides the pull-up per the schematic); fully programmable. On V1.0 the two are swapped.
// So there are TWO independently programmable buttons plus one shortcut key; we do not claim four.
//
// Actions are context-sensitive and documented in docs/BUTTONS.md. Touch always offers Pause / Resume / End too, so a
// broken button or a broken touch layer never traps the athlete. End is never a single short press.
#include <cstdint>
#include <string>
#include <vector>

namespace cyw {

enum class Key : uint8_t { Key1 /* GPIO35 upper left */, Key2 /* GPIO34 lower left */, Boot /* GPIO0 right */ };
enum class Press : uint8_t { Short, Long };
enum class Mode : uint8_t { Face, Panel, Menu, Live_Ride, Live_Lift, Live_Rest, Review };
enum class Action : uint8_t { None, Back, Home, OpenActivities, OpenQuickSettings, Confirm, LogSet, Undo, OpenCorrections, Lap, TogglePause, EndRequest, SkipRest, Save, Discard, Wake };

/// Debounce + short/long press classifier for one key. Feed raw level samples at any rate; events come out once.
class KeyDecoder {
public:
    explicit KeyDecoder(uint32_t debounceMs = 30, uint32_t longMs = 700, uint32_t repeatGuardMs = 250) : db_(debounceMs), lp_(longMs), guard_(repeatGuardMs) {}
    struct Event { bool fired; Press press; };
    /// pressed = true while the key is held (active-low pins already inverted by the HAL).
    Event feed(bool pressed, uint32_t nowMs) {
        if (pressed != rawLevel_) { rawLevel_ = pressed; rawSinceMs_ = nowMs; }
        if (nowMs - rawSinceMs_ < db_) return {false, Press::Short};               // still bouncing
        if (pressed != stable_) {
            stable_ = pressed;
            if (pressed) { downMs_ = nowMs; longFired_ = false; }
            else if (!longFired_ && nowMs - downMs_ >= db_ && (!everFired_ || nowMs - lastFireMs_ >= guard_)) { lastFireMs_ = nowMs; everFired_ = true; return {true, Press::Short}; }
        } else if (pressed && !longFired_ && nowMs - downMs_ >= lp_) { longFired_ = true; lastFireMs_ = nowMs; everFired_ = true; return {true, Press::Long}; }
        return {false, Press::Short};
    }
    bool held() const { return stable_; }
private:
    uint32_t db_, lp_, guard_; bool rawLevel_ = false, stable_ = false, longFired_ = false, everFired_ = false; uint32_t rawSinceMs_ = 0, downMs_ = 0, lastFireMs_ = 0;
};

/// Context map: what each key does where. Accidental termination is impossible: End is only a LONG press of Key1 during
/// a live activity and it only *requests* End (the UI confirms); a short press pauses/resumes or logs a set.
inline Action actionFor(Mode mode, Key key, Press press, bool screenOff, bool phoneLinked) {
    (void)phoneLinked;                                   // buttons behave the same when the phone is gone (§3)
    if (screenOff) return Action::Wake;                  // any key wakes the display first; the press is consumed
    switch (mode) {
        case Mode::Face:
            if (key == Key::Key1) return press == Press::Short ? Action::OpenActivities : Action::OpenQuickSettings;
            if (key == Key::Key2) return press == Press::Short ? Action::OpenActivities : Action::OpenQuickSettings;
            if (key == Key::Boot) return press == Press::Long ? Action::OpenQuickSettings : Action::None;
            break;
        case Mode::Panel: case Mode::Menu:
            if (key == Key::Key1) return press == Press::Short ? Action::Back : Action::Home;
            if (key == Key::Key2) return press == Press::Short ? Action::Confirm : Action::Home;
            if (key == Key::Boot) return press == Press::Long ? Action::Home : Action::None;
            break;
        case Mode::Live_Ride:
            if (key == Key::Key1) return press == Press::Short ? Action::TogglePause : Action::EndRequest;
            if (key == Key::Key2) return press == Press::Short ? Action::Lap : Action::OpenQuickSettings;
            break;
        case Mode::Live_Lift:
            if (key == Key::Key1) return press == Press::Short ? Action::TogglePause : Action::EndRequest;
            if (key == Key::Key2) return press == Press::Short ? Action::LogSet : Action::OpenCorrections;
            break;
        case Mode::Live_Rest:
            if (key == Key::Key1) return press == Press::Short ? Action::TogglePause : Action::EndRequest;
            if (key == Key::Key2) return press == Press::Short ? Action::SkipRest : Action::OpenCorrections;
            break;
        case Mode::Review:
            if (key == Key::Key1) return press == Press::Short ? Action::Back : Action::Discard;    // Discard asks to confirm
            if (key == Key::Key2) return press == Press::Short ? Action::Save : Action::None;
            break;
    }
    return Action::None;
}

/// Haptic feedback per action class (§3 "clear haptic feedback").
inline uint16_t hapticMs(Action a) {
    switch (a) { case Action::None: return 0; case Action::Wake: return 0; case Action::EndRequest: case Action::Discard: return 60; case Action::LogSet: case Action::Lap: case Action::Save: return 40; default: return 15; }
}

} // namespace cyw
