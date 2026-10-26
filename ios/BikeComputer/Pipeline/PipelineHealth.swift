import Foundation

// PIPELINE HEALTH MODEL (ios/PIPELINE_HEALTH.md). Pure value types and rules — no CoreBluetooth, HealthKit or UI —
// so every rule is unit-tested. "Bluetooth connected" is never success: a path is LIVE only when a valid measurement
// is younger than its freshness limit (power / cadence 3 s, heart rate 6 s) and is actually displayed.

enum PipelineStage: String, CaseIterable, Codable {
    case discovered, connected, subscribed, receiving, valid, forwarded, displayed
    var title: String {
        switch self {
        case .discovered: return "Discovered"; case .connected: return "Connected"; case .subscribed: return "Subscribed"
        case .receiving: return "Receiving packets"; case .valid: return "Valid measurement"; case .forwarded: return "Forwarded"; case .displayed: return "Displayed"
        }
    }
}

enum StageResult: String, Codable { case ok, pending, failed, notApplicable, unknown }

struct StageStatus: Equatable, Codable {
    var stage: PipelineStage
    var result: StageResult
    var detail: String = ""
}

/// Overall state of one path, ordered by severity (the top message is the most severe wanted path).
enum PipelineHealth: Int, Codable, Comparable {
    case notSetUp = 0, idle = 1, live = 2, waiting = 3, recovering = 4, stale = 5, noData = 6, failed = 7
    static func < (a: PipelineHealth, b: PipelineHealth) -> Bool { a.rawValue < b.rawValue }
    /// Shown as a problem (amber / red) at the top of the Ride and Connections screens.
    var needsMessage: Bool { self >= .waiting }
    var title: String {
        switch self {
        case .notSetUp: return "not set up"; case .idle: return "ready"; case .live: return "live"; case .waiting: return "waiting for data"
        case .recovering: return "reconnecting"; case .stale: return "data stale"; case .noData: return "no data"; case .failed: return "failed"
        }
    }
}

struct PipelineReport: Equatable, Codable, Identifiable {
    var id: String              /* "board.power", "board.hr", "board.csc", "watch.hr", "ble.<n>" */
    var title: String           /* "Power meter → BikeComputer → iPhone" — never a device or person name */
    var stages: [StageStatus]
    var health: PipelineHealth
    var message: String         /* ONE short line, e.g. "Power meter connected — waiting for data" */
    var note: String? = nil     /* e.g. "board firmware too old for detailed diagnostics" */
    func stage(_ s: PipelineStage) -> StageStatus? { stages.first { $0.stage == s } }
}

enum Freshness {
    static let powerS: TimeInterval = 3
    static let cadenceS: TimeInterval = 3
    static let heartRateS: TimeInterval = 6
    /// Time a connected source gets to deliver its first reading before "waiting" becomes "no readings received".
    static let graceS: TimeInterval = 10
    static func isFresh(_ at: Date?, now: Date, limit: TimeInterval) -> Bool { guard let t = at else { return false }; return now.timeIntervalSince(t) <= limit }
}

// MARK: - inputs (snapshots the monitor takes once per second)

struct BoardInputs: Equatable {
    var remembered = false
    var autoConnect = true
    var linkReady = false                 /* DeviceLink.state == .ready (INFO read over the encrypted link) */
    var attempting = false                /* a connection attempt is in progress */
    var failureReason: String? = nil
    var needsRepair = false
    var readyAt: Date? = nil
    var liveAt: Date? = nil               /* last LIVE notification */
    var live: BCLink.Live? = nil
    var liveNotifying: Bool? = nil        /* iOS confirmed the Live subscription (nil = no answer yet) */
    var fw: String? = nil
    var diag: [UInt8: DiagEntry] = [:]

