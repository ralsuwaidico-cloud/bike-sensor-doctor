import Foundation

// Training Hub v1.4 — cycling recorder: what the screen shows, as plain values (Foundation only, tested on Linux).
//
// The screen draws a `CyclingReadout`. Where the readout comes from is a separate matter:
//   • Cyclift Lab: `CyclingDemoScript` — a fixed, deterministic script. SIMULATED. No sensor, no GPS, nothing recorded.
//   • Redesigned main app: `CyclingLiveV14` (Redesign/CyclingLiveV14.swift) builds the same readout from the existing
//     ride recorder and sensor hub, using the pure rules in `CyclingSensorMap` below.
//
// Sensor truth (v1.4 correction A): a zero is shown only when it was measured. Everything else is "—" with its reason,
// or the last value dimmed with its age. A pause never turns into a zero.

/// One sensor value and how true it is right now.
enum SensorTruth: Equatable {
    case measured(Int)                  // includes a real, measured zero
    case stale(last: Int, ageSeconds: Int)
    case searching                      // a sensor is set up and its link is coming up, or is up with no reading yet
    case disconnected                   // the link dropped: "—" and the reason; nothing recorded for these seconds
    case unavailable                    // no such sensor for this ride

    /// The big figure: a number, or "—" when there is none to show.
    var figure: String {
        switch self {
        case .measured(let v): return "\(v)"
        case .stale(let v, _): return "\(v)"
        case .searching, .disconnected, .unavailable: return "—"
        }
    }
    var dimmed: Bool { if case .measured = self { return false }; return true }
    var recorded: Bool { if case .measured = self { return true }; return false }
    /// The few words that go with a value that is not a live measurement; nil for a live one.
    var reason: String? {
        switch self {
        case .measured: return nil
        case .stale(_, let age): return "\(age) s ago"
        case .searching: return "Searching"
        case .disconnected: return "No signal"
        case .unavailable: return "Not available"
        }
    }
}

/// `ready` = the screen is open and nothing is being recorded yet (main app, before Start).
enum CyclingPhase: String { case ready, recording, paused, ended }

/// How far a measured value may be trusted (the sensor hub's quality, without its "stale", which is a `SensorTruth`).
enum CyclingQuality: String { case good, unverified, estimated }

/// A box under the figures: a sensor warning, the pause statement, or a plain statement about the recording.
struct CyclingNotice: Equatable {
    enum Kind: String { case warning, paused, info }
    var kind: Kind
    var text: String
}

/// The line that names where the figures come from.
struct CyclingSourceLine: Equatable {
    enum State: String { case live, none, simulated }
    var state: State
    var text: String
}

struct CyclingMapTile: Equatable { var label: String; var value: String }

struct CyclingReadout: Equatable {
    var title: String
    var phase: CyclingPhase
    var elapsedSeconds: Int
    var movingSeconds: Int
    var power: SensorTruth
    var heartRate: SensorTruth
    var cadence: SensorTruth
    var speedKmh: Double?
    var distanceKm: Double
    var targetLow: Int?
    var targetHigh: Int?
    var laps: Int

    // — additions for the Focus / Map interface; every one has a default, so a plain readout reads as before —
    /// The figures are invented (Cyclift Lab's demonstration). The source line says so.
    var simulated = false
    var imperial = false
    /// false = the recorder has no moving time, so none is shown (never a copy of elapsed).
    var movingKnown = true
    /// Seconds spent in the current pause; nil = not known, so not shown.
    var pausedSeconds: Int? = nil
    /// Seconds left in the current interval; nil = no interval clock available, so not shown.
    var intervalRemainingSeconds: Int? = nil
    /// The averaging window of the power figure; nil = the figure is the latest reading, and the label does not claim a window.
    var powerAverageSeconds: Int? = 3
    var powerQuality: CyclingQuality = .good
    /// false = power is shown but the recorder in charge does not store it (a phone-recorded ride).
    var powerStored = true
    var speedEstimated = false
    /// Why there is no speed ("waiting for GPS", "GPS lost", …); shown beside the "—".
    var speedReason: String? = nil
    /// false = no distance exists yet (nothing is being recorded): "—", never 0.0.
    var distanceKnown = true
    /// Where the live figures come from right now, already in display order ("Power meter", "Apple Watch", "Phone GPS").
    var sourceNames: [String] = []
    /// Statements from the recorder (link lost, a ride kept as a recording only, values shown but not stored).
    var recorderNotes: [String] = []

