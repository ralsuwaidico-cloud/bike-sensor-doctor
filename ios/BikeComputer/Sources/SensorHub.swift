import Foundation
import Combine

// CONTRACT (Cyclift, docs/briefs/CYCLIFT_CONTRACTS.md). Ride layouts, the coach, the recorder mirror and the Watch read
// live metrics ONLY through `SensorHub.reading(_:)`. Source adapters (BikeComputer link, direct BLE sensors, Apple Watch,
// phone GPS, …) feed the hub; the hub applies one priority rule per metric so a value never appears twice or from two
// sources at once. Brand names never appear in metric labels: the label is the metric ("POWER · W") and the source is
// shown separately from `MetricReading.sourceLabel`. Architecture and provider notes: docs/INTEGRATIONS.md.

enum MetricKind: String, CaseIterable, Codable {
    case power, heartRate, cadence, speed
    var title: String { switch self { case .power: return "Power"; case .heartRate: return "Heart rate"; case .cadence: return "Cadence"; case .speed: return "Speed" } }
    var unit: String { switch self { case .power: return "W"; case .heartRate: return "bpm"; case .cadence: return "rpm"; case .speed: return "km/h" } }
    /// Shown when nothing provides the metric — never implies a particular brand is required.
    var missingText: String { switch self { case .power: return "No power source"; case .heartRate: return "No heart-rate source"; case .cadence: return "No cadence source"; case .speed: return "No speed source" } }
    /// A reading older than this is stale and is not shown as live.
    var freshS: TimeInterval { switch self { case .heartRate: return 6; case .speed: return 5; default: return 3 } }
}

/// How a source reaches the phone.
enum ConnectionMethod: String, Codable { case bikeComputer, bleDirect, appleWatch, phoneSensor, healthKit, cloudAPI
    var title: String {
        switch self {
        case .bikeComputer: return "Via the BikeComputer"; case .bleDirect: return "Bluetooth, direct to this phone"
        case .appleWatch: return "Apple Watch app"; case .phoneSensor: return "This phone"
        case .healthKit: return "Apple Health"; case .cloudAPI: return "Online account (after the activity)"
        }
    }
}

/// Live = streamed during the activity; imported = arrives afterwards (e.g. a cloud API or Apple Health sync).
enum DataTiming: String, Codable { case live, imported }

/// Confidence the coach may place in a value. `unverified` = measured but not yet validated (e.g. a power meter that
/// has never been checked against a reference); the coach may show it but must say so.
enum DataQuality: String, Codable { case good, unverified, estimated, stale
    var title: String { switch self { case .good: return "good"; case .unverified: return "unverified"; case .estimated: return "estimated"; case .stale: return "stale" } }
}

struct SourceDescriptor: Equatable, Hashable, Codable {
    var id: String                 // stable, e.g. "bikecomputer", "ble:<uuid>", "watch", "phone-gps"
    var name: String               // user-facing, e.g. "BikeComputer", "Apple Watch", "Phone GPS", the sensor's BLE name
    var method: ConnectionMethod
    var timing: DataTiming = .live
    var relayedBy: String? = nil   // e.g. a strap read by the BikeComputer: relayedBy = "BikeComputer"
}

struct MetricReading: Equatable {
    var kind: MetricKind
    var value: Double
    var at: Date
    var source: SourceDescriptor
    var quality: DataQuality
    var intValue: Int { Int(value.rounded()) }
    /// "Apple Watch", "Power meter via BikeComputer", … — what the layouts print next to the metric.
    var sourceLabel: String { source.relayedBy.map { "\(source.name) via \($0)" } ?? source.name }
}

/// Default priority per metric (first wins); the user's HR preference can move the Watch first. Adapters register
/// readings with a priority rank; ties are broken by freshness.
enum SourcePriority {
    static func rank(_ method: ConnectionMethod, for kind: MetricKind, hrWatchFirst: Bool) -> Int {
        switch (kind, method) {
        case (.heartRate, .appleWatch): return hrWatchFirst ? 0 : 2
        case (.heartRate, .bleDirect): return 1
        case (.heartRate, .bikeComputer): return hrWatchFirst ? 2 : 0
        case (.speed, .bleDirect): return 0          // wheel sensor beats GPS
        case (.speed, .bikeComputer): return 1
        case (.speed, .phoneSensor): return 2
        case (_, .bikeComputer): return 0            // power, cadence: the board's meter link first, then a direct sensor
        case (_, .bleDirect): return 1
        default: return 5
        }
    }
}

