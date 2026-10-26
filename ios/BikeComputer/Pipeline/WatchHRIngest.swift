import Foundation

/// One gate for Apple Watch heart rate on the iPhone, whichever channel it came through (the mirrored HealthKit workout
/// session is primary, WatchConnectivity secondary). Pure value type, unit-tested.
///  - de-duplicates by HealthKit sample time: the same sample arriving on both channels counts once;
///  - drops out-of-order samples (older than the last accepted one);
///  - drops readings older than `maxAgeS` (6 s) at arrival and implausible values (outside 25–250 bpm);
///  - never holds a value: `current(now:)` is nil once the last accepted sample is older than `maxAgeS`.
struct WatchHRIngest: Equatable {
    enum Channel: String, Codable, CaseIterable { case mirror, connectivity }
    enum Verdict: String, Equatable { case accepted, duplicate, outOfOrder, tooOld, implausible, future }

    static let maxAgeS: TimeInterval = 6
    /// Watch and phone clocks are both network-synced; allow a little skew before calling a sample "from the future".
    static let maxFutureS: TimeInterval = 2

    private(set) var bpm: Int?
    private(set) var sampleAt: Date?
    private(set) var receivedAt: Date?
    private(set) var lastChannel: Channel?
    private(set) var accepted: [Channel: Int] = [:]
    private(set) var duplicates = 0
    private(set) var dropped = 0          /* too old, out of order, implausible, future */

    @discardableResult
    mutating func offer(bpm b: Int, sampleAt t: Date, now: Date, via ch: Channel) -> Verdict {
        guard (25...250).contains(b) else { dropped += 1; return .implausible }
        if t.timeIntervalSince(now) > Self.maxFutureS { dropped += 1; return .future }
        if now.timeIntervalSince(t) > Self.maxAgeS { dropped += 1; return .tooOld }
        if let last = sampleAt {
            if abs(t.timeIntervalSince(last)) < 0.001 { duplicates += 1; return .duplicate }
            if t < last { dropped += 1; return .outOfOrder }
        }
        bpm = b; sampleAt = t; receivedAt = now; lastChannel = ch
        accepted[ch, default: 0] += 1
        return .accepted
    }

    /// The value to show / forward now, or nil when there is no reading younger than `maxAgeS`.
    func current(now: Date) -> Int? {
        guard let t = sampleAt, now.timeIntervalSince(t) <= Self.maxAgeS else { return nil }
        return bpm
    }
    func isFresh(now: Date) -> Bool { current(now: now) != nil }
    var totalAccepted: Int { accepted.values.reduce(0, +) }
}
