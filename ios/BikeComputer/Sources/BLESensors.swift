import Foundation
import CoreBluetooth
import Combine

/// Kinds of standard Bluetooth sensor the phone can read directly.
enum BLESensorKind: String, Codable, CaseIterable {
    case heartRate, power, speedCadence
    var title: String { switch self { case .heartRate: return "Heart rate"; case .power: return "Power"; case .speedCadence: return "Speed / cadence" } }
    /// Generic name for a sensor that does not advertise one — never a brand.
    var genericName: String { switch self { case .heartRate: return "Heart-rate sensor"; case .power: return "Power meter"; case .speedCadence: return "Speed / cadence sensor" } }
    var serviceId: String { switch self { case .heartRate: return "180D"; case .power: return "1818"; case .speedCadence: return "1816" } }
    var measurementId: String { switch self { case .heartRate: return "2A37"; case .power: return "2A63"; case .speedCadence: return "2A5B" } }
    /// Metrics this kind of sensor can provide (a power meter's cadence only when it sends crank data).
    var metrics: [MetricKind] { switch self { case .heartRate: return [.heartRate]; case .power: return [.power, .cadence]; case .speedCadence: return [.speed, .cadence] } }
    static func from(serviceId s: String) -> BLESensorKind? { allCases.first { $0.serviceId == s.uppercased() } }
}

/// A sensor the rider paired on this phone (remembered by its CoreBluetooth peripheral identifier). Stored in
/// `AppSettings.bleSensors` (additive, decodeIfPresent default []).
struct PairedSensor: Codable, Equatable, Identifiable {
    var id: String                 // CBPeripheral.identifier.uuidString
    var name: String
    var kinds: [BLESensorKind]
    var pairedAt: Date = Date()

    init(id: String, name: String, kinds: [BLESensorKind], pairedAt: Date = Date()) { self.id = id; self.name = name; self.kinds = kinds; self.pairedAt = pairedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Bluetooth sensor"
        kinds = ((try? c.decodeIfPresent([String].self, forKey: .kinds)) ?? []).compactMap(BLESensorKind.init(rawValue:))
        pairedAt = (try? c.decodeIfPresent(Date.self, forKey: .pairedAt)) ?? Date()
    }
    var sourceId: String { "ble:" + id }
    var metrics: [MetricKind] { var out: [MetricKind] = []; for k in kinds { for m in k.metrics where !out.contains(m) { out.append(m) } }; return out }
}

/// Direct Bluetooth sensors on the phone (heart rate 0x180D, cycling power 0x1818, speed & cadence 0x1816), so a rider
/// without the BikeComputer can ride with standard sensors. Rules:
///  - its own CBCentralManager with its own restore identifier ("cyclift.sensors.central"); DeviceLink and the
///    BikeComputer link are untouched, and the board's peripheral is never offered here;
///  - created lazily: no central exists until the rider opens "Add a sensor" or has paired sensors;
///  - pairs ONLY on the rider's tap; never connects to an unknown device by itself;
///  - remembers paired sensors and keeps a pending connect open so they reconnect automatically when in range;
///  - READ / NOTIFY ONLY: it subscribes to the measurement characteristics and never writes a value to any
///    characteristic (no control point, no calibration, no settings) — project safety rule;
///  - offers readings to the SensorHub (method .bleDirect, the sensor's name) and withdraws them on disconnect.
final class BLESensors: NSObject, ObservableObject {
    enum Radio: String { case unknown, off, unauthorized, unsupported, on }
    enum Link: String { case disconnected, connecting, connected }
    struct Discovered: Identifiable, Equatable { let id: UUID; var name: String; var rssi: Int; var kinds: [BLESensorKind] }

    @Published private(set) var paired: [PairedSensor] = []
    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var scanning = false
    @Published private(set) var radio: Radio = .unknown
    @Published private(set) var links: [String: Link] = [:]
    @Published private(set) var lastData: [String: Date] = [:]
    @Published private(set) var lastError: String?
    /// Per-sensor pipeline counters (PIPELINE_HEALTH.md): connected since, services and measurement characteristics
    /// found, subscription confirmed by iOS, packets received / rejected, last packet and last valid measurement.
    struct Counters: Equatable {
        var connectedAt: Date?
        var services: [String] = []
        var measurementChars: [String] = []
        var subscribed: Bool?
        var subscribeError: String?
        var packets = 0
        var rejected = 0
        var lastPacketAt: Date?
        var lastValidAt: Date?
    }
    @Published private(set) var counters: [String: Counters] = [:]

    weak var hub: SensorHub?
    var wheelMm: () -> Int = { 2096 }
    var persist: ([PairedSensor]) -> Void = { _ in }
    /// Peripheral identifiers that must never be offered as a sensor (the BikeComputer board).
    var excludedIds: () -> Set<String> = { [] }
    var powerVerified = false

    static let restoreId = "cyclift.sensors.central"
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var crank: [String: RevolutionRate] = [:]
    private var wheel: [String: RevolutionRate] = [:]
    private var wantScan = false
    private var scanTimer: Timer?
    private let services = BLESensorKind.allCases.map { CBUUID(string: $0.serviceId) }
    private let measurements = BLESensorKind.allCases.map { CBUUID(string: $0.measurementId) }