// MARK: - Source management (A3)

/// Connection / authorization state of one source, as the Connections dashboard shows it.
enum SourceState: String, Codable {
    case connected, connecting, disconnected, notAuthorized, notConfigured, planned
    var title: String {
        switch self {
        case .connected: return "Connected"; case .connecting: return "Connecting"; case .disconnected: return "Not connected"
        case .notAuthorized: return "Permission needed"; case .notConfigured: return "Not set up"; case .planned: return "Planned — not available yet"
        }
    }
}

/// Everything the dashboard needs about one source: what it is, how it connects, live or imported, which metrics it
/// can give, its state, the last successful update and the data quality.
struct SourceStatus: Identifiable, Equatable {
    var descriptor: SourceDescriptor
    var state: SourceState
    var metrics: [MetricKind]
    /// Plain-language line: what this source provides (also for imported sources that give no live metric).
    var provides: String
    var lastUpdate: Date? = nil
    var quality: DataQuality? = nil
    /// The rider set this source up (paired / enabled) — only then may "missing" show as red.
    var configured = false
    var detail: String = ""
    var id: String { descriptor.id }
    var isLive: Bool { descriptor.timing == .live }
}

/// Pure state rules per adapter (unit-tested; the dashboard colours come from ConnectionRules).
enum SourceStateRules {
    static func board(linkState: DeviceLink.State, liveFresh: Bool, remembered: Bool, autoConnect: Bool) -> SourceState {
        switch linkState {
        case .ready: return liveFresh ? .connected : .connecting
        case .connecting, .scanning, .pairing: return .connecting
        case .unauthorized: return .notAuthorized
        case .off: return remembered ? .disconnected : .notConfigured
        case .idle: return remembered && autoConnect ? .disconnected : .notConfigured
        }
    }
    static func watch(enabled: Bool, paired: Bool, appInstalled: Bool, hrFresh: Bool, workoutRunning: Bool) -> SourceState {
        if hrFresh { return .connected }
        if !enabled || !paired || !appInstalled { return .notConfigured }
        return workoutRunning ? .connecting : .disconnected
    }
    static func gps(authorized: Bool, sharing: Bool, fixFresh: Bool) -> SourceState {
        if !authorized { return .notAuthorized }
        if !sharing { return .disconnected }
        return fixFresh ? .connected : .connecting
    }
    static func health(available: Bool, authorized: Bool, wanted: Bool) -> SourceState {
        if !available { return .notConfigured }
        if authorized { return .connected }
        return wanted ? .notAuthorized : .notConfigured
    }
    static func bleSensor(radio: BLESensors.Radio, link: BLESensors.Link) -> SourceState {
        switch radio {
        case .unauthorized: return .notAuthorized
        case .off, .unsupported: return .disconnected
        default: break
        }
        switch link { case .connected: return .connected; case .connecting: return .connecting; case .disconnected: return .disconnected }
    }
}

final class SensorHub: ObservableObject {
    /// Latest candidate per (metric, source id). Adapters call `offer`.
    @Published private(set) var candidates: [MetricKind: [String: MetricReading]] = [:]
    /// Every known source with its state, rebuilt once per second by `refresh` (live, imported and planned).
    @Published private(set) var sources: [SourceStatus] = []
    var hrWatchFirst: () -> Bool = { false }
    var now: () -> Date = Date.init
    /// Direct Bluetooth sensors on the phone (created idle; no Bluetooth activity until configured or opened).
    let ble = BLESensors()
    /// Last successful reading per source id.
    private(set) var lastSeen: [String: Date] = [:]
    private weak var store: Store?
    weak var health: HealthAccess?

    init() { ble.hub = self }

    func offer(_ r: MetricReading) {
        candidates[r.kind, default: [:]][r.source.id] = r
        if (lastSeen[r.source.id] ?? .distantPast) < r.at { lastSeen[r.source.id] = r.at }
    }
    func withdraw(sourceId: String) { for k in MetricKind.allCases { candidates[k]?[sourceId] = nil } }
    /// Drops candidates that stopped arriving long ago (they are already hidden by `freshS`; this keeps the table small).
    func pruneStale(olderThan s: TimeInterval = 60) {
        let t = now()
        for k in MetricKind.allCases { candidates[k] = candidates[k]?.filter { t.timeIntervalSince($0.value.at) < s } }
    }

