import Foundation
import CoreBluetooth
import Combine
import UIKit

/// Connection to the Waveshare cycling computer ("BikeComputer Link", protocol v1.2.1). The board is the hub: this class
/// mirrors its live values and feeds it GPS, time and watch heart rate. It never invents a value: a field missing from
/// the board's message is nil and shown as "--".
///
/// 0.8.0: explicit connection STAGES (Searching → Found → Connecting → Pairing → Authenticating → Connected → Syncing
/// profile → Ready) with a plain-language failure reason per stage, a 20-second watchdog per stage so "Connecting…" is
/// never indefinite, a Repair flow for a board that lost this phone's keys, a stage log for the diagnostics page and
/// the board's LINK_DIAG event. The coarse `state` stays for the rest of the app (`.ready` = usable link).
final class DeviceLink: NSObject, ObservableObject {
    enum State: String { case off = "Bluetooth off", idle = "Not connected", scanning = "Searching…", connecting = "Connecting…",
                         pairing = "Pairing — type the code shown on the Waveshare", ready = "Connected", unauthorized = "Bluetooth permission needed" }

    /// Fine-grained stage of the current attempt (the brief's list) plus the resting states.
    enum Stage: String, CaseIterable {
        case off = "Bluetooth off", unauthorized = "Bluetooth permission needed", idle = "Not connected"
        case searching = "Searching", found = "Found", waiting = "Waiting for the board", connecting = "Connecting", pairing = "Pairing"
        case authenticating = "Authenticating", connected = "Connected", syncingProfile = "Syncing profile", ready = "Ready", failed = "Failed"
        var order: Int { Stage.allCases.firstIndex(of: self) ?? 0 }
        var isAttempt: Bool { [.searching, .found, .waiting, .connecting, .pairing, .authenticating, .connected, .syncingProfile].contains(self) }
    }
    /// What the rider should do next after a failure; the Connections screen turns it into the right button.
    enum Action: Equatable { case none, retry, repair, openSettings, bluetoothOn, permission, search }
    struct Failure: Equatable {
        var stage: Stage
        var reason: String
        var action: Action
        var at: Date
        var code: String?
    }
    struct LogLine: Identifiable, Equatable { let id = UUID(); let at: Date; let text: String }

