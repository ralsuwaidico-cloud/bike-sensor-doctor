import Foundation

// PORTABLE CORE — Swift port of the Nokia BikeComputer coaching core (app/src/main/java/.../core: Zones.kt, Targets.kt,
// Session.kt, WorkoutTargets.kt, LiveGraph.kt GraphBands/GraphScale, Coach.kt CoachEngine v3). No UI imports.
// The engine is verified by the shared vectors in testvectors/coach (CoachVectorTests), the same files the Kotlin and
// the firmware ports must pass. Nothing is invented: a missing or stale signal is simply unavailable.

// MARK: - Zones

/// Coggan 7-zone power model, as % of FTP.
enum PowerZones {
    static let upper: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
    static let names = ["Z1 Recovery", "Z2 Endurance", "Z3 Tempo", "Z4 Threshold", "Z5 VO2", "Z6 Anaerobic", "Z7 Neuro"]
    /// 1…7; 0 when power is nil/0 (coasting) so the UI can show a neutral state.
    static func zone(_ powerW: Int?, ftp: Int) -> Int {
        guard let p = powerW, p > 0, ftp > 0 else { return 0 }
        let frac = Double(p) / Double(ftp)
        for (i, u) in upper.enumerated() where frac <= u { return i + 1 }
        return 7
    }
    static func name(_ z: Int) -> String { (1...7).contains(z) ? names[z - 1] : "—" }
    /// Watt range of a zone, e.g. Z2 at FTP 200 → 110…150. nil high = open-ended.
    static func range(_ zone: Int, ftp: Int) -> (lo: Int, hi: Int?) {
        guard (1...7).contains(zone), ftp > 0 else { return (0, nil) }
        let lo = zone == 1 ? 0 : Int(upper[zone - 2] * Double(ftp) + 0.5)
        let hi = zone == 7 ? nil : Int(upper[zone - 1] * Double(ftp) + 0.5)
        return (lo, hi)
    }
}

/// 5-zone heart-rate model as % of max HR.
enum HrZones {
    static let upper: [Double] = [0.60, 0.70, 0.80, 0.90]
    static let names = ["Z1 Easy", "Z2 Fat-burn", "Z3 Aerobic", "Z4 Threshold", "Z5 Max"]
    static func zone(_ hr: Int?, maxHr: Int) -> Int {
        guard let h = hr, h > 0, maxHr > 0 else { return 0 }
        let frac = Double(h) / Double(maxHr)
        for (i, u) in upper.enumerated() where frac <= u { return i + 1 }
        return 5
    }
    static func name(_ z: Int) -> String { (1...5).contains(z) ? names[z - 1] : "—" }
}

// MARK: - Targets (what the gauges indicate)

enum TargetStatus { case below, on, above, unknown }
enum CoachShape { case up, check, down, none }
enum CoachMode: String { case FREE, CADENCE, ZONE2, ENDURANCE, INTERVAL }
enum EffortSource { case auto, heartRate, power }
enum Phase: String { case WARMUP, MAIN, RECOVERY, COOLDOWN }

enum Targets {
    /// Power gauge full-scale: the start of Z7 (1.5 × FTP), never below 300 W.
    static func powerGaugeMaxW(ftp: Int) -> Int { max(300, Int(Double(ftp) * 1.5 + 0.5)) }
    static let cadenceGaugeMax = 130
    static func gaugeFraction(_ value: Int?, max m: Int) -> Double {
        guard let v = value, m > 0 else { return 0 }
        return min(1, max(0, Double(v) / Double(m)))
    }
    /// Coasting (0 W) is unknown: a power meter reads 0 unloaded and that is not "below target".
    static func power(_ powerW: Int?, ftp: Int, targetZone: Int) -> TargetStatus {
        let z = PowerZones.zone(powerW, ftp: ftp); return z == 0 ? .unknown : compare(z, targetZone)
    }
    static func hr(_ bpm: Int?, maxHr: Int, targetZone: Int) -> TargetStatus {
        let z = HrZones.zone(bpm, maxHr: maxHr); return z == 0 ? .unknown : compare(z, targetZone)
    }
    static func cadence(_ rpm: Int?, low: Int, high: Int) -> TargetStatus {
        guard let r = rpm, r > 0 else { return .unknown }
        return r < low ? .below : r > high ? .above : .on
    }
    private static func compare(_ zone: Int, _ target: Int) -> TargetStatus { zone < target ? .below : zone > target ? .above : .on }
    /// Middle of the target power zone as 0…1 of the gauge.
    static func powerTargetFraction(targetZone: Int, ftp: Int) -> Double {
        let r = PowerZones.range(targetZone, ftp: ftp)
        let mid = r.hi.map { Double(r.lo + $0) / 2 } ?? Double(r.lo)
        return min(1, max(0, mid / Double(powerGaugeMaxW(ftp: ftp))))
    }
    static func hrTargetFraction(targetZone: Int) -> Double {
        let b: [Double] = [0, 0.60, 0.70, 0.80, 0.90, 1.0]
        guard (1...5).contains(targetZone) else { return 0 }
        return targetZone == 5 ? 0.90 : (b[targetZone - 1] + b[targetZone]) / 2
    }
    static func powerZoneTicks(ftp: Int) -> [Double] {
        let m = Double(powerGaugeMaxW(ftp: ftp))
        return [0.55, 0.75, 0.90, 1.05, 1.20, 1.50].map { min(1, max(0, $0 * Double(ftp) / m)) }
    }
    static let hrZoneTicks: [Double] = [0.60, 0.70, 0.80, 0.90]
    /// Percent of the way through the current power zone (0…100); nil when not in a zone.
    static func powerZonePercent(_ powerW: Int?, ftp: Int) -> Int? {
        let z = PowerZones.zone(powerW, ftp: ftp); guard z > 0, let p = powerW else { return nil }
        let r = PowerZones.range(z, ftp: ftp)
        let top = r.hi ?? Int(Double(r.lo) + Double(ftp) * 0.5)
        return pct(Double(p), Double(r.lo), Double(top))
    }
    static func hrZonePercent(_ bpm: Int?, maxHr: Int) -> Int? {
        let z = HrZones.zone(bpm, maxHr: maxHr); guard z > 0, let h = bpm else { return nil }
        let b: [Double] = [0, 0.60, 0.70, 0.80, 0.90, 1.0]
        return pct(Double(h), b[z - 1] * Double(maxHr), b[z] * Double(maxHr))
    }
    private static func pct(_ v: Double, _ lo: Double, _ hi: Double) -> Int {
        guard hi > lo else { return 0 }
        return Int(min(100, max(0, (v - lo) / (hi - lo) * 100)) + 0.5)
    }
    static func coachDirection(_ t: CueType) -> Int {
        switch t { case .PEDAL_FASTER, .PUSH_HARDER, .WORK, .PACE: return 1; case .PEDAL_SLOWER, .EASE_OFF, .RECOVER, .SURGE: return -1; default: return 0 }
    }
    static func coachShape(_ t: CueType) -> CoachShape {
        switch t { case .PEDAL_FASTER, .PUSH_HARDER, .WORK, .PACE: return .up; case .PEDAL_SLOWER, .EASE_OFF, .RECOVER, .SURGE: return .down; case .KEEP_IT_UP: return .check; default: return .none }
    }
    static func targetZone(_ mode: CoachMode) -> Int { mode == .ENDURANCE ? 3 : 2 }
}

// MARK: - Session phases and workout target bands

struct SessionPlan { var warmupSec = 300; var cooldownSec = 300; var plannedSec: Int? = nil }
enum Session {
    static func phaseAt(_ plan: SessionPlan, elapsedMs: Int64, cooldownRequestedAtMs: Int64?) -> Phase {
        if let c = cooldownStartMs(plan, cooldownRequestedAtMs: cooldownRequestedAtMs), elapsedMs >= c { return .COOLDOWN }
        if elapsedMs < Int64(plan.warmupSec) * 1000 { return .WARMUP }
        return .MAIN
    }
    static func cooldownStartMs(_ plan: SessionPlan, cooldownRequestedAtMs: Int64?) -> Int64? {
        let planned = plan.plannedSec.map { Int64(max(plan.warmupSec, $0 - plan.cooldownSec)) * 1000 }
        return [cooldownRequestedAtMs, planned].compactMap { $0 }.min()
    }
    static func warmupRemainingSec(_ plan: SessionPlan, elapsedMs: Int64) -> Int { Int(max(0, (Int64(plan.warmupSec) * 1000 - elapsedMs) / 1000)) }
}