    /// The one value shown for a metric, or nil → the layout prints `kind.missingText`.
    func reading(_ kind: MetricKind) -> MetricReading? {
        let t = now()
        let fresh = (candidates[kind] ?? [:]).values.filter { t.timeIntervalSince($0.at) < kind.freshS }
        let w = hrWatchFirst()
        return fresh.min { a, b in
            let ra = SourcePriority.rank(a.source.method, for: kind, hrWatchFirst: w), rb = SourcePriority.rank(b.source.method, for: kind, hrWatchFirst: w)
            return ra != rb ? ra < rb : a.at > b.at
        }
    }
    func value(_ kind: MetricKind) -> Int? { reading(kind)?.intValue }
    /// Fresh readings a given source currently offers (for its detail page).
    func readings(from sourceId: String) -> [MetricReading] {
        let t = now()
        return MetricKind.allCases.compactMap { k in candidates[k]?[sourceId].flatMap { t.timeIntervalSince($0.at) < k.freshS ? $0 : nil } }
    }
    func status(_ id: String) -> SourceStatus? { sources.first { $0.id == id } }

    /// Connects the hub to the store: remembered direct sensors, wheel circumference, persistence of pairings.
    func attach(store s: Store) {
        store = s
        ble.wheelMm = { [weak s] in s?.profile.wheelMm ?? 2096 }
        ble.persist = { [weak s] list in s?.settings.bleSensors = list }
        ble.excludedIds = { Set([UserDefaults.standard.string(forKey: "bikecomputer.peripheral"), UserDefaults.standard.string(forKey: "bikecomputer.stale")].compactMap { $0 }) }
        ble.configure(paired: s.settings.bleSensors)
    }

    // MARK: adapters

    static let bikeComputer = SourceDescriptor(id: "bikecomputer", name: "BikeComputer", method: .bikeComputer)
    static let watch = SourceDescriptor(id: "watch", name: "Apple Watch", method: .appleWatch)
    static let phoneGPS = SourceDescriptor(id: "phone-gps", name: "Phone GPS", method: .phoneSensor)
    static let appleHealth = SourceDescriptor(id: "apple-health", name: "Apple Health", method: .healthKit, timing: .imported)

    /// Name for heart rate the board reports, by its source tag — generic, never a brand.
    static func boardHRName(_ s: BCLink.Source) -> String? {
        switch s {
        case .bleStrap: return "Heart-rate strap"
        case .appleWatch, .phoneStrap: return nil      /* this phone sent it to the board: an echo, not a second source */
        case .wearOS: return "Wear OS watch"
        case .bleCSC: return "Sensor"
        default: return "Heart-rate sensor"
        }
    }

    /// Pulls the current values from the existing links once per second (called by the root view's timer).
    func refresh(device: DeviceLink, watch: WatchLink, location: LocationService, powerVerified: Bool) {
        let t = now()
        if device.state == .ready, device.liveIsFresh, let l = device.live {
            var meter = Self.bikeComputer; meter.name = "Power meter"; meter.relayedBy = "BikeComputer"
            if let p = l.powerW { offer(MetricReading(kind: .power, value: Double(p), at: t, source: meter, quality: powerVerified ? .good : .unverified)) }
            if let c = l.cadenceRpm { offer(MetricReading(kind: .cadence, value: Double(c), at: t, source: meter, quality: .good)) }
            if let h = l.hrBpm, let name = Self.boardHRName(l.hrSource) {
                var s = Self.bikeComputer; s.name = name; s.relayedBy = "BikeComputer"
                offer(MetricReading(kind: .heartRate, value: Double(h), at: t, source: s, quality: .good))
            } else { candidates[.heartRate]?[Self.bikeComputer.id] = nil }
        } else { withdraw(sourceId: Self.bikeComputer.id) }
        if watch.hrIsFresh, let h = watch.hrBpm { offer(MetricReading(kind: .heartRate, value: Double(h), at: watch.hrAt ?? t, source: Self.watch, quality: .good)) }
        if location.sharing, let l = location.last, l.speed >= 0, t.timeIntervalSince(l.timestamp) < 5 {
            offer(MetricReading(kind: .speed, value: l.speed * 3.6, at: l.timestamp, source: Self.phoneGPS, quality: l.horizontalAccuracy <= 20 ? .good : .estimated))
        }
        ble.powerVerified = powerVerified
        ble.tick(now: t)
        // Heart rate from a strap paired on THIS phone also reaches the board (like the watch's), so a board-recorded ride
        // keeps it — only when the board has no strap of its own and the watch is not already sending.
        if let hr = reading(.heartRate), hr.source.method == .bleDirect, !watch.hrIsFresh, device.state == .ready, device.live?.hrSource != .bleStrap {
            device.send(heartRate: hr.intValue, source: .phoneStrap, sampledAt: hr.at)
        }
        pruneStale()
        sources = buildSources(device: device, watch: watch, location: location, at: t)
    }