    @Published private(set) var state: State = .idle
    @Published private(set) var stage: Stage = .idle
    @Published private(set) var failure: Failure?
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var info: BCLink.Info?
    @Published private(set) var live: BCLink.Live?
    @Published private(set) var liveReceivedAt: Date?
    @Published private(set) var remembered = false
    @Published private(set) var rssi: Int?
    @Published private(set) var lastControl: BCLink.ControlResponse?
    @Published private(set) var lastError: String?
    @Published private(set) var stats = Stats()
    @Published private(set) var found: [(id: UUID, name: String, rssi: Int)] = []
    /// Ride history sync (ios/SYNC_PROPOSAL.md). Inactive until the board's INFO has RIDE_SYNC.
    @Published private(set) var syncStatus = "not supported by this firmware"
    @Published private(set) var syncedRides = 0
    /// 1.2 (firmware 0.6.0): Wi-Fi provisioning, athlete profile and device settings — all gated on the board's caps.
    @Published private(set) var wifiNetworks: [BCLink.WiFiNetwork] = []
    @Published private(set) var wifiScanning = false
    @Published private(set) var wifiScanError: String?
    @Published private(set) var wifiStatus: BCLink.WiFiStatus?
    @Published private(set) var wifiStatusAt: Date?
    @Published private(set) var boardProfile: BCLink.ProfileMessage?
    @Published private(set) var boardProfileAt: Date?
    @Published private(set) var lastProfileAck: BCLink.ProfileAck?
    @Published private(set) var boardSettings: BCLink.SettingsMessage?
    @Published private(set) var boardSettingsAt: Date?
    @Published private(set) var lastSettingsReply: BCLink.SettingsMessage?
    @Published private(set) var lastConnectedAt: Date?
    @Published private(set) var lastDisconnectedAt: Date?
    /// 1.2.1: the board's own account of the previous link (event once per connection) and the last battery notice.
    @Published private(set) var linkDiag: BCLink.LinkDiag?
    @Published private(set) var linkDiagAt: Date?
    @Published private(set) var batteryNotice: BCLink.Event?
    /// The board id (INFO tag 07) seen on the last good connection, so a board that took a new Bluetooth identity after a
    /// Repair / Forget is recognised as the same device. The stale CoreBluetooth identifier is kept only for diagnostics.
    @Published private(set) var knownDeviceId: String? = UserDefaults.standard.string(forKey: "bikecomputer.deviceId")
    @Published private(set) var staleIdentifier: String? = UserDefaults.standard.string(forKey: "bikecomputer.stale")
    @Published private(set) var repairing = false
    /// Off = the phone neither connects nor reconnects on its own (local choice; the board's own link switch is a device setting).
    var autoConnect = true { didSet { if autoConnect, remembered { connect() } else if !autoConnect { disconnect() } } }
    var onProfileAck: ((BCLink.ProfileAck) -> Void)?
    var onBoardProfile: ((BCLink.ProfileMessage) -> Void)?
    var onSettingsReply: ((BCLink.SettingsMessage) -> Void)?
    var onReady: (() -> Void)?
    var onBoardRide: ((BCLink.RideSummary, String) -> Void)?
    var onEvent: ((BCLink.Event) -> Void)?
    /// Highest board ride id already stored for a given board id — the Store provides it so paging resumes where it left off.
    var highestStoredRideId: ((String) -> Int)?
    /// Key for this board on this phone: its BLE address when the firmware sends it, else the CoreBluetooth identifier.
    var boardId: String { info?.deviceId ?? peripheral?.identifier.uuidString ?? "unknown" }
    var rememberedIdentifier: String? { UserDefaults.standard.string(forKey: rememberedKey) }

    struct Stats { var connects = 0, liveMsgs = 0, rejected = 0, sentGPS = 0, sentHR = 0, sentTime = 0, disconnects = 0, events = 0 }

    /// Seconds a stage may last before it is reported as failed (the brief: never an indefinite "Connecting…").
    static let stageTimeout: TimeInterval = 20

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var inputChr: CBCharacteristic?, controlChr: CBCharacteristic?, liveChr: CBCharacteristic?, syncChr: CBCharacteristic?, eventsChr: CBCharacteristic?
    private var syncInFlight = false
    private var seq: UInt16 = 0
    private var reqId: UInt16 = 0
    private var timeTimer: Timer?
    private var rssiTimer: Timer?
    private var stageTimer: Timer?
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
    var isConnected: Bool { peripheral?.state == .connected && (stage == .ready || stage == .syncingProfile || stage == .connected || stage == .pairing || stage == .authenticating) }
    var appBackgroundState: String { switch UIApplication.shared.applicationState { case .active: return "active"; case .inactive: return "inactive"; case .background: return "background"; @unknown default: return "unknown" } }