    /// Called once at launch with the remembered sensors. Creates the central only if something is paired (needed at
    /// launch so iOS can restore a background connection).
    func configure(paired list: [PairedSensor]) {
        paired = list
        for p in list { links[p.id] = .disconnected }
        if !list.isEmpty { ensureCentral() }
    }

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: BLESensors.restoreId])
    }

    // MARK: rider actions
    func startScan() {
        wantScan = true
        ensureCentral()
        guard let c = central, c.state == .poweredOn else { return }
        discovered = []
        c.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanning = true
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in self?.stopScan() }
    }

    func stopScan() {
        wantScan = false
        scanTimer?.invalidate(); scanTimer = nil
        central?.stopScan()
        scanning = false
    }

    /// The rider tapped a sensor in the search list: remember it and connect.
    func pair(_ id: UUID) {
        guard let c = central, let d = discovered.first(where: { $0.id == id }) else { return }
        let key = id.uuidString
        if !paired.contains(where: { $0.id == key }) {
            paired.append(PairedSensor(id: key, name: d.name, kinds: d.kinds))
            persist(paired)
        }
        discovered.removeAll { $0.id == id }
        if let p = peripherals[id] ?? c.retrievePeripherals(withIdentifiers: [id]).first { connect(p) }
    }

    func forget(_ id: String) {
        if let u = UUID(uuidString: id), let p = peripherals[u] { central?.cancelPeripheralConnection(p); peripherals[u] = nil }
        paired.removeAll { $0.id == id }
        links[id] = nil; lastData[id] = nil; crank[id] = nil; wheel[id] = nil
        hub?.withdraw(sourceId: "ble:" + id)
        persist(paired)
    }

    func reconnect(_ id: String) {
        ensureCentral()
        guard let c = central, c.state == .poweredOn, let u = UUID(uuidString: id) else { return }
        if let p = peripherals[u] { c.cancelPeripheralConnection(p) }
        if let p = peripherals[u] ?? c.retrievePeripherals(withIdentifiers: [u]).first { connect(p) }
    }

    func link(_ id: String) -> Link { links[id] ?? .disconnected }

    // MARK: hub feed
    /// Once per second (from SensorHub.refresh): cadence and speed fall to 0 after 3 s without a new revolution while the
    /// sensor stays connected (many sensors stop notifying when nothing turns).
    func tick(now: Date) {
        for s in paired where link(s.id) == .connected {
            if let r = crank[s.id]?.rate(at: now), r <= 250 { offer(.cadence, r, s, at: now) }
            if let r = wheel[s.id]?.rate(at: now) {
                let kmh = RevolutionRate.speedKmh(wheelRpm: r, circumferenceMm: wheelMm())
                if kmh <= 120 { offer(.speed, kmh, s, at: now) }
            }
        }
    }

    func descriptor(_ s: PairedSensor) -> SourceDescriptor { SourceDescriptor(id: s.sourceId, name: s.name, method: .bleDirect) }

    private func offer(_ kind: MetricKind, _ v: Double, _ s: PairedSensor, at: Date) {
        let q: DataQuality = kind == .power ? (powerVerified ? .good : .unverified) : .good
        hub?.offer(MetricReading(kind: kind, value: v, at: at, source: descriptor(s), quality: q))
    }

    // MARK: internals
    private func connect(_ p: CBPeripheral) {
        guard let c = central else { return }
        peripherals[p.identifier] = p
        p.delegate = self
        links[p.identifier.uuidString] = p.state == .connected ? .connected : .connecting
        if p.state == .connected { p.discoverServices(services); return }
        // a pending connect: iOS completes it whenever the sensor is in range (also in the background)
        c.connect(p, options: nil)
    }

    private func connectAllPaired() {
        guard let c = central, c.state == .poweredOn else { return }
        let ids = paired.compactMap { UUID(uuidString: $0.id) }
        for p in c.retrievePeripherals(withIdentifiers: ids) where p.state != .connected || links[p.identifier.uuidString] != .connected { connect(p) }
    }

    private func sensor(_ p: CBPeripheral) -> PairedSensor? { paired.first { $0.id == p.identifier.uuidString } }

    private func noteKinds(_ p: CBPeripheral, _ kinds: [BLESensorKind]) {
        guard let i = paired.firstIndex(where: { $0.id == p.identifier.uuidString }) else { return }
        var s = paired[i]
        for k in kinds where !s.kinds.contains(k) { s.kinds.append(k) }
        if let n = p.name, !n.isEmpty, s.name != n, s.name == "Bluetooth sensor" || BLESensorKind.allCases.contains(where: { $0.genericName == s.name }) { s.name = n }
        if s != paired[i] { paired[i] = s; persist(paired) }
    }
}

