import Foundation
import CoreBluetooth
import Combine

/// Connection to the Waveshare cycling computer ("BikeComputer Link", protocol v1). The board is the hub: this class
/// mirrors its live values and feeds it GPS, time and watch heart rate. It never invents a value: a field missing from
/// the board's message is nil and shown as "--".
final class DeviceLink: NSObject, ObservableObject {
    enum State: String { case off = "Bluetooth off", idle = "Not connected", scanning = "Searching…", connecting = "Connecting…",
                         pairing = "Pairing — type the code shown on the Waveshare", ready = "Connected", unauthorized = "Bluetooth permission needed" }

    @Published private(set) var state: State = .idle
    @Published private(set) var info: BCLink.Info?
    @Published private(set) var live: BCLink.Live?
    @Published private(set) var liveReceivedAt: Date?
    @Published private(set) var remembered = false
    @Published private(set) var rssi: Int?
    @Published private(set) var lastControl: BCLink.ControlResponse?
    @Published private(set) var lastError: String?
    @Published private(set) var stats = Stats()
    @Published private(set) var found: [(id: UUID, name: String, rssi: Int)] = []

    struct Stats { var connects = 0, liveMsgs = 0, rejected = 0, sentGPS = 0, sentHR = 0, sentTime = 0, disconnects = 0 }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var inputChr: CBCharacteristic?, controlChr: CBCharacteristic?, liveChr: CBCharacteristic?
    private var seq: UInt16 = 0
    private var reqId: UInt16 = 0
    private var timeTimer: Timer?
    private var rssiTimer: Timer?
    private var wantConnection = false
    private let rememberedKey = "bikecomputer.peripheral"
    private let serviceUUID = CBUUID(string: BCLink.serviceUUID)
    private let boardStart = Date()

    override init() {
        super.init()
        remembered = UserDefaults.standard.string(forKey: rememberedKey) != nil
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "bikecomputer.central"])
    }

    /// Live values are considered current only while the board keeps sending (1 Hz). Older than 3 s = stale.
    var liveIsFresh: Bool { guard let t = liveReceivedAt else { return false }; return Date().timeIntervalSince(t) < 3 }

    // MARK: user actions
    func connect() {
        wantConnection = true
        guard central.state == .poweredOn else { return }
        if let idStr = UserDefaults.standard.string(forKey: rememberedKey), let id = UUID(uuidString: idStr),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p)
        } else {
            startScan()
        }
    }

    func connect(to id: UUID) {
        wantConnection = true
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        UserDefaults.standard.set(id.uuidString, forKey: rememberedKey)
        remembered = true
        attach(p)
    }

    func disconnect() {
        wantConnection = false
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        setState(.idle)
    }

    /// Forgets the board here. The board's own bond is removed with "Forget phone" on its Settings > Phone page;
    /// iOS removes its bond in Settings > Bluetooth > BikeComputer > Forget This Device.
    func forget() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        remembered = false
        info = nil; live = nil
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        found = []
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        setState(.scanning)
    }

    // MARK: sending
    func send(gps fix: BCLink.GPSFix) {
        guard let d = BCLink.encodeGPS(fix, seq: nextSeq(), tMs: nowMs()) else { return }
        if write(d, to: inputChr) { stats.sentGPS += 1 }
    }

    func send(heartRate bpm: Int, source: BCLink.Source, sampledAt: Date) {
        guard bpm >= 25, bpm <= 250, let d = BCLink.encodeHR(bpm: UInt8(bpm), source: source, sampleEpochMs: UInt64(sampledAt.timeIntervalSince1970 * 1000), quality: 2, seq: nextSeq(), tMs: nowMs()) else { return }
        if write(d, to: inputChr) { stats.sentHR += 1 }
    }

    func sendTime() {
        let tz = Int16(TimeZone.current.secondsFromGMT() / 60)
        guard let d = BCLink.encodeTime(epochMs: UInt64(Date().timeIntervalSince1970 * 1000), uncertaintyMs: 100, tzMinutes: tz, seq: nextSeq(), tMs: nowMs()) else { return }
        if write(d, to: inputChr) { stats.sentTime += 1 }
    }

    func sendBattery(phonePct: Int?, watchPct: Int?) {
        guard let d = BCLink.encodeBattery(phonePct: phonePct.map { UInt8($0) }, watchPct: watchPct.map { UInt8($0) }, seq: nextSeq(), tMs: nowMs()) else { return }
        _ = write(d, to: inputChr)
    }

    @discardableResult
    func control(_ cmd: BCLink.Command) -> Bool {
        reqId &+= 1
        guard let d = BCLink.encodeControl(reqId: reqId, cmd: cmd, rideId: UInt16(live?.rideId ?? 0), seq: nextSeq(), tMs: nowMs()),
              let c = controlChr, let p = peripheral, state == .ready else { return false }
        p.writeValue(d, for: c, type: .withResponse)
        return true
    }

    // MARK: internals
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }
    private func nowMs() -> UInt32 { UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince(boardStart) * 1000)) }
    private func setState(_ s: State) { if state != s { state = s } }

    private func write(_ d: Data, to chr: CBCharacteristic?) -> Bool {
        guard let c = chr, let p = peripheral, state == .ready else { return false }
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if type == .withoutResponse, !p.canSendWriteWithoutResponse { return false }   /* drop rather than queue stale GPS */
        guard d.count <= p.maximumWriteValueLength(for: type) else { lastError = "message too long for this link"; return false }
        p.writeValue(d, for: c, type: type)
        return true
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        setState(.connecting)
        central.connect(p, options: nil)
    }

    private func startTimers() {
        timeTimer?.invalidate()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.sendTime() }
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.peripheral?.readRSSI() }
    }

    private func stopTimers() { timeTimer?.invalidate(); rssiTimer?.invalidate(); timeTimer = nil; rssiTimer = nil }
}