struct WorkoutPlan { var hrLo: Int; var hrHi: Int; var pwLo: Int?; var pwHi: Int?; var cadLo: Int; var cadHi: Int; var ftp: Int; var warmupSec: Int; var cooldownSec: Int; var plannedSec: Int? = nil; var ramps = true }
struct ActiveTargets: Equatable { var hrLo: Int; var hrHi: Int; var pwLo: Int?; var pwHi: Int?; var cadLo: Int; var cadHi: Int; var label: String }

enum WorkoutTargets {
    private static func r(_ x: Double) -> Int { Int(x.rounded()) }
    static func forPhase(_ p: WorkoutPlan, phase: Phase, elapsedSec: Int, cooldownStartSec: Int?) -> ActiveTargets {
        let floor = min(105, p.hrLo - 10)
        let pwFloor = p.pwLo.map { _ in r(0.35 * Double(p.ftp)) }
        let pwMid = p.pwHi.map { _ in r(0.5 * Double(p.ftp)) }
        switch phase {
        case .WARMUP:
            let u = (p.ramps && p.warmupSec > 0) ? min(1, max(0, Double(elapsedSec) / Double(p.warmupSec))) : 0
            let hi = r(Double(p.hrLo - 10) + Double(p.hrHi - (p.hrLo - 10)) * u)
            let pw: Int? = (pwMid != nil && p.pwHi != nil) ? r(Double(pwMid!) + Double(p.pwHi! - pwMid!) * u) : nil
            return ActiveTargets(hrLo: floor, hrHi: hi, pwLo: pwFloor, pwHi: pw, cadLo: p.cadLo, cadHi: p.cadHi, label: p.ramps ? "WARM-UP RAMP" : "WARM-UP Z1")
        case .COOLDOWN:
            let start = cooldownStartSec ?? elapsedSec
            let u = (p.ramps && p.cooldownSec > 0) ? min(1, max(0, Double(elapsedSec - start) / Double(p.cooldownSec))) : 0
            let hi = r(Double(p.hrHi) - Double(p.hrHi - (p.hrLo - 10)) * u)
            let pw: Int? = (pwMid != nil && p.pwHi != nil) ? r(Double(p.pwHi!) - Double(p.pwHi! - pwMid!) * u) : nil
            return ActiveTargets(hrLo: floor, hrHi: hi, pwLo: pwFloor, pwHi: pw, cadLo: p.cadLo, cadHi: p.cadHi, label: p.ramps ? "COOL-DOWN RAMP" : "COOL-DOWN Z1")
        case .RECOVERY: return ActiveTargets(hrLo: floor, hrHi: p.hrLo - 1, pwLo: pwFloor, pwHi: pwMid, cadLo: p.cadLo, cadHi: p.cadHi, label: "RECOVERY Z1")
        case .MAIN: return ActiveTargets(hrLo: p.hrLo, hrHi: p.hrHi, pwLo: p.pwLo, pwHi: p.pwHi, cadLo: p.cadLo, cadHi: p.cadHi, label: "MAIN")
        }
    }
    static func plannedCooldownStartSec(_ p: WorkoutPlan) -> Int? { p.plannedSec.map { max(p.warmupSec, $0 - p.cooldownSec) } }
}

// MARK: - Live graph scaling (each signal normalised against its own band)

enum GraphStatus { case none, zero, below, on, above }

struct GraphBands: Equatable {
    var pwLo: Int?; var pwHi: Int?; var hrLo: Int; var hrHi: Int; var cadLo: Int; var cadHi: Int
    /// true when the power band is only a display reference (meter unverified / no workout power target).
    var pwReference = false
    static func resolve(targets: ActiveTargets?, ftpW: Int, powerTrusted: Bool, maxHr: Int, targetZone: Int, cadLo: Int, cadHi: Int) -> GraphBands {
        let z = min(5, max(1, targetZone))
        let pwUpper: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20]
        let refLo = ftpW > 0 ? (z == 1 ? Int(Double(ftpW) * 0.30) : Int(Double(ftpW) * pwUpper[z - 2]) + 1) : 100
        let refHi = ftpW > 0 ? Int(Double(ftpW) * pwUpper[z - 1]) : 200
        if let t = targets {
            if let lo = t.pwLo, let hi = t.pwHi { return GraphBands(pwLo: lo, pwHi: hi, hrLo: t.hrLo, hrHi: t.hrHi, cadLo: t.cadLo, cadHi: t.cadHi) }
            return GraphBands(pwLo: refLo, pwHi: refHi, hrLo: t.hrLo, hrHi: t.hrHi, cadLo: t.cadLo, cadHi: t.cadHi, pwReference: true)
        }
        let hrUpper: [Double] = [0.60, 0.70, 0.80, 0.90, 1.0]
        let hrLo = z == 1 ? Int(Double(maxHr) * 0.50) : Int(Double(maxHr) * hrUpper[z - 2]) + 1
        let hrHi = Int(Double(maxHr) * hrUpper[z - 1])
        return GraphBands(pwLo: refLo, pwHi: refHi, hrLo: hrLo, hrHi: hrHi, cadLo: cadLo, cadHi: cadHi, pwReference: !(powerTrusted && ftpW > 0))
    }
}

enum GraphScale {
    static let bandH = 0.28
    static let lin = 1.5
    static func norm(_ v: Int?, lo: Int?, hi: Int?) -> Double? {
        guard let v, let lo, let hi, hi > lo else { return nil }
        return Double(v - lo) / Double(hi - lo)
    }
    /// Plot fraction from the top (0 = top, 1 = bottom).
    static func yFrac(_ n: Double) -> Double {
        let d = n - 0.5
        let y: Double
        if abs(d) <= lin { y = 0.5 - d * bandH }
        else { let extra = abs(d) - lin; let margin = 0.5 - lin * bandH; y = 0.5 - (d < 0 ? -1 : 1) * (lin * bandH + margin * (extra / (extra + 1.5))) }
        return min(0.99, max(0.01, y))
    }
    static var bandTop: Double { yFrac(1) }
    static var bandBot: Double { yFrac(0) }
    static func status(_ v: Int?, lo: Int?, hi: Int?) -> GraphStatus {
        guard let v else { return .none }
        if v == 0 { return .zero }
        guard let n = norm(v, lo: lo, hi: hi) else { return .none }
        return n < 0 ? .below : n > 1 ? .above : .on
    }
}

// MARK: - Coach engine (v3)

enum CueType: String { case NONE, KEEP_IT_UP, PEDAL_FASTER, PEDAL_SLOWER, EASE_OFF, PUSH_HARDER, RECOVER, WORK, NO_HR, NO_POWER, WARMUP, COOLDOWN, QUIET, SURGE, STEADY, SENSOR_LOST, PACE }

enum CoachAction: String {
    case NONE, WARM_UP, START_COOLDOWN, WIND_DOWN, EASIER_GEAR, HARDER_GEAR, REDUCE_PRESSURE, INCREASE_EFFORT, HR_RISING_EASE
    case PEDAL_FASTER, PEDAL_SLOWER, KEEP_CADENCE_STEADY, HOLD_PACE, STABLE_MAINTAIN, RECOVER, NO_SIGNAL, QUIET
    case SMOOTH_SURGES, STEADY_EFFORT, RECOVERED, SENSOR_LOST, POWER_DROPPING, STEADY_MILESTONE, STEADY_PACE
    var icon: String {
        switch self {
        case .NONE: return "○"; case .WARM_UP: return "☼"; case .START_COOLDOWN, .WIND_DOWN, .RECOVER: return "❄"
        case .EASIER_GEAR: return "⚙−"; case .HARDER_GEAR: return "⚙+"; case .REDUCE_PRESSURE: return "⇩"; case .INCREASE_EFFORT: return "⇧"; case .HR_RISING_EASE: return "♥↑"
        case .PEDAL_FASTER: return "↻+"; case .PEDAL_SLOWER: return "↻−"; case .KEEP_CADENCE_STEADY, .STEADY_EFFORT, .STEADY_PACE: return "≈"; case .HOLD_PACE: return "═"
        case .STABLE_MAINTAIN, .RECOVERED: return "✓"; case .NO_SIGNAL: return "?"; case .QUIET: return "…"; case .SMOOTH_SURGES: return "∿"; case .SENSOR_LOST: return "⚠"
        case .POWER_DROPPING: return "↘"; case .STEADY_MILESTONE: return "★"
        }
    }
}

struct CoachCue: Equatable {
    var type: CueType; var headline: String; var detail: String; var spoken: String; var reason: String = ""
    var action: CoachAction = .NONE; var sources: String = ""; var live: String = ""
    /// Glanceable form: short instruction + short reason.
    var short: String = ""; var why: String = ""
    static let none = CoachCue(type: .NONE, headline: "", detail: "", spoken: "")
}

enum CoachFrequency { case quiet, normal, frequent }

