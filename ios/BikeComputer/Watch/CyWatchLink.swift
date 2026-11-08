import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

// Cyclift Watch (LILYGO) companion — the iPhone side of protocol v1 (OWNERSHIP.md: the phone owns identity, plan, FTP,
// GPS and live sensor values; the watch sends events with (deviceId, seq) and the phone acknowledges cumulatively).
// Transport-independent core (`CyWatchSession`, unit-tested) + a CoreBluetooth central that drives it. Nothing here
// invents data: a Live frame carries only readings the SensorHub currently has, with their age; GPS only real fixes.

/// What the phone knows about the connected watch.
struct CyWatchStatus: Equatable { var batteryPct: Int; var charging: Bool; var freeHeap: Int; var phase: Int; var pendingEvents: Int; var at: Date }

/// Transport-independent protocol session: sequence numbers, frame reassembly, duplicate suppression with a persisted
/// cumulative ack per device, and the outbound frames the transport must send.
final class CyWatchSession {
    private(set) var txSeq: UInt16 = 0
    private var rx: [UInt8] = []
    /// Highest acknowledged event seq per watch device id — persisted so a reconnect never re-applies an old event.
    private(set) var acked: [String: UInt32]
    private let saveAcked: ([String: UInt32]) -> Void
    var onEvent: (CyWatchWire.Event) -> Void = { _ in }
    var onStatus: (CyWatchWire.Status) -> Void = { _ in }
    private(set) var outbox: [[UInt8]] = []
    private(set) var dropped = 0      // frames that failed CRC / version — surfaced in Connections, never hidden

    init(acked: [String: UInt32] = [:], saveAcked: @escaping ([String: UInt32]) -> Void = { _ in }) { self.acked = acked; self.saveAcked = saveAcked }

    func send(_ type: CyWatchWire.MsgType, _ payload: [UInt8]) {
        txSeq &+= 1
        outbox.append(CyWatchWire.encode(.init(type: type, seq: txSeq, payload: payload)))
    }
    func takeOutbox() -> [[UInt8]] { let o = outbox; outbox.removeAll(); return o }

    /// Feeds bytes from the transport (a notification may carry part of a frame or several frames).
    func receive(_ bytes: [UInt8]) {
        rx.append(contentsOf: bytes)
        while rx.count >= 6 {
            if let len = headerLength(at: 0) {
                guard rx.count >= len + 8 else { return }            // a plausible frame is still arriving
                if let f = CyWatchWire.decode(Array(rx[0..<(len + 8)])) { rx.removeFirst(len + 8); handle(f); continue }
            }
            // not a frame here: resynchronise on the next position that holds a complete valid frame, else on the next
            // plausible header still arriving, else discard everything
            dropped += 1
            var fallback: Int? = nil
            var resumed = false
            for j in 1..<rx.count where rx[j] == CyWatchWire.protocolVersion {
                guard let len = headerLength(at: j) else { continue }
                if j + len + 8 <= rx.count {
                    if CyWatchWire.decode(Array(rx[j..<(j + len + 8)])) != nil { rx.removeFirst(j); resumed = true; break }
                } else if fallback == nil { fallback = j }
            }
            if resumed { continue }
            if let f = fallback { rx.removeFirst(f); return }
            rx.removeAll(); return
        }
    }
    /// Payload length if a plausible header (version, known type, sane length) starts at `i`.
    private func headerLength(at i: Int) -> Int? {
        guard i + 6 <= rx.count, rx[i] == CyWatchWire.protocolVersion, CyWatchWire.MsgType(rawValue: rx[i + 1]) != nil else { return nil }
        let len = Int(rx[i + 4]) | Int(rx[i + 5]) << 8
        return len <= 1024 ? len : nil
    }
    private func handle(_ f: CyWatchWire.Frame) {
        switch f.type {
        case .event:
            guard let e = CyWatchWire.Event.decode(f.payload) else { dropped += 1; return }
            let last = acked[e.deviceId] ?? 0
            if e.seq > last {
                onEvent(e)
                acked[e.deviceId] = e.seq; saveAcked(acked)
            }
            // cumulative ack — also for duplicates, so a watch that missed the first ack stops resending
            send(.ack, CyWatchWire.encodeAck(acked[e.deviceId] ?? e.seq))
        case .status: if let s = CyWatchWire.Status.decode(f.payload) { onStatus(s) } else { dropped += 1 }
        default: break   // hello / error: tolerated, not acted on in v1
        }
    }
}