extension DeviceLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: if wantConnection || remembered { wantConnection = true; connect() } else { setState(.idle) }
        case .unauthorized: setState(.unauthorized)
        case .poweredOff: setState(.off)
        default: setState(.idle)
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first { peripheral = p; p.delegate = self; wantConnection = true }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "BikeComputer"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i] = (p.identifier, name, rssi.intValue) } else { found.append((p.identifier, name, rssi.intValue)) }
        // one board remembered → connect to it as soon as it is seen; nothing remembered → the user picks from the list
        if let idStr = UserDefaults.standard.string(forKey: rememberedKey), idStr == p.identifier.uuidString { c.stopScan(); attach(p) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        stats.connects += 1
        lastError = nil
        p.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        lastError = error?.localizedDescription
        if wantConnection { attach(p) }   /* iOS keeps the request pending until the board is in range */
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        stats.disconnects += 1
        stopTimers()
        live = nil; liveReceivedAt = nil; rssi = nil
        inputChr = nil; controlChr = nil; liveChr = nil
        if let e = error { lastError = e.localizedDescription }
        if wantConnection { setState(.connecting); c.connect(p, options: nil) } else { setState(.idle) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else { lastError = "BikeComputer service not found"; return }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            switch c.uuid.uuidString {
            case BCLink.infoUUID: setState(.pairing); p.readValue(for: c)       /* first secure read: triggers the passkey dialog on a new phone */
            case BCLink.liveUUID: liveChr = c
            case BCLink.inputUUID: inputChr = c
            case BCLink.controlUUID: controlChr = c
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let e = error {
            let ns = e as NSError
            // CBATTError insufficientAuthentication (5) / insufficientEncryption (15): pairing is in progress or was declined
            if ns.code == 5 || ns.code == 15 { setState(.pairing) } else { lastError = e.localizedDescription }
            return
        }
        guard let d = c.value else { return }
        switch c.uuid.uuidString {
        case BCLink.infoUUID:
            guard let i = BCLink.decodeInfo(d) else { stats.rejected += 1; lastError = "unreadable device info"; return }
            info = i
            UserDefaults.standard.set(p.identifier.uuidString, forKey: rememberedKey); remembered = true
            setState(.ready)
            if let l = liveChr { p.setNotifyValue(true, for: l) }
            if let k = controlChr { p.setNotifyValue(true, for: k) }
            sendTime()
            startTimers()
        case BCLink.liveUUID:
            if let l = BCLink.decodeLive(d) { live = l; liveReceivedAt = Date(); stats.liveMsgs += 1 } else { stats.rejected += 1 }
        case BCLink.controlUUID:
            if let r = BCLink.decodeControlResponse(d) { lastControl = r } else { stats.rejected += 1 }
        default: break
        }
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { if error == nil { rssi = RSSI.intValue } }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let e = error { lastError = e.localizedDescription }
    }
}
