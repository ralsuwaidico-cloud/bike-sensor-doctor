import Foundation

// MARK: - S2-0 data integrity (ios/S20_DATA_INTEGRITY.md)
// Every athlete value that feeds a calculation carries where it came from and when. Nothing is ever filled in with a
// sample value: a value the athlete did not give, import or measure is Unknown, and everything that depends on it says so.

/// Where a stored athlete value came from.
enum ValueSource: String, Codable, CaseIterable {
    /// Typed by the athlete in this app.
    case entered
    /// Read from Apple Health with the athlete's permission.
    case appleHealth
    /// A recorded test (an FTP test ride with verified power).
    case measuredTest
    /// Estimated from recorded rides (0.95 × best 20 min, Coggan) — an estimate, never a measurement.
    case estimatedFromRides
    /// Present in a file written by an earlier build whose provenance cannot be established. Kept, flagged, never
    /// relabelled as entered; the athlete is asked to confirm it.
    case legacyUnverified
    /// Not known. Dependent calculations are unavailable.
    case unknown

    var title: String {
        switch self {
        case .entered: return "Entered"; case .appleHealth: return "Apple Health"; case .measuredTest: return "Measured"
        case .estimatedFromRides: return "Estimated"; case .legacyUnverified: return "Unverified"; case .unknown: return "Unknown"
        }
    }
    /// The one-word tag the UI shows next to a number: Measured / Estimated / Unknown (owner rule: never show an
    /// estimate as a measurement).
    var tag: String {
        switch self {
        case .entered, .appleHealth, .measuredTest: return "Measured"
        case .estimatedFromRides: return "Estimated"
        case .legacyUnverified: return "Unverified"
        case .unknown: return "Unknown"
        }
    }
    var isKnown: Bool { self != .unknown }
}

/// The provenance record of one athlete value.
struct ValueProvenance: Codable, Equatable {
    var source: ValueSource
    /// When the value was entered, measured or sampled (nil = the earlier build did not record it).
    var recordedAt: Date?
    /// The athlete should confirm this value before it is relied on (legacy data of unknown provenance).
    var needsConfirmation: Bool = false

    init(source: ValueSource, recordedAt: Date? = nil, needsConfirmation: Bool = false) {
        self.source = source; self.recordedAt = recordedAt; self.needsConfirmation = needsConfirmation
    }
    static let unknown = ValueProvenance(source: .unknown)
    static func legacy(_ at: Date? = nil) -> ValueProvenance { ValueProvenance(source: .legacyUnverified, recordedAt: at, needsConfirmation: true) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decodeIfPresent(ValueSource.self, forKey: .source)) ?? .unknown
        recordedAt = try? c.decodeIfPresent(Date.self, forKey: .recordedAt)
        needsConfirmation = (try? c.decodeIfPresent(Bool.self, forKey: .needsConfirmation)) ?? false
    }
}

/// The athlete values that carry provenance (dictionary keys in the profile, stable strings in the file).
enum ProfileField: String, Codable, CaseIterable {
    case dateOfBirth, weight, ftp, maxHR, restHR, hrv, sleep
    var title: String {
        switch self {
        case .dateOfBirth: return "Date of birth"; case .weight: return "Weight"; case .ftp: return "FTP"; case .maxHR: return "Max heart rate"
        case .restHR: return "Resting heart rate"; case .hrv: return "Heart-rate variability"; case .sleep: return "Sleep"
        }
    }
}

// MARK: - Apple Health reads (§5): optional, permission-based, source + date shown, no conclusions drawn

/// A value read from Apple Health. The unit is fixed per kind: kg, bpm, ms (SDNN), hours.
struct HealthSample: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case weight, restingHR, hrv, sleep
        var field: ProfileField { switch self { case .weight: return .weight; case .restingHR: return .restHR; case .hrv: return .hrv; case .sleep: return .sleep } }
        var title: String { switch self { case .weight: return "Weight"; case .restingHR: return "Resting heart rate"; case .hrv: return "HRV"; case .sleep: return "Sleep" } }
        var unit: String { switch self { case .weight: return "kg"; case .restingHR: return "bpm"; case .hrv: return "ms"; case .sleep: return "h" } }
    }
    var kind: Kind
    var value: Double
    /// Sample end date (the measurement time, or the end of the night for sleep).
    var date: Date
    /// Apple Health source name (Checkpoint E); nil when unknown. Optional so files written before it decode unchanged.
    var source: String? = nil
}

