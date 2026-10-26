import Foundation
import Combine
import UIKit

/// Automatic diagnostics (ios/PIPELINE_HEALTH.md). Once per second — also in the background while a ride keeps the app
/// alive — it snapshots the links, derives every path's stages with `PipelineRules`, picks ONE short message for the
/// Ride and Connections screens, records health changes in a persisted 50-event ring buffer and runs SAFE recovery:
/// reconnect the board, re-subscribe its live data, re-request the profile, (re)start the watch workout once per ride,
/// re-connect a silent direct sensor. Every action is rate-limited and logged. Diagnostics are also explicitly run (and
/// logged) on app start, board connect, sensor connect, watch available, ride start and when a shown metric goes stale.
final class PipelineMonitor: ObservableObject {
    @Published private(set) var reports: [PipelineReport] = []
    @Published private(set) var top: (message: String, health: PipelineHealth)?
    @Published private(set) var events: [DiagEvent] = []
    @Published private(set) var sensorDiagHistory: [SensorDiagRecord] = []
    @Published private(set) var lastRun: (at: Date, trigger: String)?

    weak var device: DeviceLink?
    weak var watch: WatchLink?
    weak var hub: SensorHub?
    weak var recorder: RideRecorder?
    weak var store: Store?
    weak var diagCenter: DiagReportCenter?

    private var timer: Timer?
    private var lastHealth: [String: PipelineHealth] = [:]
    private var lastAction: [String: Date] = [:]
    private var diagStageSince: [UInt8: (stage: UInt8, since: Date)] = [:]
    private var prev = Prev()
    private var rideStartedAt: Date?
    private var watchRestartedForRide = false
    private var resubscribesThisConnection = 0
    private var profileRetriedFor: Date?
    private struct Prev { var boardReady = false; var bleConnected: Set<String> = []; var watchAvailable = false; var rideActive = false; var shown: Set<MetricKind> = [] }

    static let eventsKey = "cyclift.diagnostics.events.v1"
    static let diagKey = "cyclift.diagnostics.sensordiag.v1"