    private func buildSources(device: DeviceLink, watch: WatchLink, location: LocationService, at t: Date) -> [SourceStatus] {
        let settings = store?.settings ?? AppSettings()
        var out: [SourceStatus] = []
        // BikeComputer (optional device)
        let live = device.state == .ready && device.liveIsFresh ? device.live : nil
        var boardMetrics: [MetricKind] = []
        if live?.powerW != nil { boardMetrics.append(.power) }
        if live?.cadenceRpm != nil { boardMetrics.append(.cadence) }
        if live?.hrBpm != nil, live.map({ Self.boardHRName($0.hrSource) != nil }) == true { boardMetrics.append(.heartRate) }
        out.append(SourceStatus(descriptor: Self.bikeComputer,
                                state: SourceStateRules.board(linkState: device.state, liveFresh: device.liveIsFresh, remembered: device.remembered, autoConnect: settings.autoConnectBoard),
                                metrics: boardMetrics.isEmpty ? [.power, .cadence, .heartRate] : boardMetrics,
                                provides: "Optional cycling computer: relays the power meter, heart-rate strap and sensors paired on it.",
                                lastUpdate: lastSeen[Self.bikeComputer.id] ?? device.liveReceivedAt, quality: live == nil ? nil : .good,
                                configured: device.remembered && settings.autoConnectBoard))
        // Direct Bluetooth sensors
        for s in ble.paired {
            let st = SourceStateRules.bleSensor(radio: ble.radio, link: ble.link(s.id))
            let q: DataQuality? = st == .connected ? (s.kinds.contains(.power) && !ble.powerVerified ? .unverified : .good) : nil
            out.append(SourceStatus(descriptor: ble.descriptor(s), state: st, metrics: s.metrics,
                                    provides: s.kinds.isEmpty ? "Standard Bluetooth sensor" : s.kinds.map(\.title).joined(separator: ", "),
                                    lastUpdate: lastSeen[s.sourceId] ?? ble.lastData[s.id], quality: q, configured: true))
        }
        // Apple Watch
        let watchEnabled = settings.enabledConnections.contains("watch")
        out.append(SourceStatus(descriptor: Self.watch,
                                state: SourceStateRules.watch(enabled: watchEnabled, paired: watch.paired, appInstalled: watch.appInstalled, hrFresh: watch.hrIsFresh, workoutRunning: watch.workoutState == "running"),
                                metrics: [.heartRate], provides: "Live heart rate from the watch workout; ride controls from the wrist.",
                                lastUpdate: lastSeen[Self.watch.id] ?? watch.hrAt, quality: watch.hrIsFresh ? .good : nil, configured: watchEnabled))
        // Phone GPS
        let fixFresh = location.last.map { t.timeIntervalSince($0.timestamp) < 5 } ?? false
        out.append(SourceStatus(descriptor: Self.phoneGPS,
                                state: SourceStateRules.gps(authorized: location.authorized, sharing: location.sharing, fixFresh: fixFresh),
                                metrics: [.speed], provides: "Speed, distance and the route map.",
                                lastUpdate: lastSeen[Self.phoneGPS.id] ?? location.last?.timestamp,
                                quality: fixFresh ? ((location.last?.horizontalAccuracy ?? 99) <= 20 ? .good : .estimated) : nil,
                                configured: settings.phoneOnlyMode || !device.remembered))
        // Imported: Apple Health (real) and the planned cloud providers (never connected in 1.0)
        let h = health
        out.append(SourceStatus(descriptor: Self.appleHealth,
                                state: SourceStateRules.health(available: h?.available ?? false, authorized: h?.workoutWriteAuthorized ?? false, wanted: settings.appleHealthWanted),
                                metrics: [], provides: "Imports cycling and strength workouts. Not a live source.",
                                lastUpdate: settings.lastHealthImport, quality: nil, configured: settings.appleHealthWanted))
        if ReleaseFlags.plannedProvidersVisible { out += ProviderCatalog.planned.map(\.status) }
        return out
    }
}
