import Foundation

/// Checkpoint F (owner decision 2, 7 Nov 2026; RA-20): the ride controls follow one rule everywhere —
/// Pause → End → Review. While a ride is RUNNING the only controls are Lap and Pause; End appears only once the ride
/// is PAUSED, next to Resume. Ending opens the review (the result sheet), where Save and Discard live; Discard asks
/// again. The rule is pure so the unit tests can cover every recorder state and owner without a simulator.
enum RideControlPlan: Equatable {
    enum Button: Equatable { case lap, pause, resume, end, endDisabled }
    case notRecording
    case running          // Lap · Pause
    case paused(endEnabled: Bool)   // Resume · End (End greyed while the board recorder is out of reach)

    static func make(recording: Bool, paused: Bool, boardOwned: Bool, boardLinkLost: Bool) -> RideControlPlan {
        guard recording else { return .notRecording }
        if !paused { return .running }
        return .paused(endEnabled: !(boardOwned && boardLinkLost))
    }
    var buttons: [Button] {
        switch self {
        case .notRecording: return []
        case .running: return [.lap, .pause]
        case .paused(let e): return [.resume, e ? .end : .endDisabled]
        }
    }
    /// True when ending must go through the confirmation sheet first (always, by design).
    var endConfirms: Bool { true }
}