struct Assessment: Equatable { var atMs: Int64; var summary: String; var progress: String; var inBandPctMinute: Int?; var hrTrend: Int?; var powerTrend: Int?; var cadTrend: Int? }

struct CoachConfig {
    var mode: CoachMode = .FREE
    var cadenceEnabled = true
    var cadenceLow = 85, cadenceHigh = 95
    var effortSource: EffortSource = .auto
    var targetPowerZone = 2, targetHrZone = 2
    var ftpW = 200, maxHr = 185
    var hrZoneBounds: [Double] = [0.60, 0.70, 0.80, 0.90]
    var minAlertMs: Int64 = 10_000, sameRepeatMs: Int64 = 45_000, keepRepeatMs: Int64 = 90_000, keepHoldMs: Int64 = 5_000, infoRepeatMs: Int64 = 30_000
    var effortHoldMs: Int64 = 8_000, powerHoldMs: Int64 = 2_000, surgeHoldMs: Int64 = 6_000, cadenceHoldMs: Int64 = 5_000
    var smoothingMs: Int64 = 5_000, staleMs: Int64 = 4_000
    var hysteresisFrac = 0.02, cadenceHysteresis = 3
    var powerCoaching = true
    var graceMs: Int64 = 0
    var backoff = false, quietMs: Int64 = 300_000
    /// FTP is only the onboarding assumption: without a strap the coach uses the rider's own steady output as the yardstick.
    var ftpAssumed = false
    func withFrequency(_ f: CoachFrequency) -> CoachConfig {
        var c = self
        switch f {
        case .quiet: c.minAlertMs = 15_000; c.sameRepeatMs = 120_000; c.keepRepeatMs = 0; c.infoRepeatMs = 60_000
        case .normal: c.minAlertMs = 10_000; c.sameRepeatMs = 45_000; c.keepRepeatMs = 90_000; c.infoRepeatMs = 30_000
        case .frequent: c.minAlertMs = 8_000; c.sameRepeatMs = 30_000; c.keepRepeatMs = 60_000; c.infoRepeatMs = 20_000
        }
        return c
    }
}

struct IntervalPlan { var workSec = 240; var restSec = 120; var repeats = 4 }

/// One reading with its freshness. nil value or fresh == false ⇒ unavailable.
struct Signal: Equatable {
    var value: Int?; var fresh = true
    var available: Bool { fresh && value != nil }
    static let none = Signal(value: nil, fresh: false)
}

struct CoachInput {
    var nowMs: Int64
    var phase: Phase = .MAIN
    var cadence: Signal = .none, hr: Signal = .none, power: Signal = .none
    var targets: ActiveTargets? = nil
    var speedKmh: Double? = nil
}

final class CoachEngine {
    var config: CoachConfig
    var interval = IntervalPlan()
    private(set) var lastAssessment: Assessment?
    init(config: CoachConfig = CoachConfig()) { self.config = config }

    private enum Band { case below, on, above }

    private struct Smoother {
        var win: [(Int64, Int)] = []
        mutating func feed(_ now: Int64, _ s: Signal, _ smoothingMs: Int64) -> Int? {
            guard s.available, let v = s.value else { win.removeAll(); return nil }
            win.append((now, v))
            while let f = win.first, now - f.0 > smoothingMs { win.removeFirst() }
            return Int(Double(win.reduce(0) { $0 + $1.1 }) / Double(win.count) + 0.5)
        }
        mutating func clear() { win.removeAll() }
    }
    private struct BandTracker {
        var band: Band? = nil; var sinceMs: Int64 = 0
        mutating func update(_ now: Int64, _ frac: Double?, _ lo: Double, _ hi: Double, _ h: Double) -> Band? {
            guard let frac else { band = nil; return nil }
            let next: Band
            switch band {
            case nil: next = frac < lo ? .below : frac > hi ? .above : .on
            case .below: next = frac >= lo + h ? (frac > hi ? .above : .on) : .below
            case .above: next = frac <= hi - h ? (frac < lo ? .below : .on) : .above
            case .on: next = frac < lo - h ? .below : frac > hi + h ? .above : .on
            }
            if next != band { band = next; sinceMs = now }
            return next
        }
        func held(_ now: Int64, _ ms: Int64) -> Bool { band != nil && now - sinceMs >= ms }
        mutating func clear() { band = nil }
    }
    /// 30 s-vs-previous-30 s trend and a one-minute coefficient of variation.
    private struct Trend {
        var win: [(Int64, Double)] = []; var cvWin: [Double] = []
        mutating func feed(_ now: Int64, _ v: Double?) {
            guard let v else { win.removeAll(); cvWin.removeAll(); return }
            win.append((now, v)); while let f = win.first, now - f.0 > 60_000 { win.removeFirst() }
            cvWin.append(v); while cvWin.count > 60 { cvWin.removeFirst() }
        }
        func perMinute(_ now: Int64) -> Double? {
            guard win.count >= 40 else { return nil }
            let recent = win.filter { now - $0.0 <= 30_000 }.map { $0.1 }, older = win.filter { now - $0.0 > 30_000 }.map { $0.1 }
            guard recent.count >= 10, older.count >= 10 else { return nil }
            return (recent.reduce(0, +) / Double(recent.count) - older.reduce(0, +) / Double(older.count)) * 2
        }
        func mean() -> Double? { cvWin.count < 45 ? nil : cvWin.reduce(0, +) / Double(cvWin.count) }
        func cv() -> Double? {
            guard cvWin.count >= 45 else { return nil }
            let m = cvWin.reduce(0, +) / Double(cvWin.count); guard m > 0 else { return nil }
            return (cvWin.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(cvWin.count)).squareRoot() / m
        }
        func reversals() -> Int {
            guard cvWin.count >= 45 else { return 0 }
            var n = 0, last = 0
            for i in 1..<cvWin.count { let d = cvWin[i] - cvWin[i - 1]; let s = d >= 3 ? 1 : d <= -3 ? -1 : 0; if s != 0 { if last != 0, s != last { n += 1 }; last = s } }
            return n
        }
        mutating func clear() { win.removeAll(); cvWin.removeAll() }
    }

    private var cadS = Smoother(), hrS = Smoother(), pwS = Smoother()
    private var hrBand = BandTracker(), pwBand = BandTracker()
    private var cadState: Band? = nil; private var cadSince: Int64 = 0
    private var lastType: CueType = .NONE
    private var lastEmitMs: Int64 = Int64.min / 2
    private var lastEmitByType: [CueType: Int64] = [:]
    private var allGoodSince: Int64? = nil
    private var keepArmed = true
    private var announcedPhase: Phase? = nil
    private var surgeSince: Int64? = nil, spikeSince: Int64? = nil, easeAtMs: Int64? = nil, recoveredForMs: Int64? = nil
    private var powerSeenMs: Int64? = nil, hrSeenMs: Int64? = nil; private var powerLostSaid = false, hrLostSaid = false
    private var lastCad: Int? = nil, lastHr: Int? = nil, lastPw: Int? = nil, lastSpeed: Double? = nil
    private var lastHb: Band? = nil, lastPb: Band? = nil
    private var lastHrBand = "", lastPwBand = ""
    private var lastStopped = false, lastCoasting = false
    private var refWin: [(Int64, Int)] = [], minWin: [(Int64, Int)] = []
    private var lowSinceMs: Int64? = nil; private var steadySec = 0, lastMilestoneMin = 0; private var mainSinceMs: Int64? = nil; private var noSensorsSaid = false
    private var speedWin: [(Int64, Double)] = []
    private var hrT = Trend(), pwT = Trend(), cadT = Trend(), spT = Trend()
    private var minuteAbove = 0, minuteBelow = 0, minuteIn = 0; private var minuteStartMs: Int64 = Int64.min / 2
    private var phaseSeen: Phase? = nil; private var phaseSinceMs: Int64 = 0
    private var repeatCount = 0; private var quietSinceMs: Int64 = 0
    private var intervalStartMs: Int64? = nil

    func reset() {
        cadS.clear(); hrS.clear(); pwS.clear(); hrBand.clear(); pwBand.clear(); cadState = nil
        lastType = .NONE; lastEmitMs = Int64.min / 2; lastEmitByType.removeAll(); allGoodSince = nil; keepArmed = true
        announcedPhase = nil; surgeSince = nil; spikeSince = nil; easeAtMs = nil; recoveredForMs = nil; intervalStartMs = nil
        powerSeenMs = nil; hrSeenMs = nil; powerLostSaid = false; hrLostSaid = false
        refWin.removeAll(); minWin.removeAll(); lowSinceMs = nil; steadySec = 0; lastMilestoneMin = 0; mainSinceMs = nil; noSensorsSaid = false; speedWin.removeAll()
        phaseSeen = nil; phaseSinceMs = 0; repeatCount = 0; quietSinceMs = 0
        hrT.clear(); pwT.clear(); cadT.clear(); spT.clear(); minuteAbove = 0; minuteBelow = 0; minuteIn = 0; minuteStartMs = Int64.min / 2; lastAssessment = nil
        lastHr = nil; lastPw = nil; lastSpeed = nil; lastHb = nil; lastPb = nil
    }

