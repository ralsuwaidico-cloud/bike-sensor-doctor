import Foundation
import Network
import HealthKit
import Combine

/// Status colours for the Connections dashboard. Rules (owner, 24 Oct):
///  green  = connected and working · red "!" = disconnected / missing / needs attention, ONLY for connections the rider
///  enabled or the chosen ride configuration requires · amber = connecting / stale / limited · gray = optional, not set up
///  or deliberately off. Pure functions so the rules are unit-tested.
enum ConnStatus: Equatable { case green, red, amber, gray
    var label: String { switch self { case .green: return "connected"; case .red: return "needs attention"; case .amber: return "limited"; case .gray: return "not set up" } } }

enum ConnectionRules {
    /// A connection that is down is red only when it is wanted (enabled by the rider or required by the ride setup).
    static func down(wanted: Bool) -> ConnStatus { wanted ? .red : .gray }

    static func board(linkState: DeviceLink.State, liveFresh: Bool, remembered: Bool, autoConnect: Bool, phoneOnlyMode: Bool, pairingLost: Bool = false) -> ConnStatus {
        if !autoConnect { return .gray }                                   /* rider switched the phone link off */
        if pairingLost, remembered || linkState != .ready { return .red }  /* keys gone on one side: needs the rider (Repair) */
        switch linkState {
        case .ready: return liveFresh ? .green : .amber
        case .connecting, .scanning, .pairing: return .amber
        case .off, .unauthorized: return remembered ? .red : .gray
        case .idle: return remembered && !phoneOnlyMode ? .red : .gray
        }
    }
    static func bluetooth(linkState: DeviceLink.State, boardWanted: Bool) -> ConnStatus {
        switch linkState { case .off, .unauthorized: return boardWanted ? .red : .gray; default: return .green }
    }
    static func gps(authorized: Bool, sharing: Bool, hasFix: Bool, requiredForRides: Bool) -> ConnStatus {
        if !authorized { return requiredForRides ? .red : .gray }
        if !sharing { return .gray }
        return hasFix ? .green : .amber
    }
    static func internet(online: Bool) -> ConnStatus { online ? .green : .amber }   /* the app works offline; never red */
    static func watch(paired: Bool, appInstalled: Bool, hrFresh: Bool, workoutRunning: Bool, enabled: Bool) -> ConnStatus {
        if !enabled { return .gray }
        if hrFresh { return .green }
        if !paired { return .red }
        if !appInstalled { return .red }
        return workoutRunning ? .amber : .gray     /* app there, workout not started: nothing wrong */
    }
    /// Sensors connected to the board (power meter, strap): the board reports them in LIVE.
    static func meter(boardLive: Bool, meterLink: Int?, enabled: Bool) -> ConnStatus {
        guard boardLive, let m = meterLink else { return enabled ? .amber : .gray }
        switch m { case 4: return .green; case 2, 3, 5: return .amber; case 1: return enabled ? .red : .gray; default: return .gray }
    }
    static func strap(boardLive: Bool, hrFromStrap: Bool, enabled: Bool) -> ConnStatus {
        if hrFromStrap { return .green }
        return enabled ? (boardLive ? .amber : .gray) : .gray
    }
    /// Generic colour for a source from the hub's source model (direct BLE sensors, planned providers): red only when the
    /// rider configured it (paired / enabled) and it is missing; planned or not set up is gray, never red or green.
    static func source(_ s: SourceStatus) -> ConnStatus {
        switch s.state {
        case .connected: return s.quality == .stale ? .amber : .green
        case .connecting: return .amber
        case .disconnected, .notAuthorized: return down(wanted: s.configured)
        case .notConfigured, .planned: return .gray
        }
    }
    static func health(wanted: Bool, authorized: Bool, available: Bool) -> ConnStatus {
        guard available else { return .gray }
        if authorized { return .green }
        return wanted ? .red : .gray
    }
}

/// Internet reachability for the Connections dashboard (the app itself makes no network calls in this build).
final class Reachability: ObservableObject {
    @Published private(set) var online = false
    @Published private(set) var kind = "unknown"
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.online = p.status == .satisfied
                self?.kind = p.usesInterfaceType(.wifi) ? "Wi-Fi" : p.usesInterfaceType(.cellular) ? "cellular" : p.status == .satisfied ? "other" : "offline"
            }
        }
        monitor.start(queue: DispatchQueue(label: "bc.reachability"))
    }
    deinit { monitor.cancel() }
}

/// Apple Health access. "Connected" is reported only from HealthKit's own authorization status for writing workouts;
/// read authorization is not disclosed by iOS, so reading rights are described, never claimed.
final class HealthAccess: ObservableObject {
    @Published private(set) var available = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var workoutWriteAuthorized = false
    @Published private(set) var lastError: String?
    private let store = HKHealthStore()

    init() { refresh() }

    func refresh() {
        guard available else { return }
        workoutWriteAuthorized = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Asks iOS for the permissions. The completion runs on the main queue with the refreshed status.
    func request(_ done: ((Bool) -> Void)? = nil) {
        guard available else { done?(false); return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(e) }
        store.requestAuthorization(toShare: share, read: read) { [weak self] ok, err in
            DispatchQueue.main.async {
                self?.lastError = err?.localizedDescription
                self?.refresh()
                done?(ok && (self?.workoutWriteAuthorized ?? false))
            }
        }
    }
}