/// Which Health reads the athlete turned on (each one asks iOS for permission the first time).
struct HealthReadSettings: Codable, Equatable {
    var weight = false, restingHR = false, hrv = false, sleep = false
    var anyEnabled: Bool { weight || restingHR || hrv || sleep }
    func enabled(_ k: HealthSample.Kind) -> Bool { switch k { case .weight: return weight; case .restingHR: return restingHR; case .hrv: return hrv; case .sleep: return sleep } }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weight = (try? c.decodeIfPresent(Bool.self, forKey: .weight)) ?? false
        restingHR = (try? c.decodeIfPresent(Bool.self, forKey: .restingHR)) ?? false
        hrv = (try? c.decodeIfPresent(Bool.self, forKey: .hrv)) ?? false
        sleep = (try? c.decodeIfPresent(Bool.self, forKey: .sleep)) ?? false
    }
}

/// Precedence between what the athlete typed and what Apple Health reports (pure, unit-tested):
/// the NEWER of the two wins; a manual entry made after the Health sample stays until a newer sample arrives.
/// A legacy value of unknown provenance never beats a dated sample. Equal dates: the manual entry wins (explicit choice).
enum HealthPrecedence {
    enum Winner: Equatable { case keepCurrent, useSample }
    static func decide(current: ValueProvenance?, sample: HealthSample) -> Winner {
        guard let cur = current, cur.source.isKnown else { return .useSample }
        switch cur.source {
        case .legacyUnverified, .unknown: return .useSample
        case .appleHealth: return (cur.recordedAt ?? .distantPast) < sample.date ? .useSample : .keepCurrent
        case .entered, .measuredTest, .estimatedFromRides:
            guard let at = cur.recordedAt else { return .keepCurrent }     /* an undated manual entry is kept until the athlete changes it */
            return at < sample.date ? .useSample : .keepCurrent
        }
    }
}

// MARK: - Energy of a ride (GR-45): explicit unit and source, never relabelled

/// Energy recorded for a ride. Work from a power meter is kJ; Apple Health reports active energy in kcal, an estimate
/// made by the Watch/phone, which is never shown as work "from power".
struct EnergyValue: Codable, Equatable {
    enum Kind: String, Codable {
        /// Mechanical work integrated from power samples (kJ).
        case workFromPowerKJ
        /// Active energy as Apple Health reports it (kcal, estimated by the recording device).
        case activeKcalAppleHealth
        /// A number from an earlier build whose unit or source cannot be established; kept, shown as unverified.
        case legacyUnverified
    }
    var kind: Kind
    var value: Int
    var unit: String { kind == .activeKcalAppleHealth ? "kcal" : "kJ" }
    var sourceText: String {
        switch kind {
        case .workFromPowerKJ: return "from power"
        case .activeKcalAppleHealth: return "Apple Health estimate"
        case .legacyUnverified: return "unverified (older build)"
        }
    }
    var isMeasuredWork: Bool { kind == .workFromPowerKJ }
}

// MARK: - Device state (GR-42 / GR-47): paired ≠ connected ≠ receiving data

/// One state model for every device and sensor, derived from the real link signals (never from a switch the athlete
/// flipped). `receivingData` means a sample arrived within `DeviceState.freshWindow` seconds; `stale` means the link is
/// up and samples did arrive, but none for longer than that window (owner point 4: stale is its own state).
enum DeviceState: Equatable {
    case notPaired
    case paired
    case connected
    case receivingData(lastSampleAt: Date)
    case stale(lastSampleAt: Date)
    case problem(reason: String)

    static let freshWindow: TimeInterval = 10

    /// The link is up: fresh samples → receiving, old samples → stale, none ever → connected.
    static func linked(lastSampleAt: Date?, now: Date) -> DeviceState {
        guard let t = lastSampleAt else { return .connected }
        return now.timeIntervalSince(t) <= freshWindow ? .receivingData(lastSampleAt: t) : .stale(lastSampleAt: t)
    }

    var title: String {
        switch self {
        case .notPaired: return "Not connected"
        case .paired: return "Paired"
        case .connected: return "Connected"
        case .receivingData: return "Receiving live data"
        case .stale: return "Connected · no recent data"
        case .problem: return "Connection problem"
        }
    }
    var isReceiving: Bool { if case .receivingData = self { return true }; return false }
    var isStale: Bool { if case .stale = self { return true }; return false }
    var isConnectedOrBetter: Bool { switch self { case .connected, .receivingData, .stale: return true; default: return false } }
    /// Dashboard colour (reuses the Connections rules: green only while data flows).
    var conn: ConnStatus {
        switch self {
        case .receivingData: return .green
        case .stale, .connected, .paired: return .amber
        case .problem: return .red
        case .notPaired: return .gray
        }
    }
}