    func update(nowMs: Int64, cadenceRpm: Int?, hr: Int?, powerW: Int?) -> CoachCue {
        update(CoachInput(nowMs: nowMs, phase: .MAIN, cadence: Signal(value: cadenceRpm), hr: Signal(value: hr), power: Signal(value: powerW)))
    }

    /// Call ~1 Hz. Returns a cue to show/speak, or .none when there is nothing new to say.
    func update(_ input: CoachInput) -> CoachCue {
        let c = config
        if c.mode == .FREE { return .none }
        let now = input.nowMs

        // ---- 1. smoothing (stale ⇒ unavailable) ----
        let cad = cadS.feed(now, input.cadence, c.smoothingMs)
        lastCad = cad
        let hrRaw = hrS.feed(now, input.hr, c.smoothingMs)
        let coasting = input.power.available && input.power.value == 0
        let pwRaw = pwS.feed(now, coasting ? .none : input.power, c.smoothingMs)
        let useHr = c.effortSource != .power
        let usePw = c.effortSource != .heartRate && c.powerCoaching
        let hr = useHr ? hrRaw : nil
        let pw: Int? = (usePw && pwRaw != nil && pwRaw! > 0) ? pwRaw : nil
        lastHr = hr; lastPw = pw; lastSpeed = input.speedKmh
        hrT.feed(now, hr.map(Double.init)); pwT.feed(now, pw.map(Double.init)); cadT.feed(now, (cad ?? 0) > 0 ? Double(cad!) : nil); spT.feed(now, input.speedKmh)
        let stopped = (input.speedKmh != nil && input.speedKmh! < 2.0) || (cad != nil && cad == 0 && input.cadence.available)
        lastStopped = stopped; lastCoasting = coasting
        if input.power.available, let v = input.power.value, v > 0 { refWin.append((now, v)); minWin.append((now, v)) }
        while let f = refWin.first, now - f.0 > 600_000 { refWin.removeFirst() }
        while let f = minWin.first, now - f.0 > 60_000 { minWin.removeFirst() }
        if let s = input.speedKmh { speedWin.append((now, s)) }; while let f = speedWin.first, now - f.0 > 120_000 { speedWin.removeFirst() }

        // ---- 1b. sensor loss ----
        if input.power.available { powerSeenMs = now; powerLostSaid = false }
        if input.hr.available { hrSeenMs = now; hrLostSaid = false }
        let powerLost = !input.power.available && powerSeenMs != nil && (1...30_000).contains(now - powerSeenMs!) && !powerLostSaid
        let hrLost = !input.hr.available && hrSeenMs != nil && (1...30_000).contains(now - hrSeenMs!) && !hrLostSaid
        if powerLost, now - (powerSeenMs ?? now) >= c.staleMs {
            powerLostSaid = true
            let hasHr = input.hr.available
            return CoachCue(type: .SENSOR_LOST, headline: "POWER SENSOR DISCONNECTED", detail: hasHr ? "Coaching continues from heart rate" : "No effort signal until a sensor returns", spoken: hasHr ? "Power sensor lost. Coaching from heart rate." : "Power sensor lost.", reason: "POWER_LOST", action: .SENSOR_LOST, sources: "sensors", live: liveText(), short: "Power sensor lost", why: hasHr ? "coaching from heart rate" : "waiting for a sensor")
        }
        if hrLost, now - (hrSeenMs ?? now) >= c.staleMs {
            hrLostSaid = true
            let hasPw = input.power.available && usePw
            return CoachCue(type: .SENSOR_LOST, headline: "HEART-RATE SENSOR DISCONNECTED", detail: hasPw ? "Coaching continues from power" : "No effort signal until the strap returns", spoken: hasPw ? "Heart-rate sensor lost. Coaching from power." : "Heart-rate sensor lost.", reason: "HR_LOST", action: .SENSOR_LOST, sources: "sensors", live: liveText(), short: "HR strap lost", why: hasPw ? "coaching from power" : "waiting for the strap")
        }
        if stopped { allGoodSince = nil; return .none }

        // ---- 2. phase ----
        var phase = input.phase
        if c.mode == .INTERVAL, phase == .MAIN {
            if intervalStartMs == nil { intervalStartMs = now }
            let t = Int((now - intervalStartMs!) / 1000)
            let cycle = interval.workSec + interval.restSec
            let done = cycle > 0 && interval.repeats > 0 && t >= cycle * interval.repeats
            phase = done ? .COOLDOWN : (cycle > 0 && (t % cycle) >= interval.workSec) ? .RECOVERY : .MAIN
        }
        let targetZone = c.mode == .ENDURANCE ? 3 : c.targetPowerZone
        let targetHrZone = c.mode == .ENDURANCE ? 3 : c.targetHrZone
        if phase != phaseSeen { phaseSeen = phase; phaseSinceMs = now; repeatCount = 0 }
        let grace = c.graceMs > 0 && phase == .MAIN && now - phaseSinceMs < c.graceMs

        // ---- 3. bands with hysteresis ----
        let tg = input.targets
        let (hLo, hHi): (Double, Double) = tg != nil ? (Double(tg!.hrLo) / Double(c.maxHr), Double(tg!.hrHi) / Double(c.maxHr)) : hrBounds(targetHrZone)
        let (pLo, pHi): (Double, Double) = (tg != nil && tg!.pwLo != nil && tg!.pwHi != nil) ? (Double(tg!.pwLo!) / Double(c.ftpW), Double(tg!.pwHi!) / Double(c.ftpW)) : powerBounds(targetZone)
        let hb = hrBand.update(now, hr.map { Double($0) / Double(c.maxHr) }, hLo, hHi, c.hysteresisFrac)
        let pb = pwBand.update(now, pw.map { Double($0) / Double(c.ftpW) }, pLo, pHi, c.hysteresisFrac)
        lastHb = hb; lastPb = pb
        lastHrBand = tg != nil ? "\(tg!.hrLo)–\(tg!.hrHi) bpm" : "zone \(targetHrZone)"
        lastPwBand = (tg != nil && tg!.pwLo != nil && tg!.pwHi != nil) ? "\(tg!.pwLo!)–\(tg!.pwHi!) W" : "zone \(targetZone)"
        let bandText = lastHrBand
        if phase == .MAIN { switch hb ?? pb { case .above?: minuteAbove += 1; case .below?: minuteBelow += 1; case .on?: minuteIn += 1; case nil: break } }
        if minuteStartMs == Int64.min / 2 { minuteStartMs = now }
        if now - minuteStartMs >= 60_000 {
            let tot = minuteAbove + minuteBelow + minuteIn
            let pct: Int? = tot > 0 ? minuteIn * 100 / tot : nil
            let ht = hrT.perMinute(now).map { Int($0.rounded()) }, pt = pwT.perMinute(now).map { Int($0.rounded()) }, ct = cadT.perMinute(now).map { Int($0.rounded()) }
            var parts: [String] = []
            if let h = hr { parts.append("HR \(h)" + (ht.map { $0 >= 3 ? " ↑" : $0 <= -3 ? " ↓" : " →" } ?? "")) }
            if let p = pw { parts.append("\(p) W" + (pt.map { $0 >= 10 ? " ↑" : $0 <= -10 ? " ↓" : " →" } ?? "")) }
            if let k = cad, k > 0 { parts.append("\(k) rpm") }
            let progress: String
            if phase != .MAIN { progress = phase.rawValue.lowercased() }
            else if pct == nil { progress = "no effort signal this minute" }
            else if pct! >= 80 { progress = "on track — \(pct!) % of the last minute in band" }
            else if minuteAbove > minuteBelow { progress = "mostly above target (\(pct!) % in band) — ease" }
            else { progress = "mostly below target (\(pct!) % in band) — a little more" }
            lastAssessment = Assessment(atMs: now, summary: parts.joined(separator: " · "), progress: progress, inBandPctMinute: pct, hrTrend: ht, powerTrend: pt, cadTrend: ct)
            minuteStartMs = now; minuteAbove = 0; minuteBelow = 0; minuteIn = 0
        }
        let hrZone = hr.map { zoneOf(Double($0) / Double(c.maxHr), c.hrZoneBounds) }
        let pwZone = pw.map { PowerZones.zone($0, ftp: c.ftpW) }

        if c.mode == .CADENCE {
            if let s = safety(now, hb, hrZone, targetHrZone) { return s }
            return cadenceCue(now, cad, phase) ?? keepIfGood(now, phase, cad != nil)
        }

        // ---- 4. phase gates ----
        switch phase {
        case .WARMUP:
            if let s = safety(now, hb, hrZone, targetHrZone) { return s }
            return announce(now, phase, .WARMUP, "WARM UP", "Easy spinning — effort coaching starts after the warm-up", "Warm up, easy spinning", "PHASE_WARMUP")
        case .COOLDOWN:
            if hb == .above, hrBand.held(now, c.effortHoldMs) {
                return tg != nil ? emit(now, .EASE_OFF, "WIND DOWN", "Cool-down ceiling is now \(tg!.hrHi) bpm and falling — ease the effort a little", "Wind down", "COOLDOWN_RAMP")
                    : emit(now, .EASE_OFF, "EASE OFF", "Cool-down: let the heart rate come down", "Ease off", "COOLDOWN_HR_ABOVE")
            }
            return announce(now, phase, .COOLDOWN, "COOL DOWN", tg != nil ? "Last minutes: the ceiling comes down gradually. No more 'push' from here" : "Easy spinning to finish", "Cool down", "PHASE_COOLDOWN")
        case .RECOVERY:
            if pb == .above, pwBand.held(now, c.powerHoldMs) { return emit(now, .EASE_OFF, "EASE OFF", "Recovery interval — spin easy", "Ease off, recovery", "RECOVERY_PW_ABOVE") }
            return announce(now, phase, .RECOVER, "RECOVER", "Easy spin — recovery interval", "Recover", "PHASE_RECOVERY")
        case .MAIN:
            if announcedPhase != .MAIN {
                announcedPhase = .MAIN; keepArmed = true; allGoodSince = nil
                // (Kotlin original checks announcedPhase != null after the assignment, so it is always true here)
                if phaseSeen == .MAIN, now - phaseSinceMs < 2_000, lastType == .WARMUP {
                    lastType = .WORK; lastEmitMs = now
                    let b = tg != nil ? "\(tg!.hrLo)–\(tg!.hrHi) bpm" : "zone \(targetHrZone)"
                    return CoachCue(type: .WORK, headline: "SETTLE INTO YOUR TARGET", detail: "Main block: \(b)", spoken: "Settle into your target.", reason: "PHASE_MAIN", action: .HOLD_PACE, sources: "phase", live: liveText(), short: "Settle into your target", why: b)
                }
            }
        }

        // ---- patterns ----
        let pHiW: Double? = (usePw && c.ftpW > 0 && pHi < 5.0) ? pHi * Double(c.ftpW) : nil
        let rawPw: Int? = (input.power.available && (input.power.value ?? 0) > 0) ? input.power.value : nil
        let spiking = pHiW != nil && rawPw != nil && Double(rawPw!) > max(pHiW! * 1.5, pHiW! + 50)
        let pcv = pwT.cv(), pMean = pwT.mean()
        let unsteady = pw != nil && pcv != nil && pMean != nil && pcv! > 0.20 && pwT.reversals() >= 4 && pMean! >= pLo * Double(c.ftpW) && pMean! <= pHi * Double(c.ftpW)
        func steadyCue() -> CoachCue? {
            guard unsteady else { return nil }
            let e = emit(now, .STEADY, "HOLD A STEADIER EFFORT", "Average power is on target but it swung ±\(Int(((pcv ?? 0) * 100).rounded())) % over the last minute — pick one gear and keep the pressure even", "Hold a steadier effort", "PW_UNSTEADY")
            return e.type != .NONE ? e : nil
        }

        // ---- 5. effort ladder ----
        var effort: CoachCue? = nil
        if let hr {
            switch hb {
            case .above?:
                effort = hrBand.held(now, c.effortHoldMs) ? emit(now, .EASE_OFF, "EASE OFF", "Heart rate \(hr) above target \(bandText)", "Ease off", "HR_ABOVE") : hold()
            case .on?:
                let rising = (hrT.perMinute(now).map { $0 >= 6.0 } == true) && (pwT.perMinute(now).map { abs($0) < 15.0 } ?? true) && Double(hr) / Double(c.maxHr) > hHi - 0.03
                if rising, hrBand.held(now, 20_000) {
                    let e = emit(now, .EASE_OFF, "YOUR HEART RATE IS RISING. EASE OFF", "Heart rate \(hr) climbing about \(Int((hrT.perMinute(now) ?? 0).rounded())) bpm/min at steady power — back off a touch before it leaves the band", "Your heart rate is rising, ease off", "HR_RISING")
                    if e.type != .NONE { allGoodSince = nil }
                    return e
                }
                if let s = steadyCue() { allGoodSince = nil; return s }
                let surging = pwZone != nil && pwZone! >= targetZone + 1 && pb == .above
                if surging || spiking { if surgeSince == nil { surgeSince = now } } else { surgeSince = nil }
                if !surging && !spiking { effort = nil }
                else if spiking, now - (surgeSince ?? now) >= 3_000 {
                    effort = emit(now, .SURGE, "SMOOTH OUT THE SURGES", "Power jumped to \(rawPw ?? 0) W — more than 1.5× the top of the target (\(Int((pHiW ?? 0).rounded())) W). Surges cost more than steady watts; keep the pressure even", "Smooth out the surges", "PW_SPIKE")
                } else if surging, now - (surgeSince ?? now) >= c.surgeHoldMs {
                    effort = emit(now, .EASE_OFF, "EASE OFF", "Power surging (zone \(pwZone ?? 0)) — heart rate will follow", "Ease off, power is surging", "PW_SURGE")
                } else { effort = hold("PW_SURGE_HOLD") }
            case .below?:
                surgeSince = nil
                if pb == .on || pb == .above { effort = hold("HR_LAG_HOLD") }
                else if grace { effort = hold("TRANSITION_GRACE") }
                else if hrBand.held(now, c.effortHoldMs) { effort = emit(now, .PUSH_HARDER, "PUSH A LITTLE HARDER", "Heart rate \(hr) below target \(bandText)", "Push a little harder", "HR_BELOW") }
                else { effort = hold() }
            case nil: effort = nil
            }
        } else if let pw, c.ftpAssumed {
            effort = relativeEffort(now, pw, rawPw, coasting, stopped)
        } else if pw != nil {
            switch pb {
            case .above?: effort = pwBand.held(now, c.powerHoldMs) ? emit(now, .EASE_OFF, "EASE OFF", "Power above target — zone \(pwZone ?? 0), aim for \(targetZone)", "Ease off", "PW_ABOVE") : hold()
            case .below?: effort = grace ? hold("TRANSITION_GRACE") : pwBand.held(now, c.powerHoldMs) ? emit(now, .PUSH_HARDER, "PUSH A LITTLE HARDER", "Power below target — zone \(pwZone ?? 0), aim for \(targetZone)", "Push a little harder", "PW_BELOW") : hold()
            case .on?: effort = steadyCue()
            case nil: effort = nil
            }
        } else {
            if coasting { effort = hold("COASTING") }
            else if c.effortSource == .power { effort = info(now, .NO_POWER, "PEDAL UNDER LOAD", "Power reads 0 with no load — effort coaching needs pedaling resistance", "", "NO_POWER") }
            else { effort = sensorPoor(now, cad, stopped) }
        }
        if let e = effort { if e.type != .NONE { allGoodSince = nil }; return e }

        // ---- 6. cadence hints ----
        let effortOk = hb == .on || (hr == nil && pb == .on) || (hr == nil && pw == nil)
        if effortOk, !stopped, !coasting {
            if let cc = cadenceCue(now, cad, phase) { if cc.type != .NONE { allGoodSince = nil }; return cc }
            let cv = cadT.cv()
            if c.cadenceEnabled, let k = cad, k > 0, let cv, cv > 0.12, cadT.reversals() >= 8, (hb == .on || (hr == nil && pb == .on)) {
                let e = emit(now, .PEDAL_FASTER, "KEEP YOUR CADENCE STEADY", "Cadence varied ±\(Int((cv * 100).rounded())) % over the last minute while effort was fine — settle into one rhythm", "Keep your cadence steady", "CAD_UNEVEN")
                if e.type != .NONE { allGoodSince = nil; return e }
            }
        }

        // ---- 7. all good ----
        if stopped || coasting { allGoodSince = nil; return .none }
        let effortKnown = hb == .on || (hr == nil && pb == .on)
        return keepIfGood(now, phase, effortKnown)
    }