    struct DiagEntry: Equatable {
        var diag: BCLink.SensorDiag
        var at: Date
        var stageSince: Date
    }
    func liveFresh(_ now: Date) -> Bool { Freshness.isFresh(liveAt, now: now, limit: 3) }
    /// SENSOR_DIAG exists from firmware 0.7.2 (spec 1.2.2).
    var firmwareHasSensorDiag: Bool { !diag.isEmpty || BoardInputs.version(fw, atLeast: [0, 7, 2]) }
    static func version(_ fw: String?, atLeast min: [Int]) -> Bool {
        guard let fw else { return false }
        let digits = fw.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? ""
        let parts = digits.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return false }
        for i in 0..<max(parts.count, min.count) {
            let a = i < parts.count ? parts[i] : 0, b = i < min.count ? min[i] : 0
            if a != b { return a > b }
        }
        return true
    }
}

struct WatchInputs: Equatable {
    var enabled = true
    var paired = false
    var appInstalled = false
    var reachable = false
    var mirrorActive = false
    var workoutState = "idle"
    var workoutStateAt: Date? = nil
    var lastDeliveryAt: Date? = nil
    var lastSampleAt: Date? = nil         /* sample time of the last ACCEPTED reading */
    var hrNow: Int? = nil                 /* WatchHRIngest.current(now:) */
    var watchWorkoutAuth: String? = nil
    var rideActive = false
    var rideStartedAt: Date? = nil
    var startRequestedAt: Date? = nil
    var boardLinkReady = false
    var boardLiveFresh = false
    var boardHRSource: BCLink.Source? = nil
    var boardHR: Int? = nil
    var hrSentToBoardAt: Date? = nil
    var displayed = false
}

struct DirectInputs: Equatable {
    enum Link: String { case disconnected, connecting, connected }
    var index = 1
    var kindTitle = "Bluetooth sensor"    /* generic kind, never the sensor's advertised name */
    var freshS: TimeInterval = 3
    var radioOn = true
    var link: Link = .disconnected
    var connectedAt: Date? = nil
    var subscribed: Bool? = nil
    var subscribeError: String? = nil
    var packets = 0
    var rejected = 0
    var lastPacketAt: Date? = nil
    var lastValidAt: Date? = nil
    var displayed = false
    /// Outside a ride a sleeping sensor is normal (idle); during a ride it is being reconnected.
    var rideActive = false
}

// MARK: - rules

enum PipelineRules {
    private static func st(_ s: PipelineStage, _ r: StageResult, _ d: String = "") -> StageStatus { StageStatus(stage: s, result: r, detail: d) }
    private static func all(_ r: StageResult, _ d: String = "") -> [StageStatus] { PipelineStage.allCases.map { st($0, r, d) } }

