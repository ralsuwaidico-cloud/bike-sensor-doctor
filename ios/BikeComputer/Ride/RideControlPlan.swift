import Foundation

/// Checkpoint F (owner decision 2, 7 Nov 2026; RA-20): the ride controls follow one rule everywhere —
/// Pause → End → Review. While a ride is RUNNING the only controls are Lap and Pause; End appears only once the ride
/// is PAUSED, next to Resume. Ending opens the review (the result sheet), where Save and Discard live; Discard asks
/// again. The rule is pure so the unit tests can cover every recorder state and owner without a simulator.
enum RideControlPlan: Equatable {
    enum Button: Equatable { case lap, pause, resume, end }
    /// Where End sends the ride: the recorder in charge, or the phone's own copy when that recorder cannot be reached.
    enum EndRoute: Equatable { case phone, board, phoneCopyBoardUnreachable }
    case notRecording
    case running          // Lap · Pause
    case paused(EndRoute) // Resume · End — ALWAYS (owner 7 Nov: a lost device never traps the rider)

    static func make(recording: Bool, paused: Bool, boardOwned: Bool, boardLinkLost: Bool) -> RideControlPlan {
        guard recording else { return .notRecording }
        if !paused { return .running }
        return .paused(boardOwned ? (boardLinkLost ? .phoneCopyBoardUnreachable : .board) : .phone)
    }
    var buttons: [Button] {
        switch self {
        case .notRecording: return []
        case .running: return [.lap, .pause]
        case .paused: return [.resume, .end]
        }
    }
    var endRoute: EndRoute? { if case .paused(let r) = self { return r }; return nil }
    /// Status line shown with the controls when the recorder cannot be reached (sync is reported, never blocking).
    var syncNotice: String? {
        if case .paused(.phoneCopyBoardUnreachable) = self { return "BikeComputer not reachable: End saves the phone's copy; the board keeps its own and is checked for duplicates when it returns." }
        return nil
    }
    /// True when ending must go through the confirmation sheet first (always, by design).
    var endConfirms: Bool { true }
}