    /// Above the big clock.
    var elapsedLabel: String { switch phase { case .paused: return "PAUSED AT"; case .ready: return "NOT RECORDING"; case .ended: return "ENDED AT"; case .recording: return "ELAPSED" } }
    /// Under the big clock: "Moving 24:10 · lap 1 · interval −4:24"; paused: "Moving 30:22 · lap 1 · paused 0:46".
    var timeLine: String {
        if phase == .ready { return "The clock starts with the ride" }
        var parts: [String] = []
        if movingKnown { parts.append("Moving \(Self.clock(movingSeconds))") }
        parts.append("lap \(laps + 1)")
        if phase == .paused { if let p = pausedSeconds { parts.append("paused \(Self.short(p))") } }
        else if let i = intervalRemainingSeconds { parts.append("interval −\(Self.short(i))") }
        return parts.joined(separator: " · ")
    }
    /// Under the title: what the session is doing, in words.
    var stateLine: String {
        switch phase {
        case .ready: return "Cycling · not recording"
        case .recording: return "Cycling"
        case .paused: return "Cycling · paused"
        case .ended: return "Cycling · ended"
        }
    }

    /// Under the power figure: "In range", "Coasting", "Last reading 6 s ago", "No signal", "No power meter".
    var powerLine: String {
        switch power {
        case .measured(let w):
            if phase == .paused { return "Measured now · not recorded" }
            if phase == .ready { return "Measured now · nothing is being recorded" }
            if w == 0 { return "Coasting" }
            if powerQuality == .unverified { return "Meter not verified" }
            guard let lo = targetLow, let hi = targetHigh else { return "Measured" }
            return w < lo ? "Below target" : w > hi ? "Above target" : "In range"
        case .stale(_, let age): return "Last reading \(age) s ago"
        case .searching: return "Searching for the power meter"
        case .disconnected: return "No signal"
        case .unavailable: return "No power meter"
        }
    }
    var powerLabel: String {
        switch power {
        case .measured:
            if phase == .paused || phase == .ready { return "POWER · LIVE" }
            if powerQuality == .unverified { return "POWER · UNVERIFIED" }
            if powerQuality == .estimated { return "POWER · ESTIMATED" }
            if let s = powerAverageSeconds { return "POWER · \(s) S" }
            return "POWER"
        case .stale: return "POWER · NO UPDATE"
        case .searching: return "POWER · SEARCHING"
        case .disconnected, .unavailable: return "POWER"
        }
    }
    var targetText: String? { if let lo = targetLow, let hi = targetHigh { return "Target \(lo)–\(hi) W" }; return nil }
    var heartRateLabel: String { Self.smallLabel("HEART RATE", heartRate, liveTag: false) }
    /// Sheet 05b C10: while paused the cadence label says the reading is live (it is shown, not recorded).
    var cadenceLabel: String { Self.smallLabel("CADENCE", cadence, liveTag: phase == .paused || phase == .ready) }
    static func smallLabel(_ base: String, _ t: SensorTruth, liveTag: Bool) -> String {
        switch t {
        case .measured: return liveTag ? base + " · LIVE" : base
        case .stale: return base + " · NO UPDATE"
        case .searching: return base + " · SEARCHING"
        case .disconnected, .unavailable: return base
        }
    }

    /// "31.4 km/h", or "—" when there is no speed. Never 0.0 for a missing speed.
    var speedText: String {
        guard let s = speedKmh else { return "—" }
        return String(format: imperial ? "%.1f mph" : "%.1f km/h", imperial ? s / 1.609344 : s)
    }
    /// What follows the speed in small type: its reason when missing, "estimated" when the fix is poor.
    var speedNote: String? { speedKmh == nil ? speedReason : (speedEstimated ? "estimated" : nil) }
    var distanceText: String {
        guard distanceKnown else { return "—" }
        return String(format: imperial ? "%.1f mi" : "%.1f km", imperial ? distanceKm / 1.609344 : distanceKm)
    }

