import Foundation

// Navigation v1.2 rev 1.1, sheet F4 — what the Train ball shows. PURE (Foundation only, no SwiftUI): the state is
// built from primitive facts about the session that already exists (the store's active strength session, the ride
// recorder), so it can be unit-tested without a screen. CyCradleDock draws it; nothing here starts, pauses or saves.
//
// The ball never moves or changes size. States differ by ring construction and badge in the ordinary text colour —
// never by colour or animation alone (so High Contrast and greyscale read the same shapes).
//
// Wording: the sheet's "Spoken" lines are marked illustrative ("final wording must match supported states"). They are
// used as drawn except "completion pending": the sheet says "awaiting save confirmation", but in the app nothing is
// being saved in that state (every set is logged, Finish has not been confirmed), so it says exactly that.

/// The facts the ball is built from. Every field is a plain value read from the one existing session.
struct CyTrainBallInput: Equatable {
    /// The strength session in progress (Store.activeSession).
    struct Strength: Equatable {
        /// Working seconds, pauses excluded (StrengthSession.elapsedSeconds).
        var elapsed: Int
        var paused: Bool
        /// Every set is logged or skipped; Finish has not been confirmed.
        var allSetsLogged: Bool = false
        /// The last Save of this session failed; the session is still active and unsaved.
        var saveFailed: Bool = false
        /// The app was ended while this session was in progress and it has not been resumed since the relaunch.
        var restored: Bool = false
    }
    /// A ride being recorded. `simulated` = a labelled demonstration that records nothing (Cyclift Lab).
    struct Cycling: Equatable {
        var elapsed: Int
        var paused: Bool
        var simulated: Bool = false
    }
    var panelOpen = false
    var strength: Strength? = nil
    /// A workout was written but reading the file back has not confirmed it yet (sheet 06f X7).
    var saveUnconfirmed = false
    var cycling: Cycling? = nil
}

enum CyTrainBallState: Equatable {
    /// 1 · placeholder mark, no ring, no badge, no timer.
    case idle
    /// 2 · the ball becomes an outline (a change of shape, not of colour).
    case panelOpen
    /// 3 · segmented ring, dot badge, time only.
    case strengthRecording(Int)
    /// 4 · solid ring, dot badge, time only. (Minimising a ride stays blocked by the cycling safety gate; this state
    /// only says that a ride is being recorded while another page is shown.)
    case rideRecording(Int, simulated: Bool)
    /// 5 · ring split in two, pause-bars badge, the time stands still.
    case paused(Int, ride: Bool)
    /// 6 · three-quarter ring, "…" badge, placeholder.
    case completionPending
    /// 7 · dotted ring, "!" badge, placeholder. Never shown as saved.
    case saveUncertain
    /// 8 · paused (split) ring, "↺" badge, time.
    case restored(Int)

    enum Ring: Equatable { case none, segmented, solid, split, threeQuarter, dotted }
    enum Badge: Equatable { case none, dot, pauseBars, ellipsis, exclamation, restore }

    /// One rule, in this order: a ride being recorded; the strength session (failed save, restored, all sets logged,
    /// paused, recording); a save that is not confirmed; the open panel; idle.
    static func make(_ i: CyTrainBallInput) -> CyTrainBallState {
        if let c = i.cycling {
            return c.paused ? .paused(max(0, c.elapsed), ride: true) : .rideRecording(max(0, c.elapsed), simulated: c.simulated)
        }
        if let s = i.strength {
            let t = max(0, s.elapsed)
            if s.saveFailed { return .saveUncertain }
            if s.restored && s.paused { return .restored(t) }
            if s.allSetsLogged { return .completionPending }
            return s.paused ? .paused(t, ride: false) : .strengthRecording(t)
        }
        if i.saveUnconfirmed { return .saveUncertain }
        return i.panelOpen ? .panelOpen : .idle
    }

    var ring: Ring {
        switch self {
        case .idle, .panelOpen: return .none
        case .strengthRecording: return .segmented
        case .rideRecording: return .solid
        case .paused, .restored: return .split
        case .completionPending: return .threeQuarter
        case .saveUncertain: return .dotted
        }
    }
    var badge: Badge {
        switch self {
        case .idle, .panelOpen: return .none
        case .strengthRecording, .rideRecording: return .dot
        case .paused: return .pauseBars
        case .completionPending: return .ellipsis
        case .saveUncertain: return .exclamation
        case .restored: return .restore
        }
    }
    /// The seconds shown in the ball; nil = the placeholder mark is shown instead of a time.
    var elapsed: Int? {
        switch self {
        case .strengthRecording(let s), .restored(let s): return s
        case .rideRecording(let s, _): return s
        case .paused(let s, _): return s
        case .idle, .panelOpen, .completionPending, .saveUncertain: return nil
        }
    }
    /// The text in the ball: "14:06", "59:59", "1h04", "10h12" — or nil.
    var timerText: String? { elapsed.map(Self.clock) }
    /// A session exists that the ball returns to (the ball opens it instead of the panel).
    var hasSession: Bool { self != .idle && self != .panelOpen }

    /// Approved timer rule: under one hour MM:SS; from one hour hours and minutes in the "1h04" style.
    static func clock(_ s: Int) -> String {
        let s = max(0, s)
        return s < 3600 ? String(format: "%02d:%02d", s / 60, s % 60) : String(format: "%dh%02d", s / 3600, (s % 3600) / 60)
    }
    /// "14 minutes elapsed" · "1 minute elapsed" · "less than a minute elapsed" · "1 hour 4 minutes elapsed".
    static func spokenElapsed(_ s: Int) -> String {
        let m = max(0, s) / 60
        if m < 1 { return "less than a minute elapsed" }
        if m < 60 { return "\(m) minute\(m == 1 ? "" : "s") elapsed" }
        let h = m / 60, r = m % 60
        let hours = "\(h) hour\(h == 1 ? "" : "s")"
        return r == 0 ? "\(hours) elapsed" : "\(hours) \(r) minute\(r == 1 ? "" : "s") elapsed"
    }
    /// The accessible name (sheet F4, "Spoken"). The name carries the state; the timer text is the value.
    var spoken: String {
        switch self {
        case .idle: return "Train, no active session"
        case .panelOpen: return "Train, panel open"
        case .strengthRecording(let s): return "Strength workout recording, \(Self.spokenElapsed(s))"
        case .rideRecording(let s, let simulated):
            return simulated ? "Demonstration ride, nothing is recorded, \(Self.spokenElapsed(s))" : "Ride recording, \(Self.spokenElapsed(s))"
        case .paused(let s, let ride): return "\(ride ? "Ride" : "Workout") paused, \(Self.spokenElapsed(s))"
        case .completionPending: return "All sets logged, workout not saved yet"
        case .saveUncertain: return "Workout not confirmed saved"
        case .restored(let s): return "Workout restored, paused, \(Self.spokenElapsed(s))"
        }
    }
    var hint: String {
        switch self {
        case .idle: return "Opens training"
        case .panelOpen: return "Closes the panel"
        case .rideRecording, .paused(_, ride: true): return "Opens the ride"
        case .saveUncertain: return "Opens the workout to check or save it again"
        default: return "Opens the workout"
        }
    }
}