    // MARK: sensor on the board → BikeComputer → iPhone
    /// `metricPresent`: the board's LIVE carries this sensor's value (power: tag 01; strap: tag 05 with source strap).
    static func boardSensor(_ sensor: BCLink.SensorDiag.Sensor, board b: BoardInputs, metricPresent: Bool, displayed: Bool, wanted: Bool, now: Date) -> PipelineReport {
        let id: String, title: String, what: String
        switch sensor {
        case .power: id = "board.power"; title = "Power meter → BikeComputer → iPhone"; what = "Power meter"
        case .hrStrap: id = "board.hr"; title = "Heart-rate strap → BikeComputer → iPhone"; what = "Heart-rate strap"
        case .csc: id = "board.csc"; title = "Speed / cadence sensor → BikeComputer → iPhone"; what = "Speed / cadence sensor"
        }
        let metricWord = sensor == .power ? "power" : sensor == .hrStrap ? "heart-rate" : "speed / cadence"
        var r = PipelineReport(id: id, title: title, stages: all(.unknown), health: .notSetUp, message: "")

        guard b.remembered || b.linkReady else { r.stages = all(.notApplicable, "no BikeComputer set up"); return r }
        // phone ↔ board link first: without it nothing on the board can be seen from here
        guard b.linkReady else {
            r.stages = all(.unknown, "BikeComputer not connected")
            r.stages[r.stages.firstIndex { $0.stage == .forwarded }!] = st(.forwarded, .failed, "BikeComputer not connected to the phone")
            if b.needsRepair { r.health = .failed; r.message = "BikeComputer pairing lost — open Connections › BikeComputer › Repair" }
            else if b.autoConnect { r.health = .recovering; r.message = "BikeComputer not connected — reconnecting automatically" }
            else { r.health = .notSetUp; r.message = "BikeComputer link switched off" }
            return r
        }
        let liveFresh = b.liveFresh(now)
        let sinceReady = b.readyAt.map { now.timeIntervalSince($0) } ?? 0

        // board-side stages: SENSOR_DIAG when the firmware has it, else what LIVE tells (meter_link) for the power meter
        var stages: [PipelineStage: StageStatus] = [:]
        var health: PipelineHealth = .live
        var message = ""
        var note: String? = nil
        if let e = b.diag[sensor.rawValue], let stage = e.diag.stage {
            let s = stage.rawValue
            func ok(_ min: UInt8) -> StageResult { s >= min && stage != .error ? .ok : .pending }
            stages[.discovered] = st(.discovered, stage == .notPaired ? .failed : (s >= 2 && stage != .error ? .ok : .pending), stage == .notPaired ? "not paired on the BikeComputer" : stage == .searching ? "board searching" : "")
            stages[.connected] = st(.connected, ok(3))
            stages[.subscribed] = st(.subscribed, ok(4))
            let pk = e.diag.packets.map { "\($0) packets" } ?? ""
            stages[.receiving] = st(.receiving, ok(5), pk)
            stages[.valid] = st(.valid, stage == .valid ? .ok : stage == .stale ? .failed : .pending, stage == .stale ? "no valid measurement for > 3 s" : e.diag.validAgeS.map { String(format: "last valid %.1f s ago", $0) } ?? "")
            let waited = now.timeIntervalSince(max(e.stageSince, b.readyAt ?? e.stageSince))
            switch stage {
            case .notPaired:
                health = wanted ? .failed : .notSetUp
                message = "\(what) not paired on the BikeComputer"
            case .searching, .connecting:
                health = .waiting; message = "\(what) not connected to the BikeComputer — \(sensor == .power ? "pedal to wake it" : "wake it up")"
            case .connected, .subscribed:
                if waited < Freshness.graceS { health = .waiting; message = "\(what) connected — waiting for data" }
                else { health = .noData; message = "\(what) connected — no readings received" }
            case .receiving:
                health = waited < Freshness.graceS ? .waiting : .noData; message = "\(what) connected — no valid readings"
            case .valid:
                health = .live
            case .stale:
                health = .stale; message = "\(what) data stale"
            case .error:
                health = .failed; message = "\(what) error" + (e.diag.lastError.map { ": \($0)" } ?? "")
                stages[.connected] = st(.connected, .failed, e.diag.lastError ?? "error")
            }
        } else {
            note = b.firmwareHasSensorDiag ? "waiting for the board's sensor diagnostics" : "board firmware too old for detailed diagnostics"
            if sensor == .power, let l = b.live, liveFresh {
                // LIVE tag 0E meter_link: 0 off · 1 not paired · 2 searching · 3 connecting · 4 connected · 5 retry · 6 unsupported · 7 stale
                switch l.meterLink {
                case 4, 7:
                    stages[.discovered] = st(.discovered, .ok); stages[.connected] = st(.connected, .ok)
                    stages[.subscribed] = st(.subscribed, metricPresent ? .ok : .unknown)
                    stages[.receiving] = st(.receiving, metricPresent ? .ok : .unknown)
                    stages[.valid] = st(.valid, metricPresent ? .ok : (l.meterLink == 7 ? .failed : .unknown), l.meterLink == 7 ? "board says stale" : "")
                    if metricPresent { health = .live }
                    else if l.meterLink == 7 { health = .stale; message = "Power meter data stale" }
                    else if sinceReady < Freshness.graceS { health = .waiting; message = "Power meter connected — waiting for data" }
                    else { health = .noData; message = "Power meter connected — no readings received" }
                case 2, 3, 5:
                    stages[.discovered] = st(.discovered, l.meterLink == 2 ? .pending : .ok, l.meterLink == 2 ? "board searching" : "")
                    stages[.connected] = st(.connected, .pending, l.meterLink == 5 ? "board reconnecting" : "")
                    health = .waiting; message = "Power meter not connected to the BikeComputer — pedal to wake it"
                case 1:
                    stages[.discovered] = st(.discovered, .failed, "not paired on the BikeComputer")
                    health = wanted ? .failed : .notSetUp; message = "Power meter not paired on the BikeComputer"
                case 6:
                    stages[.connected] = st(.connected, .failed, "board: meter unsupported")
                    health = .failed; message = "Power meter not supported by the BikeComputer"
                default:
                    health = wanted ? .waiting : .notSetUp; message = "Power meter off on the BikeComputer"
                }
            } else if metricPresent {
                for s in [PipelineStage.discovered, .connected, .subscribed, .receiving, .valid] { stages[s] = st(s, .ok) }
                health = .live
            } else {
                health = .notSetUp      /* strap / CSC without SENSOR_DIAG and without data: nothing to claim either way */
            }
        }

        // board → phone (LIVE) and phone display
        if !liveFresh {
            stages[.forwarded] = st(.forwarded, sinceReady < 3 ? .pending : .failed, b.liveNotifying == false ? "Live subscription refused" : "no LIVE from the board")
            if health != .notSetUp || wanted {
                health = sinceReady < Freshness.graceS ? max(health, .waiting) : .noData
                message = b.liveNotifying == false ? "BikeComputer connected — live data subscription failed" : (sinceReady < Freshness.graceS ? "BikeComputer connected — waiting for data" : "BikeComputer connected — no live data received")
            }
        } else if metricPresent {
            stages[.forwarded] = st(.forwarded, .ok, "in LIVE")
        } else {
            stages[.forwarded] = st(.forwarded, stages[.valid]?.result == .ok ? .failed : .pending, stages[.valid]?.result == .ok ? "valid on the board but missing in LIVE" : "nothing to forward yet")
            if stages[.valid]?.result == .ok { health = .noData; message = "\(what) live on the board — not reaching the phone" }
        }
        stages[.displayed] = st(.displayed, displayed ? .ok : (stages[.forwarded]?.result == .ok ? .failed : .pending), displayed ? "" : "no \(metricWord) value on screen")
        if displayed && health == .live { message = "\(what) live" }
        if !displayed && health == .live { health = metricPresent ? .noData : (wanted ? .waiting : .notSetUp); if message.isEmpty { message = "\(what) connected — waiting for data" } }

        r.stages = PipelineStage.allCases.map { stages[$0] ?? st($0, .unknown) }
        r.health = health; r.message = message; r.note = note
        return r
    }

