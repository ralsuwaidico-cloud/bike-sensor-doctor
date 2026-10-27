import Foundation

/// Link 1.3 negotiation for ONE encrypted connection (BLE_CONTRACT.md §4). Pure: the caller feeds INFO, the HELLO_ACK
/// and the clock. The capability gate every Link 1.3 sender asks is `enabled(_:)`:
///  - the board's INFO must carry cap 0x0800 HELLO, else nothing new is ever sent (0.7.3 boards, release candidate behaviour);
///  - the phone sends APP_HELLO once, and uses a feature only when HELLO_ACK's `enabled_caps` has its bit;
///  - no HELLO_ACK within `ackTimeout` → one more HELLO, then the connection stays on Link 1.2.3 behaviour.
struct Link13Session: Equatable {
    enum Phase: Equatable { case unsupported, waitingForAck(attempt: Int), enabled(UInt32), noAnswer }
    private(set) var phase: Phase = .unsupported
    private(set) var helloSentAt: Date?
    var ackTimeout: TimeInterval = 4
    var maxAttempts = 2

    /// INFO arrived on a new connection. Returns true when APP_HELLO must be sent now.
    mutating func connected(info: BCLink.Info, now: Date) -> Bool {
        guard info.hasHello else { phase = .unsupported; helloSentAt = nil; return false }
        phase = .waitingForAck(attempt: 1); helloSentAt = now
        return true
    }
    mutating func linkDown() { phase = .unsupported; helloSentAt = nil }

    /// HELLO_ACK: enabled = INFO caps ∧ app caps as the BOARD computed it, masked again by what this app implements.
    mutating func helloAck(_ a: BCLink.HelloAck) {
        guard case .waitingForAck = phase else { if case .enabled = phase { phase = .enabled(a.enabledCaps & BCLink.appCaps13) }; return }
        phase = .enabled(a.enabledCaps & BCLink.appCaps13)
        helloSentAt = nil
    }
    /// Returns true when APP_HELLO must be sent again (first one unanswered).
    mutating func tick(now: Date) -> Bool {
        guard case .waitingForAck(let n) = phase, let t = helloSentAt, now.timeIntervalSince(t) >= ackTimeout else { return false }
        if n >= maxAttempts { phase = .noAnswer; helloSentAt = nil; return false }
        phase = .waitingForAck(attempt: n + 1); helloSentAt = now
        return true
    }

    var enabledCaps: UInt32 { if case .enabled(let c) = phase { return c }; return 0 }
    func enabled(_ cap: UInt32) -> Bool { enabledCaps & cap == cap && cap != 0 }
    var coach: Bool { enabled(BCLink.Info.capCoach) }
    var rideQueue: Bool { enabled(BCLink.Info.capRideQueue) }
    var storage: Bool { enabled(BCLink.Info.capStorage) }
    var diagAuto: Bool { enabled(BCLink.Info.capDiagAuto) }
    var isWaiting: Bool { if case .waitingForAck = phase { return true }; return false }

    /// Plain words for the BikeComputer pages.
    var summary: String {
        switch phase {
        case .unsupported: return "Link 1.2 (update the BikeComputer for coach mirroring, offline ride import and storage status)"
        case .waitingForAck: return "Link 1.3: waiting for the board"
        case .noAnswer: return "Link 1.3 not confirmed by the board — using Link 1.2 on this connection"
        case .enabled(let c):
            var parts: [String] = []
            if c & BCLink.Info.capCoach != 0 { parts.append("coach") }
            if c & BCLink.Info.capRideQueue != 0 { parts.append("offline rides") }
            if c & BCLink.Info.capStorage != 0 { parts.append("storage") }
            if c & BCLink.Info.capDiagAuto != 0 { parts.append("report retention") }
            return "Link 1.3" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
        }
    }
}
