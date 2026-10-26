import Foundation
import WatchConnectivity
import HealthKit

/// iPhone side of the iPhone <-> Apple Watch connection.
/// Live heart rate arrives on two channels and passes ONE gate (`WatchHRIngest`): the mirrored HealthKit workout
/// session (primary, works with the phone app in the background — WatchWorkoutMirror) and WatchConnectivity messages
/// (secondary, only while the watch sees the phone app as reachable). A sample is counted once (de-duplicated by its
/// HealthKit sample time), a reading older than 6 s is never shown or forwarded, and nothing is held.
/// Also: pairing/reachability, the version handshake (the watch reports its build) and the ping test.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var supported = WCSession.isSupported()
    @Published private(set) var activated = false
    @Published private(set) var paired = false
    @Published private(set) var appInstalled = false
    @Published private(set) var reachable = false
    @Published private(set) var lastResult = "Not tested yet"
    /// Version handshake: the watch app's "1.0.0 (65)", from its application context, every HR payload or the ping.
    @Published private(set) var watchBuild: String?
    /// The watch's HealthKit workout permission as the watch reports it ("allowed" | "denied" | "not asked").
    @Published private(set) var watchWorkoutAuth: String?
    @Published private(set) var hrBpm: Int?
    @Published private(set) var hrAt: Date?
    @Published private(set) var workoutState = "idle"
    @Published private(set) var workoutStateAt: Date?
    @Published private(set) var watchBattery: Int?
    @Published private(set) var hrReceived = 0
    /// Last time anything (reading or state) arrived from the watch, on either channel.
    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var ingest = WatchHRIngest()
    @Published private(set) var startRequestedAt: Date?

    weak var device: DeviceLink?
    /// Ride commands from the wrist ("start", "pause", "resume", "end", "endConfirm"); the app maps them to the one-owner rules.
    var onCommand: ((String) -> Void)?
    var onEvent: ((String) -> Void)?
    let mirror = WatchWorkoutMirror()
    private var lastContextAt: Date?

    override init() {
        super.init()
        mirror.onPayload = { [weak self] p in self?.handle(payload: p, via: .mirror) }
        mirror.onEvent = { [weak self] e in self?.onEvent?(e) }
    }

    var hrIsFresh: Bool { ingest.isFresh(now: Date()) }
    var version: WatchVersion.Comparison { WatchVersion.compare(phone: AppInfo.label, watch: watchBuild) }

    // MARK: start the watch workout from the iPhone
    /// Live heart rate exists only while the watch runs its workout. Apple's supported way for the iPhone to start it:
    /// HKHealthStore.startWatchApp(with:) launches/wakes the Cyclift watch app, which then starts the cycling workout
    /// (WatchAppDelegate.handle(_:) on the watch) and mirrors it back to this phone. No-op when no watch app is installed
    /// or the workout already runs. The first time, the phone's own HealthKit permission sheet is shown (workouts +
    /// heart rate — the same set as Profile › Apple Health), once.
    @Published private(set) var watchStartResult: String?
    private let hk = HKHealthStore()
    func startWatchWorkout(reason: String = "ride") {
        guard HKHealthStore.isHealthDataAvailable(), paired, appInstalled else { watchStartResult = "No paired watch with Cyclift installed"; return }
        if hrIsFresh || workoutState == "running" || mirror.remoteState == "running" { watchStartResult = "Watch workout already running"; return }
        startRequestedAt = Date()
        onEvent?("Starting the watch workout (\(reason))")
        let launch = { [weak self] in
            guard let self else { return }
            let cfg = HKWorkoutConfiguration(); cfg.activityType = .cycling; cfg.locationType = .outdoor
            self.watchStartResult = "Starting the watch workout…"
            self.hk.startWatchApp(with: cfg) { [weak self] ok, err in
                DispatchQueue.main.async {
                    self?.watchStartResult = ok ? "Watch workout requested — heart rate appears within a few seconds" : "Could not start the watch: \(err?.localizedDescription ?? "unknown error"). Open Cyclift on the watch and tap Start."
                    if !ok { self?.onEvent?("Watch start failed: \(err?.localizedDescription ?? "unknown")") }
                }
            }
        }
        if hk.authorizationStatus(for: HKObjectType.workoutType()) == .notDetermined {
            var read: Set<HKObjectType> = [HKObjectType.workoutType()]
            if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
            if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(e) }
            hk.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read) { _, _ in DispatchQueue.main.async { launch() } }
        } else { launch() }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        refresh(session)
    }

    func ping() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { lastResult = "Connection not ready yet"; return }
        guard session.isReachable else { lastResult = "Watch app not reachable. Open Cyclift on the watch and try again."; return }
        lastResult = "Sending…"
        session.sendMessage(WatchMessage.makePing(), replyHandler: { [weak self] reply in
            let ms = WatchMessage.roundTripMs(of: reply)
            let build = reply[WatchMessage.build] as? String
            DispatchQueue.main.async {
                if let b = build { self?.watchBuild = b }
                self?.lastResult = ms.map { "Watch replied in \($0) ms" } ?? "Watch sent an unexpected reply"
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async { self?.lastResult = "Failed: \(error.localizedDescription)" }
        })
    }

    private func refresh(_ session: WCSession) {
        let update = {
            self.activated = session.activationState == .activated
            self.paired = session.isPaired
            self.appInstalled = session.isWatchAppInstalled
            self.reachable = session.isReachable
            if session.activationState == .activated { self.applyContext(session.receivedApplicationContext) }
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    /// Mirror of the phone's ride for the watch: live message when reachable, application context (≤ every 10 s) otherwise.
    func sendRide(_ m: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var m = m; m[WatchMessage.phoneBuild] = AppInfo.label
        if session.isReachable { session.sendMessage(m, replyHandler: nil, errorHandler: nil) }
        else if lastContextAt == nil || Date().timeIntervalSince(lastContextAt!) > 10 { lastContextAt = Date(); try? session.updateApplicationContext(m) }
    }

    // MARK: incoming
    private func applyContext(_ c: [String: Any]) {
        guard c[WatchMessage.kind] as? String == WatchMessage.watchInfo else { return }
        if let b = c[WatchMessage.build] as? String { watchBuild = b }
        if let a = c[WatchMessage.hkWorkoutAuth] as? String { watchWorkoutAuth = a }
    }

    /// One path for both channels. Called on the main queue.
    func handle(payload p: WatchHRPayload, via ch: WatchHRIngest.Channel, now: Date = Date()) {
        lastDeliveryAt = now
        if !p.build.isEmpty { watchBuild = p.build }
        if p.state != workoutState { workoutState = p.state; workoutStateAt = now }
        if let b = p.battery { watchBattery = b }
        guard let bpm = p.bpm, bpm > 0 else { if !ingest.isFresh(now: now) { hrBpm = nil }; return }
        let at = Date(timeIntervalSince1970: p.at)
        guard ingest.offer(bpm: bpm, sampleAt: at, now: now, via: ch) == .accepted else { if !ingest.isFresh(now: now) { hrBpm = nil }; return }
        hrBpm = bpm; hrAt = at; hrReceived = ingest.totalAccepted
        device?.send(heartRate: bpm, source: .appleWatch, sampledAt: at)
    }

    private func handle(_ message: [String: Any]) {
        if message[WatchMessage.kind] as? String == WatchMessage.cmd, let c = message[WatchMessage.cmdKey] as? String {
            DispatchQueue.main.async { self.onCommand?(c) }
            return
        }
        if message[WatchMessage.kind] as? String == WatchMessage.watchInfo { DispatchQueue.main.async { self.applyContext(message) }; return }
        guard message[WatchMessage.kind] as? String == WatchMessage.hr else { return }
        let bpm = message[WatchMessage.bpm] as? Int
        let at = (message[WatchMessage.at] as? Double) ?? Date().timeIntervalSince1970
        let p = WatchHRPayload(bpm: (bpm ?? -1) > 0 ? bpm : nil, at: at, state: message[WatchMessage.workout] as? String ?? "idle",
                               build: message[WatchMessage.build] as? String ?? "", battery: message[WatchMessage.battery] as? Int, seq: 0)
        DispatchQueue.main.async { self.handle(payload: p, via: .connectivity) }
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refresh(session)
        if let error { DispatchQueue.main.async { self.lastResult = "Activation failed: \(error.localizedDescription)" } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) { refresh(session) }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }
    func sessionWatchStateDidChange(_ session: WCSession) { refresh(session) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { DispatchQueue.main.async { self.applyContext(applicationContext) } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) { handle(message); replyHandler([:]) }
}