/// A device row as the Devices page and the pre-ride check show it.
struct DeviceStatus: Identifiable, Equatable {
    var id: String
    var name: String
    var state: DeviceState
    var lastSyncedAt: Date?
    /// What it provides in plain words.
    var provides: String
    /// Plain-language detail (e.g. the problem reason, or "last data 3 s ago").
    var detail: String = ""
}

/// Pure derivation rules (unit-tested). `now` is injected.
enum DeviceStateRules {
    /// BikeComputer: `remembered` = paired keys exist; `ready` = the BLE link is up; live samples make it "receiving".
    static func board(linkState: DeviceLink.State, remembered: Bool, lastLiveAt: Date?, pairingLost: Bool, bluetoothOff: Bool, now: Date) -> DeviceState {
        if pairingLost { return .problem(reason: "Pairing keys were lost on one side. Re-pair from the BikeComputer page.") }
        if bluetoothOff { return remembered ? .problem(reason: "Bluetooth is off") : .notPaired }
        switch linkState {
        case .ready: return DeviceState.linked(lastSampleAt: lastLiveAt, now: now)
        case .connecting, .scanning, .pairing: return remembered ? .paired : .notPaired
        case .unauthorized: return .problem(reason: "Bluetooth permission needed")
        case .off: return remembered ? .problem(reason: "Bluetooth is off") : .notPaired
        case .idle: return remembered ? .paired : .notPaired
        }
    }
    /// Apple Watch: paired + app installed = paired; a running mirror session = connected; fresh heart-rate samples = receiving.
    static func watch(paired: Bool, appInstalled: Bool, sessionRunning: Bool, lastHRAt: Date?, now: Date) -> DeviceState {
        if let t = lastHRAt, now.timeIntervalSince(t) <= DeviceState.freshWindow { return .receivingData(lastSampleAt: t) }
        if !paired { return .notPaired }
        if !appInstalled { return .problem(reason: "Cyclift is not installed on the Watch") }
        return sessionRunning ? DeviceState.linked(lastSampleAt: lastHRAt, now: now) : .paired
    }
    /// A direct Bluetooth sensor (strap, power meter, cadence/speed): `configured` = the athlete paired it in the app.
    static func bleSensor(configured: Bool, link: BLESensors.Link, radio: BLESensors.Radio, lastSampleAt: Date?, now: Date) -> DeviceState {
        switch radio {
        case .unauthorized: return configured ? .problem(reason: "Bluetooth permission needed") : .notPaired
        case .off: return configured ? .problem(reason: "Bluetooth is off") : .notPaired
        case .unsupported: return configured ? .problem(reason: "Bluetooth is not available on this phone") : .notPaired
        default: break
        }
        guard configured else { return .notPaired }
        switch link {
        case .connected: return DeviceState.linked(lastSampleAt: lastSampleAt, now: now)
        case .connecting: return .paired
        case .disconnected: return .paired
        }
    }
    /// A sensor the BikeComputer reports (meter link code from LIVE): 4 = paired and sending, 2/3/5 = searching / weak, 1 = lost.
    static func boardSensor(boardReceiving: Bool, meterLink: Int?, enabled: Bool, lastSampleAt: Date?, now: Date) -> DeviceState {
        guard enabled else { return .notPaired }
        guard boardReceiving, let m = meterLink else { return .paired }
        switch m {
        case 4: return DeviceState.linked(lastSampleAt: lastSampleAt, now: now)
        case 2, 3, 5: return .paired
        case 1: return .problem(reason: "The BikeComputer lost the sensor")
        default: return .paired
        }
    }
    /// Apple Health is not a live device: authorized = connected; a successful read or write = receiving (sync time shown).
    static func health(available: Bool, authorized: Bool, wanted: Bool, lastSyncAt: Date?, now: Date) -> DeviceState {
        guard available else { return .notPaired }
        if !authorized { return wanted ? .problem(reason: "Permission not granted in the Health app") : .notPaired }
        if let t = lastSyncAt, now.timeIntervalSince(t) <= 60 { return .receivingData(lastSampleAt: t) }
        return .connected
    }
    static func detail(_ s: DeviceState, lastSyncedAt: Date?, now: Date) -> String {
        switch s {
        case .receivingData(let t): let a = Int(now.timeIntervalSince(t)); return a <= 1 ? "live" : "last data \(a) s ago"
        case .stale(let t): return "connected · last data \(Self.ago(t, now: now))"
        case .problem(let r): return r
        case .connected: return "connected · no data yet"
        case .paired: return lastSyncedAt.map { "paired · last sync \(Self.ago($0, now: now))" } ?? "paired · not connected now"
        case .notPaired: return "not set up"
        }
    }
    static func ago(_ d: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "\(s) s ago" }; if s < 3600 { return "\(s / 60) min ago" }; if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }
}