extension BLESensors: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            radio = .on
            connectAllPaired()
            if wantScan { startScan() }
        case .poweredOff: radio = .off; scanning = false; markAllDisconnected()
        case .unauthorized: radio = .unauthorized; scanning = false; markAllDisconnected()
        case .unsupported: radio = .unsupported
        default: radio = .unknown
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        for p in (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? [] { peripherals[p.identifier] = p; p.delegate = self }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let key = p.identifier.uuidString
        guard !excludedIds().contains(key), !paired.contains(where: { $0.id == key }) else { return }
        peripherals[p.identifier] = p
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let kinds = uuids.compactMap { BLESensorKind.from(serviceId: $0.uuidString) }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? kinds.first?.genericName ?? "Bluetooth sensor"
        let d = Discovered(id: p.identifier, name: name, rssi: rssi.intValue, kinds: kinds)
        if let i = discovered.firstIndex(where: { $0.id == p.identifier }) { discovered[i] = d } else { discovered.append(d) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        guard sensor(p) != nil else { c.cancelPeripheralConnection(p); return }     /* only sensors the rider paired */
        links[p.identifier.uuidString] = .connected
        counters[p.identifier.uuidString] = Counters(connectedAt: Date(), packets: counters[p.identifier.uuidString]?.packets ?? 0, rejected: counters[p.identifier.uuidString]?.rejected ?? 0)
        lastError = nil
        p.delegate = self
        p.discoverServices(services)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        let key = p.identifier.uuidString
        links[key] = .disconnected
        lastError = error?.localizedDescription
        guard sensor(p) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.sensor(p) != nil, self.link(key) == .disconnected else { return }
            self.connect(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let key = p.identifier.uuidString
        hub?.withdraw(sourceId: "ble:" + key)
        crank[key] = nil; wheel[key] = nil
        counters[key]?.connectedAt = nil; counters[key]?.subscribed = nil
        guard sensor(p) != nil else { links[key] = nil; return }
        links[key] = .connecting
        c.connect(p, options: nil)          /* pending reconnect: completes when the sensor is back in range */
    }

    private func markAllDisconnected() {
        for s in paired { links[s.id] = .disconnected; hub?.withdraw(sourceId: s.sourceId) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { lastError = error?.localizedDescription; return }
        var kinds: [BLESensorKind] = []
        for s in p.services ?? [] {
            guard let k = BLESensorKind.from(serviceId: s.uuid.uuidString) else { continue }
            kinds.append(k)
            p.discoverCharacteristics([CBUUID(string: k.measurementId)], for: s)
        }
        counters[p.identifier.uuidString, default: Counters()].services = (p.services ?? []).map { $0.uuid.uuidString.uppercased() }
        noteKinds(p, kinds)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard error == nil else { lastError = error?.localizedDescription; return }
        // Subscribe only (the client characteristic configuration descriptor). No characteristic value is ever written.
        for c in s.characteristics ?? [] where measurements.contains(c.uuid) && (c.properties.contains(.notify) || c.properties.contains(.indicate)) {
            counters[p.identifier.uuidString, default: Counters()].measurementChars.append(c.uuid.uuidString.uppercased())
            p.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let d = c.value, let s = sensor(p) else { return }
        let now = Date()
        let key = s.id
        counters[key, default: Counters()].packets += 1
        counters[key]?.lastPacketAt = now
        func reject() { counters[key]?.rejected += 1 }
        switch c.uuid.uuidString.uppercased() {
        case BLESensorKind.heartRate.measurementId:
            guard let bpm = BLEDecode.heartRate(d) else { reject(); return }
            offer(.heartRate, Double(bpm), s, at: now)
        case BLESensorKind.power.measurementId:
            guard let m = BLEDecode.cyclingPower(d) else { reject(); return }
            offer(.power, Double(m.powerW), s, at: now)
            if let k = m.crank {
                var r = crank[key] ?? .crank(); r.update(k, at: now); crank[key] = r
                if let v = r.rate(at: now), v <= 250 { offer(.cadence, v, s, at: now) }
            }
            if let w = m.wheel, !s.kinds.contains(.speedCadence) {
                var r = wheel[key] ?? .powerWheel(); r.update(w, at: now); wheel[key] = r
            }
        case BLESensorKind.speedCadence.measurementId:
            guard let m = BLEDecode.csc(d) else { reject(); return }
            if let k = m.crank {
                var r = crank[key] ?? .crank(); r.update(k, at: now); crank[key] = r
                if let v = r.rate(at: now), v <= 250 { offer(.cadence, v, s, at: now) }
            }
            if let w = m.wheel {
                var r = wheel[key] ?? .cscWheel(); r.update(w, at: now); wheel[key] = r
                if let v = r.rate(at: now) {
                    let kmh = RevolutionRate.speedKmh(wheelRpm: v, circumferenceMm: wheelMm())
                    if kmh <= 120 { offer(.speed, kmh, s, at: now) }
                }
            }
        default: return
        }
        counters[key]?.lastValidAt = now
        lastData[key] = now
        if links[key] != .connected { links[key] = .connected }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        let key = p.identifier.uuidString
        if let e = error { lastError = e.localizedDescription; counters[key, default: Counters()].subscribeError = e.localizedDescription }
        counters[key, default: Counters()].subscribed = error == nil && c.isNotifying
    }
}