    // MARK: helpers
    private func hrBounds(_ zone: Int) -> (Double, Double) {
        let b = config.hrZoneBounds
        let lo = zone <= 1 ? 0.0 : b[min(b.count - 1, max(0, zone - 2))]
        let hi = zone - 1 < b.count ? b[zone - 1] : 2.0
        return (lo, hi)
    }
    private func powerBounds(_ zone: Int) -> (Double, Double) {
        let up: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
        let lo = zone <= 1 ? 0.0 : up[zone - 2]
        let hi = zone - 1 < up.count ? up[zone - 1] : 9.0
        return (lo, hi)
    }
    private func zoneOf(_ frac: Double, _ bounds: [Double]) -> Int { for (i, b) in bounds.enumerated() where frac <= b { return i + 1 }; return bounds.count + 1 }

    private func safety(_ now: Int64, _ hb: Band?, _ hrZone: Int?, _ targetHrZone: Int) -> CoachCue? {
        if hb == .above, let z = hrZone, z >= targetHrZone + 2, hrBand.held(now, 5_000) {
            return emit(now, .EASE_OFF, "EASE OFF", "Heart rate zone \(z) — well above target, back off", "Ease off", "HR_SAFETY")
        }
        return nil
    }

    private func relativeEffort(_ now: Int64, _ pw: Int, _ pwRaw: Int?, _ coasting: Bool, _ stopped: Bool) -> CoachCue? {
        if refWin.count < 120 || coasting || stopped { return nil }
        let ref = Double(refWin.reduce(0) { $0 + $1.1 }) / Double(refWin.count)
        let m60: Double? = minWin.count >= 30 ? Double(minWin.reduce(0) { $0 + $1.1 }) / Double(minWin.count) : nil
        if let r = pwRaw, Double(r) > ref * 1.6 {
            if spikeSince == nil { spikeSince = now }
            if now - (spikeSince ?? now) >= 3_000 {
                spikeSince = nil
                let e = emit(now, .SURGE, "SMOOTH OUT THE SURGES", "Power jumped to \(r) W — well above your steady \(Int(ref.rounded())) W. Surges cost more than steady watts", "Smooth out the surges", "REL_SPIKE")
                return e.type != .NONE ? e : nil
            }
        } else { spikeSince = nil }
        if let m = m60, m < ref * 0.85 {
            if lowSinceMs == nil { lowSinceMs = now }
            if now - (lowSinceMs ?? now) >= 60_000 {
                let e = emit(now, .PACE, "YOUR POWER IS DROPPING. TRY TO KEEP A STEADY RHYTHM", "Last minute \(Int(m.rounded())) W against your steady \(Int(ref.rounded())) W — not a zone, your own pace", "Your power is dropping, try to keep a steady rhythm", "REL_DROP")
                return e.type != .NONE ? e : nil
            }
        } else { lowSinceMs = nil }
        if let m = m60, abs(m - ref) <= ref * 0.10 {
            steadySec += 1
            let mn = steadySec / 60
            if mn >= 10, mn % 10 == 0, mn != lastMilestoneMin {
                let e = emit(now, .KEEP_IT_UP, "YOU HAVE BEEN RIDING STEADILY FOR \(mn) MINUTES. KEEP GOING", "Steady at about \(Int(ref.rounded())) W", "You have been riding steadily for \(mn) minutes, keep going", "REL_MILESTONE")
                if e.type != .NONE { lastMilestoneMin = mn; return e }
            }
            let k = keepIfGood(now, .MAIN, true)
            return k.type != .NONE ? k : nil
        } else { steadySec = 0; allGoodSince = nil }
        return nil
    }