    /// The warning box; nil while every sensor is reporting. Nothing is warned about before a ride is being recorded,
    /// and a value the recorder does not store cannot be "not being recorded" news.
    var warning: String? {
        guard phase != .ready else { return nil }
        if powerStored {
            switch power {
            case .stale: return "Power meter is not updating"
            case .disconnected: return "Power meter lost. Power and cadence are not being recorded."
            default: break
            }
        }
        switch heartRate {
        case .stale: return "Heart rate is not updating"
        case .disconnected: return "Heart-rate sensor lost. Heart rate is not being recorded."
        default: return nil
        }
    }
    /// Every box under the figures, in order: the pause statement, the sensor warning, the recorder's statements.
    var notices: [CyclingNotice] {
        var out: [CyclingNotice] = []
        if phase == .paused { out.append(CyclingNotice(kind: .paused, text: "Paused. Time and distance are not counting.")) }
        if let w = warning { out.append(CyclingNotice(kind: .warning, text: w)) }
        out += recorderNotes.map { CyclingNotice(kind: .info, text: $0) }
        return out
    }
    var sourceLine: CyclingSourceLine {
        if simulated { return CyclingSourceLine(state: .simulated, text: "Simulated values · no sensor, no GPS") }
        if sourceNames.isEmpty { return CyclingSourceLine(state: .none, text: "No sensor is sending values") }
        return CyclingSourceLine(state: .live, text: sourceNames.joined(separator: " · "))
    }
    /// The three values on the Map view (sheet 05a C2: "same recording, three values").
    var mapTiles: [CyclingMapTile] {
        let d = distanceKnown ? String(format: "%.1f", imperial ? distanceKm / 1.609344 : distanceKm) : "—"
        return [CyclingMapTile(label: "TIME", value: Self.clock(elapsedSeconds)), CyclingMapTile(label: imperial ? "MI" : "KM", value: d), CyclingMapTile(label: "POWER", value: power.figure)]
    }
    /// What a minimised ride would show on the Train ball (sheet 05b C7 — blocked; only the value exists).
    var mini: CyclingMiniState? {
        guard phase == .recording || phase == .paused else { return nil }
        return CyclingMiniState(elapsedSeconds: elapsedSeconds, paused: phase == .paused, simulated: simulated)
    }

    static func clock(_ s: Int) -> String { let v = max(0, s); return v >= 3600 ? String(format: "%d:%02d:%02d", v / 3600, v / 60 % 60, v % 60) : String(format: "%02d:%02d", v / 60, v % 60) }
    /// "4:24", "0:46" — minutes without a leading zero, for the small print.
    static func short(_ s: Int) -> String { let v = max(0, s); return v >= 3600 ? clock(v) : String(format: "%d:%02d", v / 60, v % 60) }
}

/// The one small value a minimised ride needs (sheet 05b C7, the "24:36" under the Train ball). Minimising a ride is
/// BLOCKED by the cycling safety gate; nothing reads this yet.
struct CyclingMiniState: Equatable {
    var elapsedSeconds: Int
    var paused: Bool
    var simulated: Bool
    var label: String { (paused ? "Paused " : "") + CyclingReadout.clock(elapsedSeconds) }
}

// MARK: - From the real sensors to a truth (pure; the adapter in CyclingLiveV14 only gathers the signals)

/// The state of one source that could provide a metric — the sensor hub's `SourceState` by its raw name, and whether the
/// athlete set that source up.
struct CyclingSourceStatus: Equatable {
    var state: String           // "connected", "connecting", "disconnected", "notAuthorized", "notConfigured", "planned"
    var configured: Bool
}

/// The link to whatever provides one metric, over all its possible sources.
enum CyclingLink: String { case connected, searching, lost, notSetUp }

