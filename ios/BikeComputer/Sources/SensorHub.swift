import Foundation
import Combine

// CONTRACT (Cyclift, docs/briefs/CYCLIFT_CONTRACTS.md). Ride layouts, the coach, the recorder mirror and the Watch read
// live metrics ONLY through `SensorHub.reading(_:)`. Source adapters (BikeComputer link, direct BLE sensors, Apple Watch,
// phone GPS, …) feed the hub; the hub applies one priority rule per metric so a value never appears twice or from two
// sources at once. Brand names never appear in metric labels: the label is the metric ("POWER · W") and the source is
// shown separately from `MetricReading.source.name`.

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
enum ConnectionMethod: String, Codable { case bikeComputer, bleDirect, appleWatch, phoneSensor, healthKit, cloudAPI }

/// Live = streamed during the activity; imported = arrives afterwards (e.g. a cloud API or Apple Health sync).
enum DataTiming: String, Codable { case live, imported }

/// Confidence the coach may place in a value. `unverified` = measured but not yet validated (e.g. a power meter that
/// has never been checked against a reference); the coach may show it but must say so.
enum DataQuality: String, Codable { case good, unverified, estimated, stale }

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

final class SensorHub: ObservableObject {
    /// Latest candidate per (metric, source id). Adapters call `offer`.
    @Published private(set) var candidates: [MetricKind: [String: MetricReading]] = [:]
    var hrWatchFirst: () -> Bool = { false }
    var now: () -> Date = Date.init

    func offer(_ r: MetricReading) { candidates[r.kind, default: [:]][r.source.id] = r }
    func withdraw(sourceId: String) { for k in MetricKind.allCases { candidates[k]?[sourceId] = nil } }

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

    // MARK: adapters that exist today (Agent 3 adds direct BLE sensors and moves these into Sources/Adapters)

    static let bikeComputer = SourceDescriptor(id: "bikecomputer", name: "BikeComputer", method: .bikeComputer)
    static let watch = SourceDescriptor(id: "watch", name: "Apple Watch", method: .appleWatch)
    static let phoneGPS = SourceDescriptor(id: "phone-gps", name: "Phone GPS", method: .phoneSensor)

    /// Pulls the current values from the existing links once per second (called by the root view's timer).
    func refresh(device: DeviceLink, watch: WatchLink, location: LocationService, powerVerified: Bool) {
        let t = now()
        if device.state == .ready, device.liveIsFresh, let l = device.live {
            var meter = Self.bikeComputer; meter.name = "Power meter"; meter.relayedBy = "BikeComputer"
            if let p = l.powerW { offer(MetricReading(kind: .power, value: Double(p), at: t, source: meter, quality: powerVerified ? .good : .unverified)) }
            if let c = l.cadenceRpm { offer(MetricReading(kind: .cadence, value: Double(c), at: t, source: meter, quality: .good)) }
            if let h = l.hrBpm {
                var s = Self.bikeComputer; s.name = l.hrSource.label; s.relayedBy = "BikeComputer"
                offer(MetricReading(kind: .heartRate, value: Double(h), at: t, source: s, quality: .good))
            }
        } else { withdraw(sourceId: Self.bikeComputer.id) }
        if watch.hrIsFresh, let h = watch.hrBpm { offer(MetricReading(kind: .heartRate, value: Double(h), at: watch.hrAt ?? t, source: Self.watch, quality: .good)) }
        if location.sharing, let l = location.last, l.speed >= 0, t.timeIntervalSince(l.timestamp) < 5 {
            offer(MetricReading(kind: .speed, value: l.speed * 3.6, at: l.timestamp, source: Self.phoneGPS, quality: l.horizontalAccuracy <= 20 ? .good : .estimated))
        }
    }
}