    private func sensorPoor(_ now: Int64, _ cad: Int?, _ stopped: Bool) -> CoachCue? {
        if !noSensorsSaid {
            noSensorsSaid = true; lastType = .NO_HR; lastEmitMs = now
            return CoachCue(type: .NO_HR, headline: "NO EFFORT SENSORS", detail: "Coaching on cadence and pace until a power meter or strap reports", spoken: "", reason: "NO_SIGNAL", action: .NO_SIGNAL, sources: "sensors", live: liveText(), short: "No effort sensors", why: "coaching on cadence and pace")
        }
        if stopped { return nil }
        let sinceMain: Int64
        if let m = mainSinceMs { sinceMain = m } else { mainSinceMs = now; sinceMain = now }
        if speedWin.count >= 90 {
            let v = speedWin.map { $0.1 }.filter { $0 > 3.0 }
            if v.count >= 60 {
                let m = v.reduce(0, +) / Double(v.count); let cv = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot() / m
                if cv > 0.25, (cad ?? 0) > 0 {
                    let e = emit(now, .PACE, "TRY TO HOLD A STEADIER PACE", "Speed varied ±\(Int((cv * 100).rounded())) % over two minutes (terrain and wind count, so this is about rhythm, not effort)", "Try to hold a steadier pace", "SPEED_UNEVEN")
                    return e.type != .NONE ? e : nil
                }
            }
        }
        let mn = Int((now - sinceMain) / 60_000) / 10 * 10
        if mn >= 10, mn > lastMilestoneMin {
            let e = emit(now, .KEEP_IT_UP, "YOU HAVE BEEN RIDING FOR \(mn) MINUTES. KEEP GOING", "Time-based check-in — no effort sensor to judge intensity", "You have been riding for \(mn) minutes, keep going", "TIME_MILESTONE")
            if e.type != .NONE { lastMilestoneMin = mn; return e }
        }
        return nil
    }

    private func cadenceCue(_ now: Int64, _ cad: Int?, _ phase: Phase) -> CoachCue? {
        let c = config
        guard c.cadenceEnabled, let cad, cad > 0, phase != .COOLDOWN else { cadState = nil; return nil }
        let lo = c.cadenceLow, hi = c.cadenceHigh
        let next: Band
        switch cadState {
        case .below?: next = cad >= lo + c.cadenceHysteresis ? .on : .below
        case .above?: next = cad <= hi - c.cadenceHysteresis ? .on : .above
        default:
            let h = cadState == .on ? c.cadenceHysteresis : 0
            next = cad < lo - h ? .below : cad > hi + h ? .above : .on
        }
        if next != cadState { cadState = next; cadSince = now }
        if now - cadSince < c.cadenceHoldMs { return next == .on ? nil : hold() }
        switch next {
        case .below: return emit(now, .PEDAL_FASTER, "PEDAL FASTER", "Lift cadence toward \(lo)–\(hi) rpm", "Pedal faster", "CAD_LOW")
        case .above: return emit(now, .PEDAL_SLOWER, "PEDAL SLOWER", "Ease cadence toward \(lo)–\(hi) rpm", "Pedal slower", "CAD_HIGH")
        case .on: return nil
        }
    }

    private func keepIfGood(_ now: Int64, _ phase: Phase, _ effortKnown: Bool) -> CoachCue {
        if phase != .MAIN || !effortKnown { allGoodSince = nil; return .none }
        if allGoodSince == nil { allGoodSince = now; keepArmed = true }
        if now - (allGoodSince ?? now) < config.keepHoldMs { return .none }
        let due = keepArmed || now - lastEmitMs >= config.keepRepeatMs
        if !due { return .none }
        let cue = emit(now, .KEEP_IT_UP, "KEEP IT UP", "Effort on target", "Keep it up", "ALL_GOOD")
        if cue.type != .NONE { keepArmed = false; if cue.action == .RECOVERED { recoveredForMs = easeAtMs } }
        return cue
    }

    private func hold(_ reason: String = "") -> CoachCue { .none }

    private func announce(_ now: Int64, _ phase: Phase, _ type: CueType, _ head0: String, _ detail0: String, _ spoken0: String, _ reason: String) -> CoachCue {
        let w = action(type, head0, detail0, spoken0, reason)
        if announcedPhase == phase { return .none }
        announcedPhase = phase; allGoodSince = nil; keepArmed = true
        lastType = type; lastEmitMs = now
        let (sh, why) = shortWording(w, reason)
        return CoachCue(type: type, headline: w.head, detail: w.detail, spoken: w.spoken, reason: reason, action: w.action, sources: w.sources, live: liveText(), short: sh, why: why)
    }

    private func info(_ now: Int64, _ type: CueType, _ head: String, _ detail: String, _ spoken: String, _ reason: String) -> CoachCue {
        if type == lastType, now - lastEmitMs < config.infoRepeatMs { return .none }
        lastType = type; lastEmitMs = now
        let (sh, why) = shortWording(Worded(action: .NO_SIGNAL, head: head, detail: detail, spoken: spoken, sources: "sensors"), reason)
        return CoachCue(type: type, headline: head, detail: detail, spoken: spoken, reason: reason, action: .NO_SIGNAL, sources: "sensors", live: liveText(), short: sh, why: why)
    }