    init(autoTick: Bool = true) {
        events = Self.load([DiagEvent].self, Self.eventsKey) ?? []
        sensorDiagHistory = Self.load([SensorDiagRecord].self, Self.diagKey) ?? []
        if autoTick {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func attach(device d: DeviceLink, watch w: WatchLink, hub h: SensorHub, recorder r: RideRecorder, store s: Store) {
        device = d; watch = w; hub = h; recorder = r; store = s
        d.onSensorDiag = { [weak self] sd in self?.record(sd) }
        w.onEvent = { [weak self] e in self?.log("watch", e) }
        log("trigger", "Diagnostics run: app start (\(AppInfo.label))")
        lastRun = (Date(), "app start")
    }

    // MARK: events
    func log(_ kind: String, _ text: String, at: Date = Date()) {
        Ring.append(DiagEvent(at: at, kind: kind, text: text), to: &events)
        Self.save(events, Self.eventsKey)
    }
    private func record(_ d: BCLink.SensorDiag) {
        Ring.append(SensorDiagRecord(d, at: Date()), to: &sensorDiagHistory)
        Self.save(sensorDiagHistory, Self.diagKey)
    }
    private static func load<T: Decodable>(_ t: T.Type, _ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private static func save<T: Encodable>(_ v: T, _ key: String) { if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) } }

    /// Rate limiter: true (and remembered) when `key` last ran more than `every` seconds ago.
    private func may(_ key: String, every: TimeInterval, now: Date) -> Bool {
        if let t = lastAction[key], now.timeIntervalSince(t) < every { return false }
        lastAction[key] = now; return true
    }

    // MARK: snapshots
    func boardInputs(now: Date) -> BoardInputs {
        guard let d = device else { return BoardInputs() }
        var b = BoardInputs()
        b.remembered = d.remembered; b.autoConnect = d.autoConnect; b.linkReady = d.state == .ready
        b.attempting = d.stage.isAttempt || d.stage == .waiting
        b.failureReason = d.failure?.reason; b.needsRepair = d.failure?.action == .repair
        b.readyAt = d.readyAt; b.liveAt = d.liveReceivedAt; b.live = d.live; b.liveNotifying = d.notifying["Live"]; b.fw = d.info?.fw
        for (k, sd) in d.sensorDiag {
            if diagStageSince[k]?.stage != sd.stageRaw { diagStageSince[k] = (sd.stageRaw, now) }
            b.diag[k] = BoardInputs.DiagEntry(diag: sd, at: d.sensorDiagAt[k] ?? now, stageSince: diagStageSince[k]?.since ?? now)
        }
        return b
    }

    func watchInputs(now: Date) -> WatchInputs {
        guard let w = watch else { return WatchInputs(enabled: false) }
        var x = WatchInputs()
        x.enabled = store?.settings.enabledConnections.contains("watch") ?? true
        x.paired = w.paired; x.appInstalled = w.appInstalled; x.reachable = w.reachable
        x.mirrorActive = w.mirror.active
        x.workoutState = w.mirror.active && w.mirror.remoteState == "running" && w.workoutState == "idle" ? "running" : w.workoutState
        x.workoutStateAt = w.workoutStateAt ?? w.mirror.startedAt
        x.lastDeliveryAt = w.lastDeliveryAt; x.lastSampleAt = w.ingest.sampleAt; x.hrNow = w.ingest.current(now: now)
        x.watchWorkoutAuth = w.watchWorkoutAuth
        x.rideActive = recorder?.isActive ?? false; x.rideStartedAt = rideStartedAt; x.startRequestedAt = w.startRequestedAt
        if let d = device {
            x.boardLinkReady = d.state == .ready; x.boardLiveFresh = d.liveIsFresh
            x.boardHRSource = d.live?.hrSource; x.boardHR = d.live?.hrBpm; x.hrSentToBoardAt = d.lastHRSentAt
        }
        x.displayed = hub?.reading(.heartRate) != nil
        return x
    }

    func directInputs(now: Date) -> [(id: String, input: DirectInputs)] {
        guard let ble = hub?.ble else { return [] }
        return ble.paired.enumerated().map { (i, s) -> (id: String, input: DirectInputs) in
            var d = DirectInputs()
            d.index = i + 1
            d.kindTitle = s.kinds.first?.genericName ?? "Bluetooth sensor"
            d.freshS = s.kinds == [.heartRate] ? Freshness.heartRateS : Freshness.powerS
            d.radioOn = ble.radio == .on || ble.radio == .unknown
            switch ble.link(s.id) { case .connected: d.link = .connected; case .connecting: d.link = .connecting; case .disconnected: d.link = .disconnected }
            let c = ble.counters[s.id] ?? BLESensors.Counters()
            d.connectedAt = c.connectedAt; d.subscribed = c.subscribed; d.subscribeError = c.subscribeError
            d.packets = c.packets; d.rejected = c.rejected; d.lastPacketAt = c.lastPacketAt; d.lastValidAt = c.lastValidAt
            d.displayed = s.metrics.contains { hub?.reading($0) != nil }
            d.rideActive = recorder?.isActive ?? false
            return (s.id, d)
        }
    }

    var versionNotice: String? {
        guard let w = watch, w.paired, w.appInstalled, store?.settings.enabledConnections.contains("watch") ?? true, w.version == .watchOlder else { return nil }
        return WatchVersion.updateInstruction
    }

    // MARK: the 1 Hz run
    func tick(now: Date = Date()) {
        guard let d = device else { return }
        let board = boardInputs(now: now)
        let live = board.liveFresh(now) ? board.live : nil
        let settings = store?.settings ?? AppSettings()
        var out: [PipelineReport] = []
        let powerShown = hub?.reading(.power).map { $0.source.method == .bikeComputer } ?? false
        out.append(PipelineRules.boardSensor(.power, board: board, metricPresent: live?.powerW != nil, displayed: powerShown,
                                             wanted: settings.enabledConnections.contains("meter") || d.remembered, now: now))
        let strapWanted = settings.enabledConnections.contains("strap")
        if strapWanted || board.diag[BCLink.SensorDiag.Sensor.hrStrap.rawValue] != nil {
            out.append(PipelineRules.boardSensor(.hrStrap, board: board, metricPresent: live?.hrBpm != nil && live?.hrSource == .bleStrap,
                                                 displayed: hub?.reading(.heartRate) != nil, wanted: strapWanted, now: now))
        }
        if board.diag[BCLink.SensorDiag.Sensor.csc.rawValue] != nil {
            out.append(PipelineRules.boardSensor(.csc, board: board, metricPresent: live?.cadenceRpm != nil, displayed: hub?.reading(.cadence) != nil || hub?.reading(.speed) != nil, wanted: false, now: now))
        }
        let w = watchInputs(now: now)
        out.append(PipelineRules.watchHR(w, now: now))
        let directs = directInputs(now: now)
        out += directs.map { PipelineRules.direct($0.input, now: now) }

        // health transitions → events
        for r in out where lastHealth[r.id] != r.health {
            if let old = lastHealth[r.id], old != .notSetUp || r.health != .notSetUp {
                log("health", "\(r.title): \(old.title) → \(r.health.title)" + (r.message.isEmpty ? "" : " · \(r.message)"), at: now)
            }
            lastHealth[r.id] = r.health
        }
        reports = out
        var dm: [String: [MetricKind]] = [:]
        if let ble = hub?.ble { for (i, s) in ble.paired.enumerated() { dm["ble.\(i + 1)"] = s.metrics } }
        let reasons = PipelineRules.missingReasons(out, directMetrics: dm)
        if hub?.missingReason != reasons { hub?.missingReason = reasons }
        let t = PipelineRules.topMessage(out, versionNotice: versionNotice)
        if t?.message != top?.message { top = t }

        triggers(board: board, watch: w, directs: directs, now: now)
        recover(board: board, watch: w, directs: directs, now: now)
    }

    private func run(_ trigger: String, now: Date) {
        lastRun = (now, trigger)
        log("trigger", "Diagnostics run: \(trigger) — " + (top?.message ?? "all set-up sources live or idle"), at: now)
    }

    private func triggers(board: BoardInputs, watch w: WatchInputs, directs: [(id: String, input: DirectInputs)], now: Date) {
        if board.linkReady && !prev.boardReady { run("BikeComputer connected", now: now); resubscribesThisConnection = 0 }
        prev.boardReady = board.linkReady
        let connected = Set(directs.filter { $0.input.link == .connected }.map(\.id))
        for id in connected.subtracting(prev.bleConnected) { run("sensor \(directs.first { $0.id == id }?.input.index ?? 0) connected", now: now) }
        prev.bleConnected = connected
        let available = w.paired && w.appInstalled && (w.reachable || w.mirrorActive)
        if available && !prev.watchAvailable { run("Apple Watch available" + (w.mirrorActive ? " (workout mirrored)" : ""), now: now) }
        prev.watchAvailable = available
        if w.rideActive && !prev.rideActive { rideStartedAt = now; watchRestartedForRide = false; run("ride start", now: now) }
        if !w.rideActive { rideStartedAt = nil }
        prev.rideActive = w.rideActive
        let shown = Set(MetricKind.allCases.filter { hub?.reading($0) != nil })
        for k in prev.shown.subtracting(shown) { run("\(k.title.lowercased()) went stale", now: now) }
        prev.shown = shown
    }

    // MARK: safe recovery
    private func recover(board: BoardInputs, watch w: WatchInputs, directs: [(id: String, input: DirectInputs)], now: Date) {
        guard let d = device else { return }
        // 1. board not connected although wanted (not after a deliberate Disconnect, never over a Repair need)
        if board.remembered, board.autoConnect, d.wantConnection, !board.linkReady, !board.attempting, !board.needsRepair,
           d.stage != .off, d.stage != .unauthorized, may("board.connect", every: 30, now: now) {
            log("recovery", "Reconnecting the BikeComputer automatically (stage: \(d.stage.rawValue))", at: now)
            d.connect()
        }
        // 2. link up but no LIVE: re-subscribe (3× per connection), then drop and reconnect
        if board.linkReady, let r = board.readyAt, now.timeIntervalSince(r) > 6, !board.liveFresh(now) {
            if resubscribesThisConnection < 3, may("board.resubscribe", every: 10, now: now) {
                resubscribesThisConnection += 1
                log("recovery", "No live data from the BikeComputer — re-subscribing (\(resubscribesThisConnection)/3)", at: now)
                d.resubscribeLive()
            } else if resubscribesThisConnection >= 3, may("board.reconnect", every: 120, now: now) {
                log("recovery", "Still no live data — reconnecting the BikeComputer", at: now)
                resubscribesThisConnection = 0
                d.reconnect()
            }
        }
        // 3. profile sync failed on this connection: ask once more
        if board.linkReady, d.failure?.stage == .syncingProfile, profileRetriedFor != board.readyAt {
            profileRetriedFor = board.readyAt
            log("recovery", "Profile sync failed — requesting the board profile again", at: now)
            d.retryProfile()
        }
        // 4. ride running, watch set up, no workout / heart rate after 15 s: start the watch workout again, once per ride
        if w.rideActive, w.enabled, w.paired, w.appInstalled, w.hrNow == nil, w.workoutState != "running", !watchRestartedForRide,
           let s = rideStartedAt, now.timeIntervalSince(s) > 15 {
            watchRestartedForRide = true
            log("recovery", "Watch workout not running 15 s into the ride — starting it again (once)", at: now)
            watch?.startWatchWorkout(reason: "automatic recovery")
        }
        // 5. direct sensor connected but silent (or its subscription failed): reconnect it
        for (id, x) in directs where x.link == .connected {
            let silent = x.subscribed == false || (x.lastPacketAt.map { now.timeIntervalSince($0) > 15 } ?? (x.connectedAt.map { now.timeIntervalSince($0) > 15 } ?? false))
            if silent, may("ble.\(id)", every: 30, now: now) {
                log("recovery", "\(x.kindTitle) (sensor \(x.index)) connected but silent — reconnecting it", at: now)
                hub?.ble.reconnect(id)
            }
        }
    }

    // MARK: report
    func makeReport(now: Date = Date()) -> DiagnosticReport {
        let d = device, w = watch
        var board: DiagnosticReport.Board?
        if let d, d.remembered || d.state == .ready || d.info != nil {
            let s = d.stats
            board = DiagnosticReport.Board(
                firmware: d.info?.fw, protocolVersion: d.info.map { "v\($0.verMajor).\($0.verMinor)" }, caps: d.info.map { "0x" + String($0.caps, radix: 16) },
                stage: d.stage.rawValue, linkUsable: d.state == .ready,
                connectedForS: d.readyAt.map { Int(now.timeIntervalSince($0)) }, liveAgeS: d.liveReceivedAt.map { (now.timeIntervalSince($0) * 10).rounded() / 10 },
                maxNotifyBytes: d.maxNotifyBytes, characteristics: d.characteristicsSeen, notifying: d.notifying, notifyErrors: d.notifyErrors,
                counters: ["connects": s.connects, "drops": s.disconnects, "liveMessages": s.liveMsgs, "events": s.events, "sensorDiags": s.sensorDiags,
                           "rejected": s.rejected, "sentGPS": s.sentGPS, "sentHR": s.sentHR, "sentTime": s.sentTime],
                parseErrors: d.parseErrors, lastFailure: d.failure.map { "\($0.stage.rawValue): \($0.reason)" + ($0.code.map { " [\($0)]" } ?? "") },
                liveResubscribes: d.liveResubscribes,
                latestSensorDiag: d.sensorDiag.keys.sorted().compactMap { k in d.sensorDiag[k].map { SensorDiagRecord($0, at: d.sensorDiagAt[k] ?? now) } })
        }
        let ing = w?.ingest ?? WatchHRIngest()
        let watchSection = DiagnosticReport.Watch(
            enabled: store?.settings.enabledConnections.contains("watch") ?? false, paired: w?.paired ?? false, appInstalled: w?.appInstalled ?? false,
            reachable: w?.reachable ?? false, mirrorActive: w?.mirror.active ?? false, mirrorRemoteState: w?.mirror.remoteState ?? "none",
            mirrorSessions: w?.mirror.sessionsReceived ?? 0, mirrorPayloads: w?.mirror.payloads ?? 0, mirrorBadPayloads: w?.mirror.badPayloads ?? 0,
            lastMirrorDisconnect: w?.mirror.lastDisconnectReason, workoutState: w?.workoutState ?? "idle", workoutAuthOnWatch: w?.watchWorkoutAuth,
            hrAcceptedMirror: ing.accepted[.mirror] ?? 0, hrAcceptedConnectivity: ing.accepted[.connectivity] ?? 0, hrDuplicates: ing.duplicates, hrDropped: ing.dropped,
            lastDeliveryAgeS: w?.lastDeliveryAt.map { (now.timeIntervalSince($0) * 10).rounded() / 10 }, hrSentToBoard: d?.stats.sentHR ?? 0)
        var directs: [DiagnosticReport.Direct] = []
        if let ble = hub?.ble {
            for (i, s) in ble.paired.enumerated() {
                let c = ble.counters[s.id] ?? BLESensors.Counters()
                directs.append(DiagnosticReport.Direct(index: i + 1, kind: s.kinds.map(\.rawValue).joined(separator: "+"), link: ble.link(s.id).rawValue,
                                                       subscribed: c.subscribed, services: c.services, characteristics: c.measurementChars,
                                                       packets: c.packets, rejected: c.rejected,
                                                       lastPacketAgeS: c.lastPacketAt.map { (now.timeIntervalSince($0) * 10).rounded() / 10 },
                                                       lastValidAgeS: c.lastValidAt.map { (now.timeIntervalSince($0) * 10).rounded() / 10 }))
            }
        }
        let check: String
        switch w?.version ?? .unknown {
        case .unknown: check = "unknown (watch has not reported)"
        case .same: check = "same build"
        case .watchOlder: check = "watch app is OLDER — update it"
        case .watchNewer: check = "watch app is newer than the phone app"
        }
        var report = DiagnosticReport(
            generatedAt: now, app: AppInfo.label, system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            watchApp: w?.watchBuild, watchVersionCheck: check,
            topMessage: top?.message, pipelines: reports, board: board, watch: watchSection, directSensors: directs,
            recentEvents: events, sensorDiagHistory: sensorDiagHistory,
            boardStageLog: (d?.log ?? []).suffix(50).map { "\($0.at.formatted(.iso8601)) \($0.text)" })
        report.boardReports = diagCenter?.exportEntries()
        return report
    }

    /// Strings that must never leave the phone in a report: the rider's name and the advertised names of paired sensors.
    var personalStrings: [String] {
        var p: [String] = []
        if let n = store?.profile.name, !n.isEmpty { p.append(n) }
        p += (hub?.ble.paired ?? []).map(\.name).filter { !BLESensorKind.allCases.map(\.genericName).contains($0) && $0 != "Bluetooth sensor" }
        return p
    }

    func reportJSON() -> Data { makeReport().json(personal: personalStrings) }
}
