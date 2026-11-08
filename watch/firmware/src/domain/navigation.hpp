#pragma once
// Cyclift Watch OS — orbital navigation model (owner directive §3F), pure and host-tested:
//   watch face = dashboard · swipe left/right = major panels · swipe up = activities · swipe down = quick settings ·
//   tap = details · long press = contextual actions · hardware buttons = back / confirm / activity shortcut.
// During an activity the critical controls (Pause / Resume / End / Log set) are always on the live screen; a swipe
// never leaves the activity accidentally — it moves between the activity's own views (Cockpit / Navigation /
// Performance, or Exercise / Rest / Summary), and only Back (button) or End leaves it.
#include <cstdint>
#include <vector>
#include <string>

namespace cyw {

enum class Gesture : uint8_t { Tap, LongPress, SwipeLeft, SwipeRight, SwipeUp, SwipeDown, Button1, Button2, Button3 };

enum class Screen : uint8_t {
    Face,            // dashboard watch face (Orbit / Chrono / Pulse)
    Today,           // panel: today's training + next session (swipe left of Face)
    Recovery,        // panel: sleep / recovery / HRV from the phone (swipe left ×2)
    Progress,        // panel: weekly goals and progress (swipe right of Face)
    Notifications,   // panel: notifications and timers (swipe right ×2)
    Activities,      // swipe up: the activity library
    QuickSettings,   // swipe down: brightness, do-not-disturb, display mode, battery, connection
    FaceDetail,      // tap on the face: complication detail
    FaceActions,     // long press on the face: choose face / complications
    RidePrepare, RideCockpit, RideNavigation, RidePerformance, RideReview,
    LiftPrepare, LiftExercise, LiftRest, LiftReview,
    ActivityGeneric, Review
};

inline bool isLiveActivity(Screen s) { return s == Screen::RideCockpit || s == Screen::RideNavigation || s == Screen::RidePerformance || s == Screen::LiftExercise || s == Screen::LiftRest || s == Screen::ActivityGeneric; }

class Navigator {
public:
    Screen current() const { return cur_; }
    bool activityRunning() const { return running_; }

    void startActivity(bool cycling, bool strength) { running_ = true; cur_ = cycling ? Screen::RideCockpit : strength ? Screen::LiftExercise : Screen::ActivityGeneric; stack_.clear(); }
    void endActivity() { running_ = false; cur_ = (cur_ == Screen::LiftExercise || cur_ == Screen::LiftRest) ? Screen::LiftReview : Screen::RideReview; }
    void finishReview() { cur_ = Screen::Face; stack_.clear(); }

    /// Returns true when the gesture changed the screen (so the UI animates); false when it was ignored here and the
    /// screen itself may use it (e.g. tap on a control).
    bool handle(Gesture g) {
        if (running_) return handleLive(g);
        switch (cur_) {
            case Screen::Face:
                switch (g) {
                    case Gesture::SwipeLeft: return go(Screen::Today);
                    case Gesture::SwipeRight: return go(Screen::Progress);
                    case Gesture::SwipeUp: return go(Screen::Activities);
                    case Gesture::SwipeDown: return go(Screen::QuickSettings);
                    case Gesture::Tap: return go(Screen::FaceDetail);
                    case Gesture::LongPress: return go(Screen::FaceActions);
                    case Gesture::Button3: return go(Screen::Activities);      // physical shortcut to activities
                    default: return false;
                }
            case Screen::Today: if (g == Gesture::SwipeLeft) return go(Screen::Recovery); if (g == Gesture::SwipeRight || g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::Recovery: if (g == Gesture::SwipeRight) return go(Screen::Today); if (g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::Progress: if (g == Gesture::SwipeRight) return go(Screen::Notifications); if (g == Gesture::SwipeLeft || g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::Notifications: if (g == Gesture::SwipeLeft) return go(Screen::Progress); if (g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::Activities: if (g == Gesture::SwipeDown || g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::QuickSettings: if (g == Gesture::SwipeUp || g == Gesture::Button1) return go(Screen::Face); return false;
            case Screen::FaceDetail: case Screen::FaceActions: if (g == Gesture::Button1 || g == Gesture::SwipeDown) return go(Screen::Face); return false;
            case Screen::RidePrepare: case Screen::LiftPrepare: if (g == Gesture::Button1) return go(Screen::Activities); return false;
            case Screen::RideReview: case Screen::LiftReview: case Screen::Review: return false;   // Save / Discard are explicit controls
            default: return false;
        }
    }

private:
    bool handleLive(Gesture g) {
        switch (cur_) {
            case Screen::RideCockpit: if (g == Gesture::SwipeLeft) return go(Screen::RideNavigation); if (g == Gesture::SwipeRight) return go(Screen::RidePerformance); return false;
            case Screen::RideNavigation: if (g == Gesture::SwipeRight) return go(Screen::RideCockpit); if (g == Gesture::SwipeLeft) return go(Screen::RidePerformance); return false;
            case Screen::RidePerformance: if (g == Gesture::SwipeLeft) return go(Screen::RideCockpit); if (g == Gesture::SwipeRight) return go(Screen::RideNavigation); return false;
            case Screen::LiftExercise: if (g == Gesture::SwipeLeft) return go(Screen::LiftRest); return false;
            case Screen::LiftRest: if (g == Gesture::SwipeRight) return go(Screen::LiftExercise); return false;
            default: return false;                       // swipes up/down and taps belong to the live screen's controls
        }
    }
    bool go(Screen s) { if (s == cur_) return false; stack_.push_back(cur_); cur_ = s; return true; }
    Screen cur_ = Screen::Face; bool running_ = false; std::vector<Screen> stack_;
};

} // namespace cyw