    private struct Worded { var action: CoachAction; var head: String; var detail: String; var spoken: String; var sources: String }

    /// Gear intelligence: the same effort decision, said as what to do with the bike.
    private func action(_ type: CueType, _ head: String, _ detail: String, _ spoken: String, _ reason: String) -> Worded {
        let c = config; let cad = lastCad, pw = lastPw, hr = lastHr
        let gearOk = !lastStopped && !lastCoasting
        let cadLow = gearOk && cad != nil && cad! > 0 && cad! < c.cadenceLow; let cadHigh = gearOk && cad != nil && cad! > c.cadenceHigh
        let pwLow = lastPb == .below || (pw != nil && Double(pw!) < Double(c.ftpW) * 0.55)
        var src = ""
        if reason.hasPrefix("HR") || reason == "COOLDOWN_RAMP" || reason == "COOLDOWN_HR_ABOVE" { src += "HR" }
        if reason.hasPrefix("PW") { src += "power" }
        if reason.hasPrefix("CAD") { src += "cadence" }
        let srcOrHR = src.isEmpty ? "HR" : src
        switch type {
        case .EASE_OFF:
            if head == "WIND DOWN" { return Worded(action: .WIND_DOWN, head: "WIND DOWN", detail: detail, spoken: spoken, sources: "HR") }
            if reason == "HR_RISING" { return Worded(action: .HR_RISING_EASE, head: head, detail: detail, spoken: spoken, sources: "HR trend + power") }
            if cadLow, !pwLow { return Worded(action: .EASIER_GEAR, head: "SHIFT TO AN EASIER GEAR", detail: "\(detail) · cadence \(cad ?? 0) rpm with a heavy gear: less resistance, smoother spin, and the effort comes down", spoken: "Shift to an easier gear", sources: "\(src) + cadence") }
            return Worded(action: .REDUCE_PRESSURE, head: "REDUCE PRESSURE ON THE PEDALS", detail: detail, spoken: "Reduce pressure on the pedals", sources: srcOrHR)
        case .PUSH_HARDER:
            if cadHigh, (pwLow || pw == nil) { return Worded(action: .HARDER_GEAR, head: "SHIFT TO A HARDER GEAR", detail: "\(detail) · cadence \(cad ?? 0) rpm is high with little resistance — add gear, keep the spin", spoken: "Shift to a harder gear", sources: "\(src) + cadence") }
            return Worded(action: .INCREASE_EFFORT, head: "INCREASE YOUR EFFORT SLIGHTLY", detail: cadLow ? "\(detail) · cadence is low too, so press a little more rather than changing gear" : detail, spoken: "Increase your effort slightly", sources: srcOrHR)
        case .PEDAL_FASTER:
            return head.hasPrefix("KEEP") ? Worded(action: .KEEP_CADENCE_STEADY, head: head, detail: detail, spoken: spoken, sources: "cadence") : Worded(action: .PEDAL_FASTER, head: "PEDAL A LITTLE FASTER", detail: "Easier gear, same effort — \(detail)", spoken: "Pedal a little faster", sources: "cadence")
        case .PEDAL_SLOWER: return Worded(action: .PEDAL_SLOWER, head: "SLOW YOUR PEDALLING", detail: "Harder gear, same effort — \(detail)", spoken: "Slow your pedalling", sources: "cadence")
        case .PACE: return reason == "REL_DROP" ? Worded(action: .POWER_DROPPING, head: head, detail: detail, spoken: spoken, sources: "power") : Worded(action: .STEADY_PACE, head: head, detail: detail, spoken: spoken, sources: "speed + cadence")
        case .KEEP_IT_UP:
            if reason == "REL_MILESTONE" || reason == "TIME_MILESTONE" { return Worded(action: .STEADY_MILESTONE, head: head, detail: detail, spoken: spoken, sources: reason == "REL_MILESTONE" ? "power" : "time") }
            if reason == "ALL_GOOD", config.ftpAssumed, hr == nil, pw != nil { return Worded(action: .HOLD_PACE, head: "GOOD PACE. HOLD THIS EFFORT", detail: "Steady against your own output — no zone claimed", spoken: "Good pace, hold this effort", sources: "power") }
            if easeAtMs != nil, easeAtMs != recoveredForMs { return Worded(action: .RECOVERED, head: "GOOD — BACK ON TARGET", detail: "\(hr != nil ? "Heart rate" : "Power") settled back into the band after easing off — hold this", spoken: "Good, back on target", sources: hr != nil ? "HR" : "power") }
            if pw != nil, lastPb == .on { return Worded(action: .HOLD_PACE, head: "HOLD THIS PACE", detail: "Power and heart rate on target", spoken: "Hold this pace", sources: "HR + power") }
            return Worded(action: .STABLE_MAINTAIN, head: "YOUR EFFORT IS STABLE. MAINTAIN THIS RHYTHM", detail: detail, spoken: "Your effort is stable, maintain this rhythm", sources: hr != nil ? "HR" : "power")
        case .COOLDOWN: return Worded(action: .START_COOLDOWN, head: "START YOUR COOLDOWN", detail: detail, spoken: "Start your cooldown", sources: "phase")
        case .SURGE: return Worded(action: .SMOOTH_SURGES, head: head, detail: detail, spoken: spoken, sources: "power")
        case .STEADY: return Worded(action: .STEADY_EFFORT, head: head, detail: detail, spoken: spoken, sources: hr != nil ? "power + HR" : "power")
        case .WARMUP: return Worded(action: .WARM_UP, head: head, detail: detail, spoken: spoken, sources: "phase")
        case .RECOVER: return Worded(action: .RECOVER, head: head, detail: detail, spoken: spoken, sources: "phase")
        case .NO_HR, .NO_POWER: return Worded(action: .NO_SIGNAL, head: head, detail: detail, spoken: spoken, sources: "sensors")
        case .QUIET: return Worded(action: .QUIET, head: head, detail: detail, spoken: spoken, sources: "")
        default: return Worded(action: .NONE, head: head, detail: detail, spoken: spoken, sources: src)
        }
    }

    private func shortWording(_ w: Worded, _ reason: String) -> (String, String) {
        let hrv = lastHr.map { "HR \($0)" } ?? "", cadv = lastCad.map { "\($0) rpm" } ?? ""
        let pwReason = reason.hasPrefix("PW") || reason.hasPrefix("RECOVERY_PW")
        func cap(_ s: String) -> String { let l = s.lowercased(); return l.prefix(1).uppercased() + l.dropFirst() }
        switch w.action {
        case .EASIER_GEAR: return ("Shift to an easier gear", "\(cadv) low · \(pwReason ? "power" : "HR") above target")
        case .HARDER_GEAR: return ("Shift to a harder gear", "\(cadv) high · \(pwReason ? "power" : "HR") below target")
        case .REDUCE_PRESSURE: return (pwReason ? "Ease off — power above target" : "Ease off — HR above target", pwReason ? "\(lastPw ?? 0) W vs \(lastPwBand)" : "\(hrv) vs \(lastHrBand)")
        case .INCREASE_EFFORT: return (pwReason ? "Push a little — power below target" : "Push a little — HR below target", pwReason ? "\(lastPw ?? 0) W vs \(lastPwBand)" : "\(hrv) vs \(lastHrBand)")
        case .HR_RISING_EASE: return ("HR rising — ease off", "climbing at steady power")
        case .PEDAL_FASTER: return ("Pedal a little faster", "\(cadv) · below \(config.cadenceLow) rpm")
        case .PEDAL_SLOWER: return ("Slow your pedalling", "\(cadv) · above \(config.cadenceHigh) rpm")
        case .KEEP_CADENCE_STEADY: return ("Keep your cadence steady", "rhythm uneven over the last minute")
        case .HOLD_PACE: return config.ftpAssumed && lastHr == nil ? ("Good pace — hold this effort", "steady against your own output") : ("Hold this pace", "power and HR on target")
        case .STABLE_MAINTAIN: return ("Maintain this rhythm", "effort stable · on target")
        case .START_COOLDOWN: return ("Start your cooldown", "ceiling comes down gradually")
        case .WIND_DOWN: return ("Wind down", "HR above the cool-down ceiling")
        case .WARM_UP: return ("Warm up — easy spinning", "no 'push' until the main block")
        case .RECOVER: return ("Recover — easy spin", "recovery interval")
        case .QUIET: return ("Coach quiet", "said 3× — speaks again on change")
        case .SMOOTH_SURGES: return ("Smooth out the surges", "power spikes well above target")
        case .STEADY_EFFORT: return ("Hold a steadier effort", "power swinging around the target")
        case .RECOVERED: return ("Good — back on target", lastHr != nil ? "HR settled after easing off" : "power settled after easing off")
        case .NO_SIGNAL: return ("No effort signal", reason == "NO_POWER" ? "pedal under load" : "no heart rate, no loaded power")
        case .SENSOR_LOST: return (cap(w.head), w.detail)
        case .POWER_DROPPING: return ("Power dropping — keep a steady rhythm", "\(lastPw.map(String.init) ?? "—") W vs your steady pace")
        case .STEADY_MILESTONE: return (cap(String(w.head.split(separator: ".").first ?? Substring(w.head))), "keep going")
        case .STEADY_PACE: return ("Try to hold a steadier pace", "speed uneven — rhythm, not effort")
        case .NONE: return (cap(w.head), String((w.detail.components(separatedBy: " — ").first ?? w.detail).prefix(46)))
        }
    }