struct CyclingSensorInput: Equatable {
    /// The sensor hub's current reading — fresh and usable; nil when it has none.
    var fresh: Int?
    /// The newest reading the hub still holds for this metric, fresh or not, and its age.
    var last: Int? = nil
    var lastAgeSeconds: Int? = nil
    var link: CyclingLink
}

enum CyclingSensorMap {
    /// A reading older than this is no longer shown as a dimmed last value: it becomes "—", no signal.
    static let staleLimitSeconds = 15

    /// The best link among a metric's sources: connected beats connecting beats a set-up source that is away.
    /// A source the athlete never set up is not "lost"; with nothing else the metric is simply not available.
    static func link(_ sources: [CyclingSourceStatus]) -> CyclingLink {
        if sources.contains(where: { $0.state == "connected" }) { return .connected }
        if sources.contains(where: { $0.state == "connecting" }) { return .searching }
        if sources.contains(where: { ($0.state == "disconnected" || $0.state == "notAuthorized") && $0.configured }) { return .lost }
        return .notSetUp
    }

    /// The five truths. A fresh reading is measured — a zero included. With the link up and no fresh reading, the last
    /// one is shown dimmed with its age for a few seconds, then it is "no signal". A dropped link is "—" at once: an
    /// old number is never shown for a sensor that is gone. Nothing here ever produces a number that was not read.
    static func truth(_ i: CyclingSensorInput) -> SensorTruth {
        if let v = i.fresh { return .measured(v) }
        switch i.link {
        case .connected:
            guard let l = i.last, let a = i.lastAgeSeconds else { return .searching }      // linked, nothing received yet
            return a <= staleLimitSeconds ? .stale(last: l, ageSeconds: max(1, a)) : .disconnected
        case .searching: return .searching
        case .lost: return .disconnected
        case .notSetUp: return .unavailable
        }
    }

    /// Source names in display order, without blanks or repeats.
    static func sourceNames(_ names: [String?]) -> [String] {
        var out: [String] = []
        for n in names { if let n, !n.isEmpty, !out.contains(n) { out.append(n) } }
        return out
    }

    /// Seconds with a recorded speed of at least 0.5 m/s — the ride recorder's own threshold for counting distance.
    /// nil when no second carries a speed at all: then there is no moving time to show.
    static func movingSeconds(speedsCms: [Int?]) -> Int? {
        guard speedsCms.contains(where: { $0 != nil }) else { return nil }
        return speedsCms.reduce(0) { $0 + (($1 ?? 0) >= 50 ? 1 : 0) }
    }

    /// A phone-recorded ride stores time, GPS and Apple Watch heart rate only. Whatever else is on screen is said to be
    /// live only, by name.
    static func notStoredNote(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "This phone is the recorder. \(list.prefix(1).uppercased() + list.dropFirst()) \(names.count == 1 ? "is" : "are") shown live and not stored in this ride."
    }

    /// Why there is no speed, from the phone-GPS state ("off", "searching", "good", "lost").
    static func speedReason(gps: String) -> String {
        switch gps {
        case "searching": return "waiting for GPS"
        case "lost": return "GPS lost"
        case "good": return "no speed reading"
        default: return "no speed source"
        }
    }
}

// MARK: - Finishing (sheet 05b C11)

/// What the finish page states. Averages use measured seconds only; seconds without a value are counted and named,
/// never filled in.
struct CyclingFinishSummary: Equatable {
    var elapsedSeconds: Int
    var movingSeconds: Int?
    var distanceKm: Double?
    var imperial = false
    var averagePower: Int?
    var powerMissingSeconds: Int
    var averageHeartRate: Int?
    var heartRateMissingSeconds: Int