    // MARK: Apple Watch → iPhone → BikeComputer
    static func watchHR(_ w: WatchInputs, now: Date) -> PipelineReport {
        var r = PipelineReport(id: "watch.hr", title: "Apple Watch → iPhone → BikeComputer", stages: all(.unknown), health: .notSetUp, message: "")
        guard w.enabled, w.paired else { r.stages = all(.notApplicable, w.enabled ? "no watch paired" : "switched off"); return r }
        var s: [PipelineStage: StageStatus] = [:]
        guard w.appInstalled else {
            r.stages = all(.unknown); r.stages[0] = st(.discovered, .failed, "Cyclift not installed on the watch")
            r.health = .failed; r.message = "Install Cyclift on the watch: Watch app on iPhone › Cyclift › Install"
            return r
        }
        let delivering = Freshness.isFresh(w.lastDeliveryAt, now: now, limit: 8)
        let linked = w.mirrorActive || w.reachable || delivering
        let running = w.workoutState == "running" || w.workoutState == "paused"
        let hrFresh = w.hrNow != nil
        s[.discovered] = st(.discovered, .ok)
        s[.connected] = st(.connected, linked ? .ok : .pending, w.mirrorActive ? "workout mirroring" : w.reachable ? "Watch Connectivity" : delivering ? "messages arriving" : "not reachable")
        s[.subscribed] = st(.subscribed, running ? .ok : (w.rideActive ? .failed : .pending), "watch workout \(w.workoutState)")
        s[.receiving] = st(.receiving, Freshness.isFresh(w.lastSampleAt, now: now, limit: Freshness.heartRateS) ? .ok : (running ? .pending : .notApplicable))
        s[.valid] = st(.valid, hrFresh ? .ok : (running ? .pending : .notApplicable), hrFresh ? "\(w.hrNow!) bpm" : "")
        // forwarded: confirmed only by the board's LIVE echo (hr source = Apple Watch)
        if !w.boardLinkReady { s[.forwarded] = st(.forwarded, .notApplicable, "no BikeComputer connected") }
        else if w.boardLiveFresh, w.boardHRSource == .appleWatch, w.boardHR != nil { s[.forwarded] = st(.forwarded, .ok, "board shows source WATCH") }
        else if w.boardLiveFresh, w.boardHRSource == .bleStrap, w.boardHR != nil { s[.forwarded] = st(.forwarded, .notApplicable, "board uses its own strap") }
        else if hrFresh, Freshness.isFresh(w.hrSentToBoardAt, now: now, limit: 3) {
            // sent; the board echoes it in LIVE within a second or two — after the grace time a missing echo is a failure
            let runningFor = w.workoutStateAt.map { now.timeIntervalSince($0) } ?? 0
            s[.forwarded] = runningFor > Freshness.graceS && w.boardLiveFresh ? st(.forwarded, .failed, "sent, but the board does not show it") : st(.forwarded, .pending, "sent, not echoed yet")
        }
        else { s[.forwarded] = st(.forwarded, hrFresh ? .failed : .pending, hrFresh ? "not sent to the board" : "") }
        s[.displayed] = st(.displayed, w.displayed ? .ok : (hrFresh ? .failed : .pending))
        r.stages = PipelineStage.allCases.map { s[$0] ?? st($0, .unknown) }

        if w.watchWorkoutAuth == "denied" {
            r.health = .failed; r.message = "Watch heart rate needs Health permission: iPhone Settings › Health › Data Access & Devices › Cyclift"
        } else if hrFresh {
            r.health = .live; r.message = "Watch heart rate live"
            if s[.forwarded]?.result == .failed {
                r.health = .noData; r.message = "Phone connected — watch heart rate not reaching the BikeComputer"
            }
            if !w.displayed && r.health == .live { r.health = .noData; r.message = "Watch heart rate received — not displayed" }
        } else if running {
            let since = w.workoutStateAt.map { now.timeIntervalSince($0) } ?? Freshness.graceS
            if w.lastSampleAt != nil && !linked { r.health = .recovering; r.message = "Watch not reachable — reconnecting automatically" }
            else if w.lastSampleAt != nil { r.health = .stale; r.message = "Watch heart rate stale" }
            else if since < Freshness.graceS { r.health = .waiting; r.message = "Watch connected — waiting for heart rate" }
            else { r.health = .noData; r.message = "Watch connected — heart rate unavailable" }
        } else if w.rideActive {
            if let t = w.startRequestedAt, now.timeIntervalSince(t) < 20 { r.health = .recovering; r.message = "Starting the watch workout…" }
            else { r.health = .failed; r.message = "Watch workout not running — open Cyclift on the watch and tap Start" }
        } else {
            r.health = .idle; r.message = "Watch ready — the workout starts with the ride"
        }
        return r
    }