    private func liveText() -> String {
        [lastHr.map { "HR \($0)" }, lastPw.map { "\($0) W" }, (lastCad ?? 0) > 0 ? "\(lastCad!) rpm" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func emit(_ now: Int64, _ type: CueType, _ head0: String, _ detail0: String, _ spoken0: String, _ reason: String) -> CoachCue {
        let w = action(type, head0, detail0, spoken0, reason)
        let since = now - lastEmitMs
        if type == lastType, type == .KEEP_IT_UP, config.keepRepeatMs <= 0 { return .none }
        if type == lastType, since < (type == .KEEP_IT_UP ? config.keepRepeatMs : config.sameRepeatMs) { return .none }
        if type != lastType, since < config.minAlertMs { return .none }
        if type != .KEEP_IT_UP, let t = lastEmitByType[type], now - t < config.sameRepeatMs { return .none }
        if config.backoff, type == lastType, type != .KEEP_IT_UP {
            repeatCount += 1
            if repeatCount >= 3 {
                if repeatCount == 3 {
                    lastEmitMs = now; quietSinceMs = now
                    return CoachCue(type: .QUIET, headline: "COACH QUIET", detail: "\(w.head) said 3 times without a change — going quiet until something changes (5 min max)", spoken: "", reason: "BACKOFF", action: .QUIET, sources: "", live: liveText(), short: "Coach quiet", why: "said 3× — speaks again on change")
                }
                if now - quietSinceMs < config.quietMs { return .none }
                repeatCount = 0
            }
        } else { repeatCount = 0 }
        lastType = type; lastEmitMs = now; lastEmitByType[type] = now
        if type == .EASE_OFF || type == .SURGE { easeAtMs = now }
        let (sh, why) = shortWording(w, reason)
        return CoachCue(type: type, headline: w.head, detail: w.detail, spoken: w.spoken, reason: reason, action: w.action, sources: w.sources, live: liveText(), short: sh, why: why)
    }
}

// MARK: - Cyclift 1.0 additions (additive: the engine and its vectors above are unchanged)

/// Display-side rate limit for the on-screen coach panel. The engine already spaces its own cues (minAlertMs,
/// sameRepeatMs); the gate additionally HOLDS the cue on screen for at least `holdMs` (15 s) so the instruction does
/// not flicker between rules. A newer cue that arrives during the hold is kept as `pending` and shown when the hold
/// ends (if it is still recent). Only clearly necessary cues cut the hold short: a safety ease-off (heart rate two
/// zones above target), a sensor that dropped out, and phase changes (warm-up / main / recovery / cool-down).
struct CueGate {
    var holdMs: Int64 = 15_000
    /// A pending cue older than this when the hold ends is stale and dropped (the engine says it again if it still applies).
    var pendingMaxAgeMs: Int64 = 20_000
    private(set) var shown: CoachCue = .none
    private(set) var shownAtMs: Int64? = nil
    private(set) var pending: CoachCue? = nil
    private var pendingAtMs: Int64 = 0

    static func isUrgent(_ c: CoachCue) -> Bool {
        switch c.type {
        case .SENSOR_LOST, .WARMUP, .COOLDOWN, .RECOVER, .WORK: return true
        default: return c.reason == "HR_SAFETY" || c.reason == "PHASE_MAIN"
        }
    }

    /// Feed every engine result (including `.none`) once per second. Returns true when the shown cue changed.
    @discardableResult
    mutating func offer(_ c: CoachCue, nowMs: Int64) -> Bool {
        if c.type != .NONE {
            let held = shownAtMs.map { nowMs - $0 < holdMs } ?? false
            if !held || Self.isUrgent(c) || shown.type == .NONE { show(c, nowMs); return true }
            pending = c; pendingAtMs = nowMs
            return false
        }
        if let p = pending, let t = shownAtMs, nowMs - t >= holdMs {
            pending = nil
            if nowMs - pendingAtMs <= pendingMaxAgeMs { show(p, nowMs); return true }
        }
        return false
    }
    mutating func reset() { shown = .none; shownAtMs = nil; pending = nil; pendingAtMs = 0 }
    private mutating func show(_ c: CoachCue, _ now: Int64) { shown = c; shownAtMs = now; pending = nil }
}

/// Plain-language instruction for the ride-screen coach panel, from the engine's action. Wording only — the decision
/// is the engine's. `targetZone` lets an ease-off name the zone the rider is returning to.
enum CoachWording {
    static func instruction(_ c: CoachCue, targetZone: Int) -> String {
        switch c.action {
        case .STABLE_MAINTAIN, .HOLD_PACE, .STEADY_MILESTONE: return "Maintain current effort"
        case .RECOVERED: return "Good — back on target, maintain it"
        case .PEDAL_FASTER: return "Increase cadence slightly"
        case .PEDAL_SLOWER: return "Lower cadence slightly"
        case .EASIER_GEAR: return "Shift to an easier gear"
        case .HARDER_GEAR: return "Shift to a harder gear"
        case .REDUCE_PRESSURE, .HR_RISING_EASE: return "Reduce intensity to return to Zone \(min(5, max(1, targetZone)))"
        case .INCREASE_EFFORT: return "Increase effort slightly"
        case .RECOVER: return "Recover for the next interval"
        case .WIND_DOWN, .START_COOLDOWN: return "Ease down — cool-down"
        case .WARM_UP: return "Warm up — easy spinning"
        default: return c.short.isEmpty ? c.headline : c.short
        }
    }
    /// The rule behind a cue, with the values the engine used. Never invents a reading: values come from the cue.
    static func rule(_ c: CoachCue) -> String {
        switch c.reason {
        case "HR_ABOVE": return "Heart rate stayed above the target band for at least 8 s."
        case "HR_BELOW": return "Heart rate stayed below the target band for at least 8 s while power was not already on target."
        case "HR_SAFETY": return "Heart rate is two or more zones above the target — safety rule, shown at once."
        case "HR_RISING": return "Heart rate is climbing about 6 bpm/min or more while power stays steady, near the top of the band."
        case "PW_ABOVE": return "Smoothed power stayed above the target zone for at least 2 s."
        case "PW_BELOW": return "Smoothed power stayed below the target zone for at least 2 s."
        case "PW_SURGE", "PW_SPIKE", "REL_SPIKE": return "Power surged well above the target; surges cost more than steady watts."
        case "PW_UNSTEADY": return "Average power is on target but swung more than ±20 % over the last minute."
        case "REL_DROP": return "Last-minute power is more than 15 % below your own steady output for a minute."
        case "CAD_LOW": return "Cadence stayed below your range for at least 5 s while effort was fine."
        case "CAD_HIGH": return "Cadence stayed above your range for at least 5 s while effort was fine."
        case "CAD_UNEVEN": return "Cadence varied more than ±12 % over the last minute."
        case "ALL_GOOD": return "Effort has been inside the target band for at least 5 s."
        case "SPEED_UNEVEN": return "Speed varied more than ±25 % over two minutes (terrain and wind count)."
        case "TIME_MILESTONE", "REL_MILESTONE": return "Time-based check-in every 10 minutes."
        case "PHASE_WARMUP": return "The first 5 minutes are a warm-up: no 'push' cues yet."
        case "PHASE_COOLDOWN", "COOLDOWN_RAMP", "COOLDOWN_HR_ABOVE": return "Cool-down: the ceiling comes down gradually; no more 'push' cues."
        case "PHASE_RECOVERY", "RECOVERY_PW_ABOVE": return "Recovery interval of the workout: spin easy so the next interval counts."
        case "PHASE_MAIN": return "The main block of the workout started."
        case "POWER_LOST", "HR_LOST": return "A sensor stopped reporting; the coach continues from what is still live."
        case "NO_SIGNAL", "NO_POWER": return "No heart rate and no loaded power: the coach cannot judge effort."
        default: return "Rule-based coach decision."
        }
    }
}