#if canImport(CoreBluetooth)
/// CoreBluetooth central for the watch's NUS-style service. One watch at a time; auto-reconnects while enabled.
final class CyWatchLink: NSObject, ObservableObject {
    enum State: Equatable { case off, bluetoothOff, scanning, connecting, connected(String), failed(String) }
    @Published private(set) var state: State = .off
    @Published private(set) var status: CyWatchStatus?
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var droppedFrames = 0

    let session: CyWatchSession
    /// Providers set by the app (read on each tick); nil = nothing to send.
    var liveProvider: () -> CyWatchWire.Live? = { nil }
    var gpsProvider: () -> CyWatchWire.Gps? = { nil }
    var planProvider: () -> CyWatchWire.PlanToday? = { nil }
    var cachedProvider: () -> CyWatchWire.Cached? = { nil }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var timer: Timer?
    private var lastPlan: [UInt8]? = nil, lastCached: [UInt8]? = nil, lastTimeSync: Date? = nil
    private let serviceUUID = CBUUID(string: CyWatchWire.serviceUUID), txUUID = CBUUID(string: CyWatchWire.txUUID), rxUUID = CBUUID(string: CyWatchWire.rxUUID)
    private var enabled = false

    override init() {
        let saved = (UserDefaults.standard.dictionary(forKey: "cyw.acked") as? [String: Int]) ?? [:]
        session = CyWatchSession(acked: saved.mapValues { UInt32($0) }, saveAcked: { UserDefaults.standard.set($0.mapValues { Int($0) }, forKey: "cyw.acked") })
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        session.onStatus = { [weak self] s in self?.status = CyWatchStatus(batteryPct: Int(s.batteryPct), charging: s.charging, freeHeap: Int(s.freeHeap), phase: Int(s.phase), pendingEvents: Int(s.pendingEvents), at: Date()) }
    }

    func start() { enabled = true; scanIfPossible() }
    func stop() {
        enabled = false; timer?.invalidate(); timer = nil
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        if central.state == .poweredOn { central.stopScan() }
        peripheral = nil; rxChar = nil; state = .off
    }

    private func scanIfPossible() {
        guard enabled else { return }
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        state = .scanning
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    private func onConnected() {
        lastPlan = nil; lastCached = nil; lastTimeSync = nil
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }
    /// Once a second: time sync (on connect, then every 10 min), plan / cached when they change, live + GPS when present.
    private func tick() {
        guard rxChar != nil else { return }
        let now = Date()
        if lastTimeSync.map({ now.timeIntervalSince($0) > 600 }) ?? true { session.send(.timeSync, CyWatchWire.TimeSync(now).encode()); lastTimeSync = now }
        if let p = planProvider()?.encode(), p != lastPlan { session.send(.planToday, p); lastPlan = p }
        if let c = cachedProvider()?.encode(), c != lastCached { session.send(.cached, c); lastCached = c }
        if let l = liveProvider() { session.send(.live, l.encode()) }
        if let g = gpsProvider() { session.send(.gps, g.encode()) }
        flush()
    }
    func sendCoach(_ c: CyWatchWire.Coach) { session.send(.coach, c.encode()); flush() }

    private func flush() {
        guard let p = peripheral, let rx = rxChar else { return }
        let withResponse = !rx.properties.contains(.writeWithoutResponse)
        let mtu = max(20, p.maximumWriteValueLength(for: withResponse ? .withResponse : .withoutResponse))
        for frame in session.takeOutbox() {
            var i = 0
            while i < frame.count { let n = min(mtu, frame.count - i); p.writeValue(Data(frame[i..<(i + n)]), for: rx, type: withResponse ? .withResponse : .withoutResponse); i += n }
        }
    }
}

extension CyWatchLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { scanIfPossible() } else if enabled { state = .bluetoothOff }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral == nil else { return }
        peripheral = p; p.delegate = self; c.stopScan(); state = .connecting; c.connect(p, options: nil)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([serviceUUID]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { peripheral = nil; state = .failed(error?.localizedDescription ?? "Could not connect"); scanIfPossible() }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        peripheral = nil; rxChar = nil; timer?.invalidate(); timer = nil
        if enabled { scanIfPossible() } else { state = .off }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else { state = .failed("Watch service not found"); central.cancelPeripheralConnection(p); return }
        p.discoverCharacteristics([txUUID, rxUUID], for: s)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == txUUID { p.setNotifyValue(true, for: ch) }
            if ch.uuid == rxUUID { rxChar = ch }
        }
        if rxChar != nil { state = .connected(p.name ?? "Cyclift Watch"); onConnected() }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == txUUID, let d = ch.value else { return }
        lastFrameAt = Date()
        session.receive([UInt8](d))
        droppedFrames = session.dropped
        flush()   // acks
    }
}
#endif