    // MARK: direct BLE sensor → iPhone
    static func direct(_ d: DirectInputs, now: Date) -> PipelineReport {
        var r = PipelineReport(id: "ble.\(d.index)", title: "\(d.kindTitle) → iPhone (Bluetooth)", stages: all(.unknown), health: .notSetUp, message: "")
        var s: [PipelineStage: StageStatus] = [:]
        let packetFresh = Freshness.isFresh(d.lastPacketAt, now: now, limit: d.freshS)
        let validFresh = Freshness.isFresh(d.lastValidAt, now: now, limit: d.freshS)
        s[.discovered] = st(.discovered, .ok, "paired on this phone")
        s[.connected] = st(.connected, d.link == .connected ? .ok : .pending, d.link.rawValue)
        s[.subscribed] = st(.subscribed, d.subscribed == true ? .ok : d.subscribed == false ? .failed : (d.link == .connected ? .pending : .unknown), d.subscribeError ?? "")
        s[.receiving] = st(.receiving, packetFresh ? .ok : (d.link == .connected ? .pending : .unknown), "\(d.packets) packets")
        s[.valid] = st(.valid, validFresh ? .ok : (d.lastValidAt != nil && d.link == .connected ? .failed : .pending), d.rejected > 0 ? "\(d.rejected) rejected" : "")
        s[.forwarded] = st(.forwarded, .notApplicable)
        s[.displayed] = st(.displayed, d.displayed ? .ok : (validFresh ? .failed : .pending))
        r.stages = PipelineStage.allCases.map { s[$0] ?? st($0, .unknown) }
        let what = d.kindTitle
        if !d.radioOn { r.health = .failed; r.message = "Bluetooth is off — \(what.lowercased()) unavailable"; return r }
        switch d.link {
        case .disconnected, .connecting:
            if d.rideActive { r.health = .recovering; r.message = "\(what) not connected — reconnecting automatically" }
            else { r.health = .idle; r.message = "\(what) asleep or out of range — connects when awake" }
        case .connected:
            let since = d.connectedAt.map { now.timeIntervalSince($0) } ?? Freshness.graceS
            if d.subscribed == false { r.health = .failed; r.message = "\(what) connected — subscription failed" }
            else if validFresh { r.health = d.displayed ? .live : .noData; r.message = d.displayed ? "\(what) live" : "\(what) data received — not displayed" }
            else if d.lastValidAt != nil { r.health = .stale; r.message = "\(what) data stale" }
            else if since < Freshness.graceS { r.health = .waiting; r.message = "\(what) connected — waiting for data" }
            else { r.health = .noData; r.message = d.packets > 0 ? "\(what) connected — no valid readings" : "\(what) connected — no readings received" }
        }
        return r
    }