    /// `power` / `heartRate`: one entry per ride second, nil = no value that second.
    static func make(elapsedSeconds: Int, movingSeconds: Int?, distanceKm: Double?, imperial: Bool = false, power: [Int?], heartRate: [Int?]) -> CyclingFinishSummary {
        func avg(_ a: [Int?]) -> Int? { let v = a.compactMap { $0 }; return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded()) }
        func missing(_ a: [Int?]) -> Int { a.contains { $0 != nil } ? a.filter { $0 == nil }.count : 0 }
        return CyclingFinishSummary(elapsedSeconds: elapsedSeconds, movingSeconds: movingSeconds, distanceKm: distanceKm, imperial: imperial,
                                    averagePower: avg(power), powerMissingSeconds: missing(power), averageHeartRate: avg(heartRate), heartRateMissingSeconds: missing(heartRate))
    }
    var elapsedText: String { CyclingReadout.clock(elapsedSeconds) }
    var movingText: String? { movingSeconds.map { "moving \(CyclingReadout.clock($0))" } }
    var distanceText: String { distanceKm.map { String(format: imperial ? "%.1f mi" : "%.1f km", imperial ? $0 / 1.609344 : $0) } ?? "—" }
    var powerText: String { averagePower.map { "\($0) W average" } ?? "—" }
    var powerDetail: String? { averagePower == nil ? "no power values" : Self.missingText(powerMissingSeconds) }
    var heartRateText: String { averageHeartRate.map { "\($0) bpm average" } ?? "—" }
    var heartRateDetail: String? { averageHeartRate == nil ? "no heart-rate values" : Self.missingText(heartRateMissingSeconds) }
    /// "2 min 12 s missing — not filled in"; nil when nothing is missing.
    static func missingText(_ s: Int) -> String? {
        guard s > 0 else { return nil }
        let d = s >= 60 ? "\(s / 60) min \(s % 60) s" : "\(s) s"
        return "\(d) missing — not filled in"
    }
}

/// The Lab demonstration: a fixed script over ride time, so every screenshot and test sees the same thing. It walks
/// through the sensor states on purpose: riding in range, a measured zero while coasting, a stale meter, a lost meter,
/// and back. All of it is invented for the demonstration and labelled so on screen.
enum CyclingDemoScript {
    static let title = "Tempo intervals"
    /// The script's invented interval length, for the "interval −m:ss" clock.
    static let intervalSeconds = 300
    /// `t` = ride seconds (pauses excluded).
    static func readout(at t: Int, phase: CyclingPhase, laps: Int) -> CyclingReadout {
        let c = t % 90                                   // the script repeats every 90 ride seconds
        let wobble = [0, 3, -2, 5, -4, 1, 4, -3][t % 8]
        var power: SensorTruth = .measured(230 + wobble)
        var cadence: SensorTruth = .measured(88 + wobble / 2)
        var speed: Double? = 31.4 + Double(wobble) / 10
        switch c {
        case 30..<40: power = .measured(0); cadence = .measured(0); speed = 27.0            // coasting: a real zero
        case 50..<60: power = .stale(last: 231, ageSeconds: c - 49); cadence = .stale(last: 88, ageSeconds: c - 49)
        case 60..<72: power = .disconnected; cadence = .disconnected
        default: break
        }
        var r = CyclingReadout(title: title, phase: phase, elapsedSeconds: t, movingSeconds: t, power: power,
                               heartRate: .measured(150 + min(8, t / 20) + wobble / 3), cadence: cadence, speedKmh: speed,
                               distanceKm: Double(t) * 31.4 / 3600, targetLow: 220, targetHigh: 240, laps: laps)
        r.simulated = true
        r.intervalRemainingSeconds = intervalSeconds - t % intervalSeconds
        return r
    }
    /// The demonstration's finish page: the script's own seconds, averaged the same way as a real ride's.
    static func summary(seconds: Int) -> CyclingFinishSummary {
        let all = (0..<max(0, seconds)).map { readout(at: $0, phase: .recording, laps: 0) }
        func v(_ t: SensorTruth) -> Int? { if case .measured(let x) = t { return x }; return nil }
        return CyclingFinishSummary.make(elapsedSeconds: seconds, movingSeconds: seconds, distanceKm: Double(seconds) * 31.4 / 3600,
                                         power: all.map { v($0.power) }, heartRate: all.map { v($0.heartRate) })
    }
}