    // MARK: user actions
    func connect() {
        wantConnection = true
        failure = nil
        guard central.state == .poweredOn else { noteBluetoothState(); return }
        if let idStr = UserDefaults.standard.string(forKey: rememberedKey), let id = UUID(uuidString: idStr),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p)
        } else {
            startScan()
        }
    }

    func connect(to id: UUID) {
        wantConnection = true
        failure = nil
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        UserDefaults.standard.set(id.uuidString, forKey: rememberedKey)
        remembered = true
        note("Chosen: \(p.name ?? "BikeComputer") (\(id.uuidString.prefix(8)))")
        attach(p)
    }

    func disconnect() {
        wantConnection = false
        central.stopScan()
        stageTimer?.invalidate()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        setState(.idle); setStage(.idle)
    }

    /// Forgets the board here. The board's own bond is removed with "Forget phone" on its Phone page; iOS removes its
    /// bond in Settings > Bluetooth > BikeComputer > Forget This Device.
    func forget() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        UserDefaults.standard.removeObject(forKey: "bikecomputer.deviceId")
        remembered = false; knownDeviceId = nil
        info = nil; live = nil; failure = nil; repairing = false
        note("Forgot the BikeComputer on this phone")
    }

    /// Repair a pairing the board no longer holds (iOS: "Peer removed pairing information"). With firmware 0.7.0 the
    /// board takes a NEW Bluetooth identity when the rider holds REPAIR on its Phone screen, so iOS sees a new device and
    /// pairs again with the code. This phone therefore drops the remembered identifier (kept as "stale" for diagnostics),
    /// keeps the board id, scans by the Link service and accepts the next board that shows up. If iOS still holds the
    /// old bond for the SAME identity, pairing fails again and the failure names the one step only the rider can do:
    /// Settings › Bluetooth › BikeComputer Link › Forget This Device.
    func repair() {
        if let old = UserDefaults.standard.string(forKey: rememberedKey) { staleIdentifier = old; UserDefaults.standard.set(old, forKey: "bikecomputer.stale") }
        central.stopScan()
        stageTimer?.invalidate()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        remembered = false
        info = nil; live = nil; failure = nil
        repairing = true
        wantConnection = true
        note("Repair started: looking for the board under its new identity")
        startScan()
    }

    func startScan() {
        guard central.state == .poweredOn else { noteBluetoothState(); return }
        found = []
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        setState(.scanning); setStage(.searching)
    }

    /// The Connections screen's "Retry profile sync": asks the board for its profile again (the sync layer compares).
    func retryProfile() { guard state == .ready else { return }; setStage(.syncingProfile); profileGet() }

    /// Called by the profile-sync layer when the sync question is settled (in sync, needs confirmation or unsupported).
    func profileSyncSettled() { if stage == .syncingProfile || stage == .connected { setStage(.ready) } }
    func profileSyncFailed(_ reason: String) { if stage == .syncingProfile { fail(.syncingProfile, reason, .retry) ; setStage(.ready) } }

    /// Opens the iOS Settings app (the Bluetooth › Forget step cannot be done from inside an app).
    static func openSettings() { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }

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

    /// Asks the board for rides after the highest id already stored. Does nothing when the firmware lacks RIDE_SYNC.
    func startSync() {
        guard state == .ready, let i = info, i.hasRideSync, let c = syncChr, let p = peripheral else { syncStatus = info?.hasRideSync == false ? "not supported by firmware \(info?.fw ?? "?") — sync coming" : syncStatus; return }
        let after = highestStoredRideId?(boardId) ?? 0
        guard let d = BCLink.encodeSyncRequest(afterRideId: UInt16(clamping: after), maxCount: 50, seq: nextSeq(), tMs: nowMs()) else { return }
        syncInFlight = true; syncStatus = "syncing from ride \(after + 1)…"
        p.writeValue(d, for: c, type: .withResponse)
    }

    // MARK: internals
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }
    private func nowMs() -> UInt32 { UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince(boardStart) * 1000)) }
    private func setState(_ s: State) { if state != s { state = s } }

    private func setStage(_ s: Stage) {
        if stage != s { stage = s; note(s.rawValue) }
        stageTimer?.invalidate()
        guard s.isAttempt, s != .waiting else { return }
        stageTimer = Timer.scheduledTimer(withTimeInterval: DeviceLink.stageTimeout, repeats: false) { [weak self] _ in self?.stageTimedOut(s) }
    }

    private func stageTimedOut(_ s: Stage) {
        guard stage == s else { return }
        switch s {
        case .searching:
            fail(.searching, repairing ? "No BikeComputer found. Hold REPAIR on the board's Phone screen (it then advertises under a new identity) and keep it within a metre." : "No BikeComputer found. The board must be on, within a metre, with Phone link ON; firmware 0.5.0 stops advertising when its screen sleeps.", .search)
            central.stopScan(); setState(.idle)
        case .found: fail(.found, "The board was seen but not chosen.", .search)
        case .connecting:
            // iOS keeps the connect request pending until the board advertises: not an error, but say what is going on.
            setStage(.waiting); failure = Failure(stage: .connecting, reason: "The board is not answering — probably out of range, off, or in deep sleep. The phone keeps trying in the background.", action: .retry, at: Date(), code: nil)
        case .pairing: fail(.pairing, "Pairing did not complete. Type the 6-digit code shown on the board, or the board may still hold keys for another phone.", .repair)
        case .authenticating: fail(.authenticating, "The encrypted link was not established within 20 s.", .repair)
        case .connected: fail(.connected, "Connected but the board sent no device info.", .retry)
        case .syncingProfile: profileSyncFailed("The board did not answer the profile request within 20 s."); setStage(.ready)
        default: break
        }
    }

    private func fail(_ s: Stage, _ reason: String, _ action: Action, code: String? = nil) {
        failure = Failure(stage: s, reason: reason, action: action, at: Date(), code: code)
        lastError = reason
        note("Failed while \(s.rawValue.lowercased()): \(reason)")
        stage = .failed
    }

    private func note(_ t: String) {
        log.append(LogLine(at: Date(), text: t))
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    private func noteBluetoothState() {
        switch central.state {
        case .poweredOff: setState(.off); setStage(.off); failure = Failure(stage: .off, reason: "Bluetooth is off on the phone.", action: .bluetoothOn, at: Date(), code: nil)
        case .unauthorized: setState(.unauthorized); setStage(.unauthorized); failure = Failure(stage: .unauthorized, reason: "Cyclift has no Bluetooth permission.", action: .permission, at: Date(), code: nil)
        default: break
        }
    }

    /// CoreBluetooth / ATT errors in plain words plus the action that fixes them.
    static func describe(_ e: Error) -> (reason: String, action: Action, code: String) {
        let ns = e as NSError
        let code = "\(ns.domain) \(ns.code)"
        if ns.domain == CBErrorDomain {
            switch CBError.Code(rawValue: ns.code) {
            case .peerRemovedPairingInformation: return ("The BikeComputer no longer has this phone's keys (it was reset or the phone was forgotten on the board). The iPhone still holds the old pairing.", .repair, code)
            case .encryptionTimedOut: return ("Encryption timed out — the board may hold keys for a different phone.", .repair, code)
            case .connectionTimeout: return ("The connection attempt timed out (out of range or the board is asleep).", .retry, code)
            case .connectionFailed: return ("The connection failed to establish.", .retry, code)
            case .peripheralDisconnected: return ("The board ended the connection.", .retry, code)
            case .unknownDevice, .invalidHandle: return ("The remembered BikeComputer is unknown to this phone (it probably took a new identity).", .repair, code)
            case .connectionLimitReached: return ("iOS has too many Bluetooth connections open.", .retry, code)
            case .uuidNotAllowed: return ("Bluetooth access is restricted on this phone.", .permission, code)
            default: break
            }
        }
        if ns.domain == CBATTErrorDomain {
            switch ns.code {
            case 5, 15, 8: return ("The BikeComputer no longer has this phone's keys — the secure read was refused (insufficient authentication / encryption).", .repair, code)
            default: break
            }
        }
        return (ns.localizedDescription, .retry, code)
    }

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
        if p.state == .connected { setState(.connecting); setStage(.connected); p.discoverServices([serviceUUID]); return }   /* restored by iOS while we were suspended */
        setState(.connecting); setStage(.connecting)
        // iOS keeps a pending connect alive (also in the background with bluetooth-central) until the board advertises again:
        // this is the reconnect-without-touching-the-board path. No scanning, no polling.
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true, CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    // MARK: 1.2 Wi-Fi provisioning
    func wifiScan() {
        guard state == .ready, info?.hasWiFi == true, let d = BCLink.encodeWiFiScanRequest(max: 16, seq: nextSeq(), tMs: nowMs()) else { return }
        wifiNetworks = []; wifiScanning = true; wifiScanError = nil
        _ = writeControl(d)
    }
    func wifiStatusRequest() { guard info?.hasWiFi == true, let d = BCLink.encodeWiFiStatusRequest(seq: nextSeq(), tMs: nowMs()) else { return }; _ = writeControl(d) }
    /// Sends the credentials over the encrypted link. The password is not kept anywhere on the phone.
    @discardableResult
    func wifiSet(ssid: String, password: String) -> Bool {
        guard info?.hasWiFi == true, let d = BCLink.encodeWiFiSet(ssid: ssid, password: password, seq: nextSeq(), tMs: nowMs()) else { return false }
        return writeControl(d)
    }
    @discardableResult
    func wifiForget(ssid: String) -> Bool { guard info?.hasWiFi == true, let d = BCLink.encodeWiFiForget(ssid: ssid, seq: nextSeq(), tMs: nowMs()) else { return false }; return writeControl(d) }

    // MARK: 1.2 profile and settings
    func profileGet() { guard info?.hasProfileSync == true, let d = BCLink.encodeProfileGet(seq: nextSeq(), tMs: nowMs()) else { return }; _ = writeControl(d) }
    @discardableResult
    func profileSet(_ m: BCLink.ProfileMessage) -> Bool { guard info?.hasProfileSync == true, let d = BCLink.encodeProfileSet(m, seq: nextSeq(), tMs: nowMs()) else { return false }; return writeControl(d) }
    func settingsGet() { guard info?.hasSettings == true, let d = BCLink.encodeSettingsGet(seq: nextSeq(), tMs: nowMs()) else { return }; _ = writeControl(d) }
    @discardableResult
    func settingsSet(_ m: BCLink.SettingsMessage) -> Bool { guard info?.hasSettings == true, let d = BCLink.encodeSettingsSet(m, seq: nextSeq(), tMs: nowMs()) else { return false }; return writeControl(d) }

    private func writeControl(_ d: Data) -> Bool {
        guard let c = controlChr, let p = peripheral, state == .ready else { return false }
        p.writeValue(d, for: c, type: .withResponse)
        return true
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
        case .poweredOn:
            if failure?.action == .bluetoothOn || failure?.action == .permission { failure = nil }
            if (wantConnection || remembered) && autoConnect { wantConnection = true; connect() } else { setState(.idle); setStage(.idle) }
        case .unauthorized: noteBluetoothState()
        case .poweredOff: noteBluetoothState()
        default: setState(.idle); setStage(.idle)
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first { peripheral = p; p.delegate = self; wantConnection = true; note("Restored by iOS in the background") }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "BikeComputer"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i] = (p.identifier, name, rssi.intValue) } else { found.append((p.identifier, name, rssi.intValue)); note("Found \(name) (\(p.identifier.uuidString.prefix(8))) \(rssi.intValue) dBm") }
        if stage == .searching { setStage(.found) }
        // one board remembered → connect to it as soon as it is seen; nothing remembered → the user picks from the list
        if let idStr = UserDefaults.standard.string(forKey: rememberedKey), idStr == p.identifier.uuidString { c.stopScan(); attach(p); return }
        // repairing: the board advertises under a NEW identity — accept the first board that is not the stale one
        if repairing, p.identifier.uuidString != staleIdentifier {
            c.stopScan()
            UserDefaults.standard.set(p.identifier.uuidString, forKey: rememberedKey); remembered = true
            note("Repair: new identity \(p.identifier.uuidString.prefix(8)) accepted")
            attach(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        stats.connects += 1
        lastError = nil; lastConnectedAt = Date()
        setStage(.connected)
        p.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if let e = error { let d = DeviceLink.describe(e); fail(.connecting, d.reason, d.action, code: d.code) }
        if wantConnection, failure?.action != .repair { attach(p) }   /* iOS keeps the request pending until the board is in range */
        else { setState(.idle) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        stats.disconnects += 1; lastDisconnectedAt = Date()
        stopTimers(); stageTimer?.invalidate()
        live = nil; liveReceivedAt = nil; rssi = nil
        inputChr = nil; controlChr = nil; liveChr = nil; syncChr = nil; eventsChr = nil; syncInFlight = false
        wifiScanning = false; wifiStatus = nil; boardSettings = nil
        let wasPairing = stage == .pairing || stage == .authenticating
        if let e = error {
            let d = DeviceLink.describe(e)
            // a drop in the middle of pairing with an encryption error = the board lost this phone's keys
            if wasPairing && (d.action == .repair) { fail(.pairing, d.reason, .repair, code: d.code) }
            else if d.action == .repair { fail(.authenticating, d.reason, .repair, code: d.code) }
            else { lastError = d.reason; note("Disconnected: \(d.reason) [\(d.code)]") }
        } else { note("Disconnected") }
        if wantConnection, autoConnect, failure?.action != .repair { attach(p) } else { setState(.idle); if failure == nil { setStage(.idle) } }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { let d = DeviceLink.describe(e); fail(.connected, d.reason, d.action, code: d.code); return }
        guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else { fail(.connected, "The BikeComputer Link service was not found on this device.", .search); return }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let e = error { let d = DeviceLink.describe(e); fail(.connected, d.reason, d.action, code: d.code); return }
        for c in s.characteristics ?? [] {
            switch c.uuid.uuidString {
            case BCLink.infoUUID: setState(.pairing); setStage(.pairing); p.readValue(for: c)       /* first secure read: triggers the passkey dialog on a new phone */
            case BCLink.liveUUID: liveChr = c
            case BCLink.inputUUID: inputChr = c
            case BCLink.controlUUID: controlChr = c
            case BCLink.syncUUID: syncChr = c
            case BCLink.eventsUUID: eventsChr = c
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let e = error {
            let ns = e as NSError
            // CBATTError insufficientAuthentication (5) / insufficientEncryption (15): pairing is in progress (the passkey
            // dialog is up) — iOS retries the read after pairing. A SECOND refusal or a CBError means the keys are gone.
            if ns.domain == CBATTErrorDomain, ns.code == 5 || ns.code == 15, stage == .pairing { setStage(.authenticating); note("Secure read refused once — waiting for the passkey dialog") }
            else if state == .ready { let d = DeviceLink.describe(e); lastError = d.reason; note("Read error: \(d.reason) [\(d.code)]") }
            else { let d = DeviceLink.describe(e); fail(.authenticating, d.reason, d.action, code: d.code) }
            return
        }
        guard let d = c.value else { return }
        switch c.uuid.uuidString {
        case BCLink.infoUUID:
            guard let i = BCLink.decodeInfo(d) else { stats.rejected += 1; fail(.connected, "unreadable device info", .retry); return }
            info = i
            UserDefaults.standard.set(p.identifier.uuidString, forKey: rememberedKey); remembered = true
            if let id = i.deviceId {
                if let k = knownDeviceId, k != id, !repairing { note("Note: a different board (\(id)); the known one was \(k)") }
                if repairing, let k = knownDeviceId, k == id { note("Repair complete: same board \(id) under its new identity") }
                knownDeviceId = id; UserDefaults.standard.set(id, forKey: "bikecomputer.deviceId")
            }
            repairing = false; failure = nil
            setState(.ready); setStage(.connected)
            if let l = liveChr { p.setNotifyValue(true, for: l) }
            if let k = controlChr { p.setNotifyValue(true, for: k) }
            if let ev = eventsChr { p.setNotifyValue(true, for: ev) }
            if i.hasRideSync, let sc = syncChr { p.setNotifyValue(true, for: sc); syncStatus = "supported"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startSync() } }
            else { syncStatus = "not supported by firmware \(i.fw) — sync coming" }
            sendTime()
            startTimers()
            if i.hasWiFi { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.wifiStatusRequest() } }
            if i.hasSettings { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.settingsGet() } }
            if i.hasProfileSync {
                setStage(.syncingProfile)
                // firmware 0.7.0 sends PROFILE by itself ("hello"); older 0.6.x needs the request
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in guard let self else { return }; if self.boardProfileAt == nil || (self.lastConnectedAt.map { self.boardProfileAt! < $0 } ?? true) { self.profileGet() } }
            } else { setStage(.ready) }
            onReady?()
        case BCLink.liveUUID:
            if let l = BCLink.decodeLive(d) { live = l; liveReceivedAt = Date(); stats.liveMsgs += 1 } else { stats.rejected += 1 }
        case BCLink.controlUUID:
            handleControl(d)
        case BCLink.syncUUID:
            if let r = BCLink.decodeSyncRide(d) { syncedRides += 1; onBoardRide?(r, boardId) }
            else if let e = BCLink.decodeSyncEnd(d) {
                syncInFlight = false
                syncStatus = "\(e.total) rides on the board · \(syncedRides) received"
                if e.more { startSync() }
            } else { stats.rejected += 1 }
        case BCLink.eventsUUID:
            guard let ev = BCLink.decodeEvent(d) else { stats.rejected += 1; return }
            stats.events += 1
            if let diag = BCLink.linkDiag(from: ev) { linkDiag = diag; linkDiagAt = Date(); note("Board: previous link ended by \(diag.reasonText); \(diag.bonds) phone(s) remembered; profile \(diag.syncText)") }
            else if ev.isBatteryNotice { batteryNotice = ev }
            onEvent?(ev)
        default: break
        }
    }

    /// Control characteristic: ride-control replies (v1) and the 1.2 Wi-Fi / profile / settings replies, told apart by the type byte.
    private func handleControl(_ d: Data) {
        guard let t = d.first, let type = BCLink.MsgType(rawValue: t) else { stats.rejected += 1; return }
        switch type {
        case .ctrlResp: if let r = BCLink.decodeControlResponse(d) { lastControl = r } else { stats.rejected += 1 }
        case .wifiScanResult:
            if let n = BCLink.decodeWiFiScanResult(d) { if let i = wifiNetworks.firstIndex(where: { $0.ssid == n.ssid }) { wifiNetworks[i] = n } else { wifiNetworks.append(n) }; wifiNetworks.sort { $0.rssi > $1.rssi } } else { stats.rejected += 1 }
        case .wifiScanEnd:
            wifiScanning = false
            if let e = BCLink.decodeWiFiScanEnd(d) { wifiScanError = e.errorText } else { stats.rejected += 1 }
        case .wifiStatus:
            if let s = BCLink.decodeWiFiStatus(d) { wifiStatus = s; wifiStatusAt = Date() } else { stats.rejected += 1 }
        case .profile:
            if let p = BCLink.decodeProfile(d) { boardProfile = p; boardProfileAt = Date(); note("Board profile v\(p.version) (\(p.source == 1 ? "phone-synced" : "device-only"))"); onBoardProfile?(p) } else { stats.rejected += 1 }
        case .profileAck:
            if let a = BCLink.decodeProfileAck(d) { lastProfileAck = a; note("Profile ack v\(a.version): \(a.statusText)"); onProfileAck?(a) } else { stats.rejected += 1 }
        case .settings:
            if let s = BCLink.decodeSettings(d) { boardSettings = s; boardSettingsAt = Date(); lastSettingsReply = s; onSettingsReply?(s) } else { stats.rejected += 1 }
        default: stats.rejected += 1
        }
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { if error == nil { rssi = RSSI.intValue } }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let e = error { lastError = DeviceLink.describe(e).reason }
    }
}