    // MARK: per-metric truth for the ride screen
    /// What a metric shows instead of a value when a set-up source cannot deliver one; nil = nothing set up (the plain
    /// "No … source" stays).
    static func missingLabel(_ h: PipelineHealth, metric: MetricKind) -> String? {
        switch h {
        case .waiting: return "Connected — waiting for data"
        case .noData: return "No \(metric.title.lowercased()) data"
        case .stale: return "Data stale"
        case .recovering: return "Reconnecting automatically"
        case .failed: return "\(metric.title) unavailable — see Connections"
        case .notSetUp, .idle, .live: return nil
        }
    }
    /// Metrics each path can provide (for the per-metric labels).
    static func metrics(of id: String, direct: [MetricKind] = []) -> [MetricKind] {
        switch id {
        case "board.power": return [.power, .cadence]
        case "board.hr", "watch.hr": return [.heartRate]
        case "board.csc": return [.cadence, .speed]
        default: return direct
        }
    }
    /// Most severe reason per metric over all paths that provide it.
    static func missingReasons(_ reports: [PipelineReport], directMetrics: [String: [MetricKind]] = [:]) -> [MetricKind: String] {
        var worst: [MetricKind: PipelineHealth] = [:]
        var out: [MetricKind: String] = [:]
        for r in reports {
            for m in metrics(of: r.id, direct: directMetrics[r.id] ?? []) {
                guard let label = missingLabel(r.health, metric: m) else { continue }
                if worst[m] == nil || r.health > worst[m]! { worst[m] = r.health; out[m] = label }
            }
        }
        return out
    }

    // MARK: message selection
    /// The ONE short line for the top of the Ride and Connections screens: the most severe path that needs attention
    /// (ties: power, watch, then direct sensors, in the given order); the watch-update notice only when nothing worse is
    /// going on; nil when every set-up path is live or idle.
    static func topMessage(_ reports: [PipelineReport], versionNotice: String? = nil) -> (message: String, health: PipelineHealth)? {
        var best: PipelineReport?
        for r in reports where r.health.needsMessage && !r.message.isEmpty {
            if best == nil || r.health > best!.health { best = r }
        }
        if let b = best, b.health > .waiting { return (b.message, b.health) }
        if let v = versionNotice { return (v, .waiting) }
        if let b = best { return (b.message, b.health) }
        return nil
    }
}
